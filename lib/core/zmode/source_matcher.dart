import 'package:flutter/foundation.dart';

import '../error/exceptions.dart';
import '../models/media_item.dart';
import '../provider/cf_solve_needed.dart';
import '../repository/source_repository.dart';
import 'match_store.dart';
import 'playback_resolver.dart' show SweepReason;
import 'zmode_ids.dart';
import 'zmode_source_prefs.dart';

/// Thrown by playback when a metadata title has no source at all.
class NoSourceMatch implements Exception {
  const NoSourceMatch(
    this.canonical, {
    this.outcomes = const [],
    this.selectedSourceName,
  });
  final ZCanonical canonical;

  final List<({String sourceId, String name, SweepReason reason})> outcomes;
  final String? selectedSourceName;

  @override
  String toString() => 'No installed source has $canonical';
}

/// Thrown when a title's matched source has no episode with this number.
class EpisodeNotOnSource implements Exception {
  const EpisodeNotOnSource(this.canonical, this.episode);
  final ZCanonical canonical;
  final int episode;
  @override
  String toString() => 'Episode $episode is not on the source for $canonical';
}

/// Finds the source show behind a metadata title, one source at a time.
class SourceMatcher {
  SourceMatcher({
    required SourceRepository sources,
    required MatchStore store,
    required ZSourcePrefs prefs,
    required List<({String id, String name})> Function(ZKind) candidates,
    List<({String id, String name})> Function(ZKind)? sweepCandidates,
  }) : _sources = sources,
       _store = store,
       _prefs = prefs,
       _candidates = candidates,
       _sweepCandidates = sweepCandidates ?? candidates;

  final SourceRepository _sources;
  final MatchStore _store;
  final ZSourcePrefs _prefs;
  final List<({String id, String name})> Function(ZKind) _candidates;
  final List<({String id, String name})> Function(ZKind) _sweepCandidates;

  void Function(ZCanonical)? _onSourceChanged;

  void bindSourceChanged(void Function(ZCanonical) fn) => _onSourceChanged = fn;

  void _sourceChanged(ZCanonical c) => _onSourceChanged?.call(c);

  SourceMatch? saved(ZCanonical c) {
    final sel = sourceForTitle(c);
    return sel == null ? null : _store.get(c, sel);
  }

  String? sourceForTitle(ZCanonical c) {
    return pinnedSource(c) ?? _prefs.get(c.kind);
  }

  String? pinnedSource(ZCanonical c) {
    final sel = _prefs.get(c.kind);
    if (sel != null) {
      final m = _store.get(c, sel);
      if (m != null && m.pinned) return m.sourceId;
    }
    return null;
  }

  Future<void> chooseSource(ZCanonical c, String? sourceId) async {
    if (sourceId == null) {
      await clearAuto(c);
    } else {
      await _prefs.set(c.kind, sourceId);
      _sourceChanged(c);
    }
  }

  Future<void> selectSource(ZKind kind, String sourceId) async {
    await _prefs.set(kind, sourceId);
  }

  Future<void> clearAuto(ZCanonical c) async {
    _sourceChanged(c);
  }

  Future<SourceMatch?> pinTitleToSource(
    ZCanonical c,
    String sourceId, {
    required String title,
    String? altTitle,
    List<String> metadataAliases = const [],
    int? malId,
  }) async {
    await _prefs.set(c.kind, sourceId);
    final m = await resolveOn(
      c,
      sourceId,
      title: title,
      altTitle: altTitle,
      metadataAliases: metadataAliases,
      malId: malId,
    );
    if (m != null) {
      final pinnedMatch = SourceMatch(
        sourceId: m.sourceId,
        showUrl: m.showUrl,
        showId: m.showId,
        showTitle: m.showTitle,
        pinned: true,
      );
      await _store.save(c, pinnedMatch);
      _sourceChanged(c);
      return pinnedMatch;
    }
    _sourceChanged(c);
    return null;
  }

  Future<SourceMatch> pinManual(ZCanonical c, MediaItem item) async {
    await _prefs.set(c.kind, item.sourceId);
    final m = SourceMatch(
      sourceId: item.sourceId,
      showUrl: item.url,
      showId: item.id,
      showTitle: item.title,
      pinned: true,
    );
    await _store.save(c, m);
    _sourceChanged(c);
    return m;
  }

  Future<SourceMatch> pinForTitle(ZCanonical c, MediaItem item) => pinManual(c, item);

  String? cfBlockedUrl(ZKind kind) => null;

  /// Clean title of years, tags, brackets for clean provider queries
  static String _cleanSearchTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'\(\s*\d{4}\s*\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '')
        .replaceAll(RegExp(r'[:\-_\.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _fuzzyMatchTitle(String candidate, String target) {
    final c = candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final t = target.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.isEmpty || t.isEmpty) return false;
    return c.contains(t) || t.contains(c);
  }

  Future<SourceMatch?> resolveOn(
    ZCanonical c,
    String sourceId, {
    required String title,
    String? altTitle,
    List<String> metadataAliases = const [],
    int? malId,
    bool Function()? abandoned,
  }) async {
    final loaded = await _sources.ensureSourceLoaded(sourceId);
    if (!loaded) {
      debugPrint('[source-matcher] resolveOn · $sourceId → null (ensureSourceLoaded failed)');
      return null;
    }

    Future<List<MediaItem>?> searchFor(String q) async {
      if (abandoned?.call() ?? false) return null;
      try {
        final cleanQ = q.trim();
        if (cleanQ.isEmpty) return null;
        final results = await _sources.search(cleanQ, sourceId: sourceId);
        return (abandoned?.call() ?? false) ? null : results;
      } catch (e) {
        if (e is CloudflareRequiredException) {
          final host = Uri.tryParse(e.url)?.host ?? '';
          if (host.isNotEmpty) {
            CfSolveNeeded.needsSolve(host, e.url, sourceId: sourceId);
          }
        }
        debugPrint('[zmode] $sourceId search THREW for "$q": $e');
        return null;
      }
    }

    final cleanedTitle = _cleanSearchTitle(title);
    final queries = <String>{
      cleanedTitle,
      title,
      if (altTitle != null && altTitle.trim().isNotEmpty) ...[
        _cleanSearchTitle(altTitle),
        altTitle.trim(),
      ],
      for (final a in metadataAliases) ...[
        _cleanSearchTitle(a),
        a.trim(),
      ],
    }.where((q) => q.isNotEmpty).toList();

    MediaItem? matchedItem;

    for (final q in queries) {
      if (abandoned?.call() ?? false) return null;
      final results = await searchFor(q);
      if (results == null || results.isEmpty) continue;

      var hit = bestTitleMatch(
        results,
        title,
        altTitle: altTitle,
        metadataAliases: metadataAliases,
        wantedMalId: malId,
      );

      if (hit != null &&
          titleMatches(
            hit,
            title,
            altTitle: altTitle,
            metadataAliases: metadataAliases,
            wantedMalId: malId,
          )) {
        matchedItem = hit;
        break;
      }

      for (final item in results) {
        if (_fuzzyMatchTitle(item.title, cleanedTitle) ||
            (altTitle != null && _fuzzyMatchTitle(item.title, _cleanSearchTitle(altTitle)))) {
          matchedItem = item;
          break;
        }
      }

      if (matchedItem != null) break;
    }

    if (matchedItem == null) {
      debugPrint('[zmode] $sourceId REJECTED "$title"');
      return null;
    }

    final found = matchedItem;
    debugPrint('[zmode] $sourceId MATCHED "$title" -> "${found.title}"');
    final m = SourceMatch(
      sourceId: found.sourceId,
      showUrl: found.url,
      showId: found.id,
      showTitle: found.title,
      pinned: false,
    );
    if (abandoned?.call() ?? false) return null;
    await _store.save(c, m);
    return m;
  }

  Future<SourceMatch?> matchOn(
    ZCanonical c,
    String sourceId, {
    required String title,
    String? altTitle,
    List<String> metadataAliases = const [],
    int? malId,
    bool Function()? abandoned,
  }) async {
    if (abandoned?.call() ?? false) return null;
    final saved = _store.get(c, sourceId);
    final savedIsMatch = saved != null && saved.showUrl.isNotEmpty;
    if (savedIsMatch && (saved.pinned || _sources.hasSource(sourceId))) {
      final loaded = await _sources.ensureSourceLoaded(sourceId);
      if (abandoned?.call() ?? false) return null;
      return loaded ? saved : null;
    }
    if (!_sources.hasSource(sourceId)) return null;

    return resolveOn(
      c,
      sourceId,
      title: title,
      altTitle: altTitle,
      metadataAliases: metadataAliases,
      malId: malId,
      abandoned: abandoned,
    );
  }

  final Map<String, Future<SourceMatch?>> _inFlight = {};
  final Map<String, void Function()> _cancelInFlight = {};
  final Map<String, ({String sourceName, int current, int total})> _resolveProgress = {};
  final Map<String, Set<void Function(String sourceName, int current, int total)>>
      _resolveProgressListeners = {};

  void _publishProgress(String key, String sourceName, int current, int total) {
    final progress = (sourceName: sourceName, current: current, total: total);
    _resolveProgress[key] = progress;
    for (final listener in _resolveProgressListeners[key]?.toList() ?? const []) {
      listener(sourceName, current, total);
    }
  }

  void cancelResolve(ZCanonical c) => _cancelInFlight[c.key]?.call();

  Future<SourceMatch?> resolve(
    ZCanonical c, {
    required String title,
    String? altTitle,
    List<String> metadataAliases = const [],
    int? malId,
    bool Function()? abandoned,
    void Function(String sourceName, int current, int total)? onProgress,
  }) {
    if (onProgress != null) {
      _resolveProgressListeners.putIfAbsent(c.key, () => {}).add(onProgress);
      final progress = _resolveProgress[c.key];
      if (progress != null) {
        onProgress(progress.sourceName, progress.current, progress.total);
      }
    }
    final running = _inFlight[c.key];
    if (running != null) return running;
    var cancelled = false;
    void cancel() => cancelled = true;
    _cancelInFlight[c.key] = cancel;
    bool gone() => cancelled || (abandoned?.call() ?? false);

    final f = _resolve(
      c,
      title: title,
      altTitle: altTitle,
      metadataAliases: metadataAliases,
      malId: malId,
      abandoned: gone,
      onProgress: (sourceName, current, total) =>
          _publishProgress(c.key, sourceName, current, total),
    ).whenComplete(() {
      _inFlight.remove(c.key);
      _resolveProgress.remove(c.key);
      _resolveProgressListeners.remove(c.key);
      if (identical(_cancelInFlight[c.key], cancel)) {
        _cancelInFlight.remove(c.key);
      }
    });
    _inFlight[c.key] = f;
    return f;
  }

  Future<SourceMatch?> _resolve(
    ZCanonical c, {
    required String title,
    String? altTitle,
    List<String> metadataAliases = const [],
    int? malId,
    bool Function()? abandoned,
    void Function(String sourceName, int current, int total)? onProgress,
  }) async {
    if (abandoned?.call() ?? false) return null;
    final candidates = _candidates(c.kind);
    final pinned = pinnedSource(c);
    if (pinned != null) {
      return matchOn(
        c,
        pinned,
        title: title,
        altTitle: altTitle,
        metadataAliases: metadataAliases,
        malId: malId,
        abandoned: abandoned,
      );
    }

    final selId = _prefs.get(c.kind);
    if (selId != null && candidates.any((s) => s.id == selId)) {
      return matchOn(
        c,
        selId,
        title: title,
        altTitle: altTitle,
        metadataAliases: metadataAliases,
        malId: malId,
        abandoned: abandoned,
      );
    }

    final sweep = _sweepCandidates(c.kind);
    final isReading = c.kind == ZKind.manga || c.kind == ZKind.novel;
    final remembered = isReading ? _prefs.lastGood(c.kind) : null;
    if (remembered != null && sweep.any((s) => s.id == remembered)) {
      return matchOn(
        c,
        remembered,
        title: title,
        altTitle: altTitle,
        metadataAliases: metadataAliases,
        malId: malId,
      );
    }

    for (var i = 0; i < sweep.length; i++) {
      if (abandoned?.call() ?? false) return null;
      final s = sweep[i];
      onProgress?.call(s.name, i + 1, sweep.length);

      final match = await matchOn(
        c,
        s.id,
        title: title,
        altTitle: altTitle,
        metadataAliases: metadataAliases,
        malId: malId,
        abandoned: abandoned,
      );
      if (match != null) {
        _sourceChanged(c);
        return match;
      }
    }
    return null;
  }
}
