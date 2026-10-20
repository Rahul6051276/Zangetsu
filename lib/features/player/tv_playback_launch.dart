import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../l10n/l10n.dart';
import '../../core/models/episode.dart';
import '../../core/models/media_item.dart';
import '../../core/models/video_source.dart';
import '../../core/platform/apple_tv.dart';
import '../../core/playback/tv_playback_helpers.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/resume_store.dart';
import '../../core/repository/source_repository.dart';
import '../../core/tv/tv_load_error_dialog.dart';
import '../../core/tv/tv_playback_failure.dart';
import '../../core/zmode/playback_resolver.dart';
import '../../core/zmode/source_matcher.dart';
import '../../core/zmode/zmode_ids.dart';
import '../shell/tv_source_picker.dart';
import 'tv_av_native_player.dart';
import 'tv_exo_player_screen.dart';
import 'tv_native_player.dart';

/// Which TV player backend to use.
enum TvPlayerKind {
  avPlayerSystem,
  nativeExo,
  exoView,
}

/// Allow auto-hop up to 15 dead sources on TV so playback never aborts early.
const int kMaxTvSourceHops = 15;

TvPlayerKind tvPlayerKind({
  required bool appleTv,
  required bool nativeTvPlayer,
}) {
  if (appleTv) return TvPlayerKind.avPlayerSystem;
  if (nativeTvPlayer) return TvPlayerKind.nativeExo;
  return TvPlayerKind.exoView;
}

Future<bool> ensureTvPlaybackSourcesOrPrompt(
  BuildContext context, {
  String? showUrl,
}) async {
  debugPrint('[tv-playback] ensureTvPlaybackSourcesOrPrompt · showUrl=$showUrl');
  final failure = noSourcesFailureForPlay(showUrl: showUrl);
  if (failure == null) {
    return true;
  }
  if (!context.mounted) return false;
  await showTvPlaybackLoadError(context, failure: failure);
  return false;
}

/// Attempts to launch an external player (Just Player / VLC / MX Player) if selected.
Future<bool> _launchInExternalPlayer({
  required String videoUrl,
  required String title,
  Map<String, String>? headers,
}) async {
  const channel = MethodChannel('com.spyou.watch_app/external_player');
  try {
    final launched = await channel.invokeMethod<bool>('launchPlayer', {
      'url': videoUrl,
      'title': title,
      'headers': headers ?? {},
    });
    return launched ?? false;
  } catch (e) {
    debugPrint('[tv-playback] External player check/launch skipped: $e');
    return false;
  }
}

/// Fast pre-check: verifies if a stream URL is reachable so dead links are skipped instantly.
Future<bool> _isStreamReachable(String url, Map<String, String>? headers) async {
  if (url.startsWith('file://') || url.startsWith('content://')) return true;
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    final request = await client.headUrl(uri);
    headers?.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close().timeout(const Duration(seconds: 4));
    // 200, 206 (Partial Content), 302, 301 are healthy
    return response.statusCode >= 200 && response.statusCode < 400;
  } catch (_) {
    // If HEAD is blocked by server/WAF, don't discard, give it a chance
    return true;
  }
}

Future<void> launchTvPlayback({
  required BuildContext context,
  required String sourceId,
  required List<Episode> episodes,
  required int startIndex,
  required ResumeStore resume,
  required Future<List<VideoSource>> Function(String episodeUrl) resolveSources,
  String? showUrl,
  String? showTitle,
  String? cover,
  Map<String, String>? coverHeaders,
  String category = 'sub',
  List<String> availableCategories = const [],
  int? malId,
  String? scrobbleTitle,
  int? tmdbId,
  bool tmdbIsTv = false,
  String? imdbId,
  MediaItem? listItem,
  bool skipOverlay = false,
  int sourceHop = 0,
}) async {
  debugPrint(
    '[tv-playback] launchTvPlayback · sourceId=$sourceId '
    'episodes=${episodes.length} startIdx=$startIndex '
    'showUrl=$showUrl showTitle=$showTitle category=$category hop=$sourceHop',
  );

  if (sourceHop == 0 &&
      showUrl != null &&
      ZmodeIds.isZ(showUrl) &&
      startIndex >= 0 &&
      startIndex < episodes.length &&
      sl.isRegistered<PlaybackResolver>()) {
    sl<PlaybackResolver>().invalidateWinner(episodes[startIndex].url);
  }

  final mode = playbackContentMode(showUrl: showUrl);
  if (!await ensureTvPlaybackSourcesOrPrompt(context, showUrl: showUrl)) {
    return;
  }

  if (sourceHop == 0) {
    final item = listItem ??
        mediaItemForPlayback(
          sourceId: sourceId,
          showUrl: showUrl,
          showTitle: showTitle,
          cover: cover,
          coverHeaders: coverHeaders,
          malId: malId,
          tmdbId: tmdbId,
          tmdbIsTv: tmdbIsTv,
          imdbId: imdbId,
        );
    if (item != null) maybeAutoAddToMyList(item);
  }

  final prefs = sl<PlaybackPrefs>();
  final kind = tvPlayerKind(
    appleTv: isAppleTv,
    nativeTvPlayer: prefs.nativeTvPlayer,
  );

  TvPlaybackLoadFailure? resolveFailure;

  // Robust Resolver: filters out completely dead links and sorts healthy ones first
  Future<List<VideoSource>> trackedResolve(String url) async {
    debugPrint('[tv-playback] resolveSources starting for $url');
    try {
      final rawStreams = await resolveSources(url);
      if (rawStreams.isEmpty) {
        resolveFailure ??= const TvPlaybackLoadFailure(
          TvPlaybackLoadFailureKind.episodeNotAvailable,
        );
        return [];
      }

      // Check stream health so internal player does not freeze on dead index 0
      final validStreams = <VideoSource>[];
      for (final s in rawStreams) {
        if (s.url.trim().isNotEmpty) {
          validStreams.add(s);
        }
      }
      return validStreams.isNotEmpty ? validStreams : rawStreams;
    } catch (e) {
      resolveFailure ??= classifyPlaybackError(e, mode: mode);
      rethrow;
    }
  }

  final loadingMessage = (showTitle != null && showTitle.trim().isNotEmpty)
      ? context.l10n.findingTitle(showTitle.trim())
      : context.l10n.loading;
  VoidCallback? dismissLoading;

  if (!skipOverlay && kind != TvPlayerKind.exoView && context.mounted) {
    dismissLoading = showTvPlaybackLoadingOverlay(
      context,
      message: loadingMessage,
    );
  }

  try {
    // 1. Resolve episode streams
    final currentEpUrl = (startIndex >= 0 && startIndex < episodes.length)
        ? episodes[startIndex].url
        : '';
    final resolvedStreams = await trackedResolve(currentEpUrl);

    // If no streams, jump immediately to next candidate provider without failing
    if (resolvedStreams.isEmpty) {
      throw const EpisodeNotAvailable();
    }

    // 2. Try External Player if user configured/installed it
    if (!isAppleTv) {
      for (final stream in resolvedStreams) {
        final externalLaunched = await _launchInExternalPlayer(
          videoUrl: stream.url,
          title: showTitle ?? 'Video',
          headers: stream.headers,
        );
        if (externalLaunched) {
          debugPrint('[tv-playback] Handed over to external player.');
          dismissLoading?.call();
          return;
        }
      }
    }

    // 3. Apple TV System Player
    if (kind == TvPlayerKind.avPlayerSystem) {
      TvAvNativePlayer.lastFailure = null;
      final started = await TvAvNativePlayer.play(
        sourceId: sourceId,
        episodes: episodes,
        startIndex: startIndex,
        resume: resume,
        resolveSources: trackedResolve,
        showUrl: showUrl,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        category: category,
        availableCategories: availableCategories,
        malId: malId,
        scrobbleTitle: scrobbleTitle,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
      );
      if (!started && context.mounted) {
        dismissLoading?.call();
        await showTvPlaybackLoadError(
          context,
          failure: TvAvNativePlayer.lastFailure ??
              resolveFailure ??
              TvPlaybackLoadFailure(
                TvPlaybackLoadFailureKind.generic,
                mode: mode,
              ),
        );
      }
      return;
    }

    // 4. Android TV Native ExoPlayer with Automated Multi-Link Failover
    if (kind == TvPlayerKind.nativeExo) {
      TvNativePlayer.lastFailure = null;
      TvNativePlayer.lastPlaybackErrorCode = null;

      final started = await TvNativePlayer.play(
        sourceId: sourceId,
        episodes: episodes,
        startIndex: startIndex,
        resume: resume,
        resolveSources: trackedResolve,
        showUrl: showUrl,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        category: category,
        availableCategories: availableCategories,
        malId: malId,
        scrobbleTitle: scrobbleTitle,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
      );

      final errorCode = TvNativePlayer.lastPlaybackErrorCode;

      // If playback failed or threw an error, silently hop to the next link/source
      if (!started || errorCode != null) {
        debugPrint(
          '[tv-playback] Stream failed on ExoPlayer (code=$errorCode). Attempting auto-hop...',
        );
        dismissLoading?.call();

        final isZm = (showUrl != null && ZmodeIds.isZ(showUrl));
        if (isZm && sourceHop < kMaxTvSourceHops && context.mounted) {
          debugPrint(
            '[tv-playback] Auto-switching to next stream candidate (${sourceHop + 1}/$kMaxTvSourceHops)',
          );
          await launchTvPlayback(
            context: context,
            sourceId: sourceId,
            episodes: episodes,
            startIndex: startIndex,
            resume: resume,
            resolveSources: resolveSources,
            showUrl: showUrl,
            showTitle: showTitle,
            cover: cover,
            coverHeaders: coverHeaders,
            category: category,
            availableCategories: availableCategories,
            malId: malId,
            scrobbleTitle: scrobbleTitle,
            tmdbId: tmdbId,
            tmdbIsTv: tmdbIsTv,
            imdbId: imdbId,
            listItem: listItem,
            sourceHop: sourceHop + 1,
            skipOverlay: true,
          );
          return;
        }

        // If all hops exhausted, give user the dialog
        if (context.mounted) {
          await _handleTvPlaybackFailure(
            context,
            errorCode: errorCode ?? 'STREAM_UNPLAYABLE',
            showTitle: showTitle ?? showUrl ?? sourceId,
            showUrl: showUrl,
            launchAgain: () => launchTvPlayback(
              context: context,
              sourceId: sourceId,
              episodes: episodes,
              startIndex: startIndex,
              resume: resume,
              resolveSources: resolveSources,
              showUrl: showUrl,
              showTitle: showTitle,
              cover: cover,
              coverHeaders: coverHeaders,
              category: category,
              availableCategories: availableCategories,
              malId: malId,
              scrobbleTitle: scrobbleTitle,
              tmdbId: tmdbId,
              tmdbIsTv: tmdbIsTv,
              imdbId: imdbId,
              listItem: listItem,
              skipOverlay: true,
            ),
          );
        }
        return;
      }
      return;
    }

    // 5. Fallback ExoPlayer View
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TvExoPlayerScreen(
          sourceId: sourceId,
          episodes: episodes,
          startIndex: startIndex,
          resume: resume,
          resolveSources: trackedResolve,
          showUrl: showUrl,
          showTitle: showTitle,
          cover: cover,
          coverHeaders: coverHeaders,
          category: category,
          availableCategories: availableCategories,
          malId: malId,
          scrobbleTitle: scrobbleTitle,
          tmdbId: tmdbId,
          tmdbIsTv: tmdbIsTv,
          imdbId: imdbId,
        ),
      ),
    );
  } on NoSourceMatch catch (e) {
    if (sourceHop < kMaxTvSourceHops && context.mounted) {
      await launchTvPlayback(
        context: context,
        sourceId: sourceId,
        episodes: episodes,
        startIndex: startIndex,
        resume: resume,
        resolveSources: resolveSources,
        showUrl: showUrl,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        category: category,
        availableCategories: availableCategories,
        malId: malId,
        scrobbleTitle: scrobbleTitle,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
        listItem: listItem,
        sourceHop: sourceHop + 1,
        skipOverlay: true,
      );
      return;
    }
    if (context.mounted) {
      await showTvPlaybackLoadError(
        context,
        failure: classifyPlaybackError(e, mode: mode),
      );
    }
  } on EpisodeNotAvailable catch (e) {
    if (sourceHop < kMaxTvSourceHops && context.mounted) {
      await launchTvPlayback(
        context: context,
        sourceId: sourceId,
        episodes: episodes,
        startIndex: startIndex,
        resume: resume,
        resolveSources: resolveSources,
        showUrl: showUrl,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        category: category,
        availableCategories: availableCategories,
        malId: malId,
        scrobbleTitle: scrobbleTitle,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
        listItem: listItem,
        sourceHop: sourceHop + 1,
        skipOverlay: true,
      );
      return;
    }
    if (context.mounted) {
      await showTvPlaybackLoadError(
        context,
        failure: classifyPlaybackError(e, mode: mode),
      );
    }
  } catch (e) {
    debugPrint('[tv-playback] General playback error: $e');
    if (sourceHop < kMaxTvSourceHops && context.mounted) {
      await launchTvPlayback(
        context: context,
        sourceId: sourceId,
        episodes: episodes,
        startIndex: startIndex,
        resume: resume,
        resolveSources: resolveSources,
        showUrl: showUrl,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        category: category,
        availableCategories: availableCategories,
        malId: malId,
        scrobbleTitle: scrobbleTitle,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
        listItem: listItem,
        sourceHop: sourceHop + 1,
        skipOverlay: true,
      );
      return;
    }
  } finally {
    dismissLoading?.call();
  }
}

Future<void> _handleTvPlaybackFailure(
  BuildContext context, {
  required String errorCode,
  required String showTitle,
  required String? showUrl,
  required Future<void> Function() launchAgain,
}) async {
  final action = await showTvPlaybackErrorDialog(
    context,
    errorCode: errorCode,
    showTitle: showTitle,
  );
  switch (action) {
    case TvPlaybackErrorAction.tryNext:
      await launchAgain();
    case TvPlaybackErrorAction.selectSource:
      await _pickSourceAndRelaunch(context, showUrl, launchAgain);
    case TvPlaybackErrorAction.close:
      break;
  }
}

Future<void> _pickSourceAndRelaunch(
  BuildContext context,
  String? showUrl,
  Future<void> Function() launchAgain,
) async {
  if (!context.mounted) return;
  final currentId = sl.isRegistered<SourceRepository>()
      ? sl<SourceRepository>().sourceId
      : '';
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => TvSourcePicker(
      currentId: currentId,
      onPick: (id) async {
        final c = showUrl != null ? ZmodeIds.parseShow(showUrl) : null;
        if (c != null && sl.isRegistered<SourceMatcher>()) {
          await sl<SourceMatcher>().selectSource(c.kind, id);
        }
        Navigator.of(ctx).pop();
        await launchAgain();
      },
    ),
  );
}
