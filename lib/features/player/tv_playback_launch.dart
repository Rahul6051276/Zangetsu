import 'dart:async';
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

enum TvPlayerKind {
  avPlayerSystem,
  nativeExo,
  exoView,
}

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

Future<bool> _launchInExternalPlayer({
  required String videoUrl,
  required String title,
  required String package,
  Map<String, String>? headers,
}) async {
  final channels = [
    const MethodChannel('com.spyou.watch_app/external_player'),
    const MethodChannel('app.spyou.zangetsu/external_player'),
  ];

  for (final channel in channels) {
    try {
      final launched = await channel.invokeMethod<bool>('launchPlayer', {
        'url': videoUrl,
        'title': title,
        'package': package,
        'headers': headers ?? {},
      });
      if (launched == true) return true;
    } catch (_) {}
  }

  // Fallback to Android VIEW Intent channel if custom player channel fails
  try {
    const intentChannel = MethodChannel('com.spyou.watch_app/intent');
    final launched = await intentChannel.invokeMethod<bool>('launchUrl', {
      'url': videoUrl,
      'package': package,
      'mimeType': 'video/*',
      'title': title,
      'headers': headers ?? {},
    });
    if (launched == true) return true;
  } catch (e) {
    debugPrint('[tv-playback] External player intent fallback failed: $e');
  }

  return false;
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
      sl.is
