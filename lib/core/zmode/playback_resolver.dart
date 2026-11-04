import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/episode.dart';
import '../models/video_source.dart';
import '../playback/source_health_store.dart';
import '../di/injector.dart';
import '../provider/cf_solve_needed.dart';
import '../provider/cloudstream_provider.dart';
import '../provider/js_engine.dart';
import '../provider/provider_manager.dart';
import '../repository/source_repository.dart';
import 'match_store.dart';
import 'source_matcher.dart';
import 'source_order_prefs.dart';
import 'source_score_store.dart';
import 'zmode_ids.dart';
import 'zmode_source_prefs.dart';

enum SweepReason {
  timedOut,
  cloudflare,
  unhealthy,
  cooldown,
  failed,
  streamsDead,
  noTitleMatch,
  episodeMissing,
  noStreams,
}

typedef SweepOutcome = ({String sourceId, String name, SweepReason reason});

String? sweepFailureDetail(List<SweepOutcome> outcomes) {
  String names(SweepReason r) {
    final n = outcomes.where((o) => o.reason == r).map((o) => o.name).toList();
    if (n.isEmpty) return '';
    if (n.length == 1) return n.first;
    if (n.length == 2) return '${n[0]} and ${n[1]}';
    return '${n.first} and ${n.length - 1} others';
  }

  final slow = names(SweepReason.timedOut);
  final deadLinks = names(SweepReason.streamsDead);
  final cf = names(SweepReason.cloudflare);
  final cooling = names(SweepReason.cooldown);
  final unwell = names(SweepReason.unhealthy);

  if (slow.isNotEmpty) return '$slow took too long to answer';
  if (deadLinks.isNotEmpty) return '$deadLinks gave links that would not open';
  if (cf.isNotEmpty) return '$cf needs a Cloudflare check';
  if (cooling.isNotEmpty) return '$cooling was skipped after a recent timeout';
  if (unwell.isNotEmpty) return '$unwell is not responding';
  return null;
}

class EpisodeNotAvailable implements Exception {
  const EpisodeNotAvailable(
    this.canonical,
    this.episode, {
    this.hadTitleMatch = false,
    this.outcomes = const [],
    this.selectedSourceName,
  });
  final ZCanonical canonical;
  final int episode;
  final bool hadTitleMatch;
  final List<SweepOutcome> outcomes;
  final String? selectedSourceName;

  @override
  String toString() => hadTitleMatch
      ? 'Episode $episode is not available on any source for $canonical'
      : 'No installed source has $canonical';
}

class PlaybackAborted implements Exception {
  const PlaybackAborted();

  @override
  String toString() => 'Playback sweep abandoned — the viewer left';
}

class ResolvedPlayback {
  const ResolvedPlayback({
    required this.match,
    required this.episodeUrl,
    required this.streams,
    required this.show,
    required this.episode,
  });

  final SourceMatch match;
  final String episodeUrl;
  final List<VideoSource> streams;
  final ZCanonical show;
  final int episode;
}

class ProgressiveResolve {
  const ProgressiveResolve({
    required this.match,
    required this.episodeUrl,
    required this.streams,
    required this.done,
  });

  final SourceMatch match;
  final String episodeUrl;
  final List<VideoSource> streams;
  final bool done;
}

class PlaybackResolver {
  PlaybackResolver({
    required SourceMatcher matcher,
    required SourceRepository sources,
    required MatchStore store,
    required ZSourcePrefs prefs,
    required SourceHealthStore health,
    required List<({String id, String name})> Function(ZKind) candidates,
    Duration? perSourceBudget,
    Duration? chosenBudget,
    Duration? relaxedBudget,
    SourceScoreStore? scores,
  })  : _budget = perSourceBudget ?? defaultPerSourceBudget,
        _chosenBudget = chosenBudget ?? chosenSourceBudget,
        _relaxedBudget =
            relaxedBudget ?? perSourceBudget ?? relaxedPerSourceBudget,
        _matcher = matcher,
        _sources = sources,
        _store = store,
        _prefs = prefs,
        _health = health,
        _candidates = candidates,
        _scores = scores;

  final SourceMatcher _matcher;
  final SourceRepository _sources;
  final MatchStore _store;
  final ZSourcePrefs _prefs;
  final SourceHealthStore _health;
  final List<({String id, String name})> Function(ZKind) _candidates;
  final SourceScoreStore? _scores;
  late Future<({String title, String? alt, int? malId})> Function(ZCanonical c)
      _titleLookup;

  void bindTitleLookup(
    Future<({String title, String? alt, int? malId})> Function(ZCanonical c) fn,
  ) {
    _titleLookup = fn;
  }

  final Map<String, ({String episodeUrl, String sourceId, SourceMatch match})>
      _winners = {};

  static String _winKey(String zmEpisodeUrl, String category) =>
      '$zmEpisodeUrl|$category';

  final Map<String, Future<ResolvedPlayback>> _inFlight = {};

  static const Duration defaultPerSourceBudget = Duration(seconds: 8);
  final Duration _budget;
  static const int sweepWaveSize = 3;
  static const Duration relaxedPerSourceBudget = Duration(seconds: 20);
  final Duration _relaxedBudget;
  static const Duration chosenSourceBudget = Duration(seconds: 25);
  final Duration _chosenBudget;

  Duration _budgetFor(String sourceId, Set<String> chosen) {
    if (!JsEngine.runsOffUiIsolate) return _budget;
    return chosen.contains(sourceId) ? _chosenBudget : _relaxedBudget;
  }

  Set<String> _chosenSources(ZCanonical c) => {
        ?_matcher.pinnedSource(c),
        ?_prefs.get(c.kind),
      };

  static const Duration probeBudget = Duration(seconds: 5);

  final Map<String, DateTime> _overBudget = {};
  static const Duration overBudgetCooldown = Duration(minutes: 10);
  final Map<String, Set<String>> _unplayable = {};

  void markSourceUnplayable(
    String zmEpisodeUrl,
    String sourceId, {
    String category = 'sub',
  }) {
    final key = _winKey(zmEpisodeUrl, category);
    (_unplayable[key] ??= <String>{}).add(sourceId);
    _winners.remove(key);
    _noSource.remove(key);
    debugPrint(
      '[playback] markSourceUnplayable · $sourceId for $zmEpisodeUrl '
      '($category) — ${_unplayable[key]!.length} now excluded',
    );
  }

  int unplayableCount(String zmEpisodeUrl, {String category = 'sub'}) =>
      _unplayable[_winKey(zmEpisodeUrl, category)]?.length ?? 0;

  int _sweepGen = 0;

  void abortSweeps() {
    _sweepGen++;
    if (!_abortSignal.isCompleted) _abortSignal.complete();
    _abortSignal = Completer<void>();
    unawaited(CloudStreamProvider.cancelInFlightLinks());
  }

  Completer<void> _abortSignal = Completer<void>();

  final Map<String, ({DateTime at, bool hadTitleMatch})> _noSource = {};
  static const Duration noSourceCooldown = Duration(minutes: 5);

  bool _recentlyOverBudget(String id) {
    final at = _overBudget[id];
    if (at == null) return false;
    if (DateTime.now().difference(at) < overBudgetCooldown) return true;
    _overBudget.remove(id);
    return false;
  }

  Future<ResolvedPlayback> resolveForPlayback(
    String zmEpisodeUrl, {
    bool fast = false,
    String category = 'sub',
    bool Function(List<VideoSource> streams)? accept,
  }) {
    final flightKey = _winKey(zmEpisodeUrl, category);
    if (accept == null) {
      final running = _inFlight[flightKey];
      if (running != null) return running;
    }
    final miss = _noSource[flightKey];
    if (miss != null) {
      if (DateTime.now().difference(miss.at) < noSourceCooldown) {
        debugPrint(
          '[playback] resolveForPlayback · $zmEpisodeUrl → no source '
          '(remembered, skipping the sweep)',
        );
        final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
        return Future.error(
          p == null || !miss.hadTitleMatch
              ? NoSourceMatch(p?.show ?? const ZCanonical(ZKind.anime, ''))
              : EpisodeNotAvailable(p.show, p.episode, hadTitleMatch: true),
        );
      }
      _noSource.remove(flightKey);
    }
    if (accept != null) {
      return _resolve(
        zmEpisodeUrl,
        fast: fast,
        category: category,
        accept: accept,
      );
    }
    final f = _resolve(zmEpisodeUrl, fast: fast, category: category)
        .whenComplete(() {
      _inFlight.remove(flightKey);
    });
    _inFlight[flightKey] = f;
    return f;
  }

  Stream<ProgressiveResolve> resolveProgressive(
    String zmEpisodeUrl, {
    String category = 'sub',
    bool stopAfterFirstWave = false,
  }) async* {
    final gen = _sweepGen;
    final abortFuture = _abortSignal.future.then<_Attempt?>((_) => null);
    final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (p == null) {
      throw ArgumentError('not a metadata episode url: $zmEpisodeUrl');
    }
    final flightKey = _winKey(zmEpisodeUrl, category);
    final miss = _noSource[flightKey];
    if (miss != null) {
      if (DateTime.now().difference(miss.at) < noSourceCooldown) {
        if (!miss.hadTitleMatch) throw NoSourceMatch(p.show);
        throw EpisodeNotAvailable(p.show, p.episode, hadTitleMatch: true);
      }
      _noSource.remove(flightKey);
    }
    final hit = _winners[flightKey];
    if (hit != null) {
      final streams = await Future.any<List<VideoSource>>([
        _sources.sources(hit.episodeUrl, sourceId: hit.sourceId, fast: true),
        abortFuture.then<List<VideoSource>>(
          (_) => throw const PlaybackAborted(),
        ),
      ]);
      if (gen != _sweepGen) throw const PlaybackAborted();
      if (streams.isNotEmpty) {
        yield ProgressiveResolve(
          match: hit.match,
          episodeUrl: hit.episodeUrl,
          streams: streams,
          done: true,
        );
        return;
      }
      _winners.remove(flightKey);
    }
    final t = await _titleLookup(p.show);
    final selectedSource = _matcher.sourceForTitle(p.show);
    final ordered = _orderedCandidates(p.show);
    if (ordered.isEmpty) {
      throw NoSourceMatch(p.show);
    }

    final chosen = _chosenSources(p.show);
    final dead =
        _unplayable[_winKey(zmEpisodeUrl, category)] ?? const <String>{};
    final outcomes = <SweepOutcome>[];
    void note(String sourceId, SweepReason reason) => outcomes.add((
          sourceId: sourceId,
          name: _sources.displayName(sourceId),
          reason: reason,
        ));

    var hadTitleMatch = false;

    Future<_Attempt?> ask(String sourceId) async {
      _Attempt? attempt;
      final budget = _budgetFor(sourceId, chosen);
      try {
        final call = _tryCandidate(
          p,
          sourceId,
          t,
          fast: true,
          category: category,
          onTitleMatch: () => hadTitleMatch = true,
          onMiss: (reason) => note(sourceId, reason),
        ).timeout(budget);
        attempt = await Future.any<_Attempt?>([call, abortFuture]);
        if (attempt == null) {
          unawaited(call.then<void>((_) {}, onError: (_) {}));
        }
      } on TimeoutException {
        _overBudget[sourceId] = DateTime.now();
        note(sourceId, SweepReason.timedOut);
      } catch (_) {
        note(sourceId, SweepReason.failed);
      }
      return attempt;
    }

    final acc = <VideoSource>[];
    final seenUrls = <String>{};
    _Attempt? firstHit;
    var winnerWritten = false;

    Future<ProgressiveResolve> recordHit(_Attempt attempt) async {
      if (!winnerWritten) {
        winnerWritten = true;
        firstHit = attempt;
        _winners[_winKey(zmEpisodeUrl, category)] = (
          episodeUrl: attempt.episodeUrl,
          sourceId: attempt.match.sourceId,
          match: attempt.match,
        );
        if (!attempt.match.pinned) {
          await _store.rememberLastPlayed(p.show, attempt.match.sourceId);
          await _scores?.bump(attempt.match.sourceId);
        }
      }
      for (final s in attempt.streams) {
        if (seenUrls.add(s.url)) acc.add(s);
      }
      return ProgressiveResolve(
        match: attempt.match,
        episodeUrl: attempt.episodeUrl,
        streams: [...acc],
        done: false,
      );
    }

    if (selectedSource != null) {
      final attempt = await ask(selectedSource);
      if (gen != _sweepGen) throw const PlaybackAborted();
      if (attempt != null) {
        final event = await recordHit(attempt);
        yield ProgressiveResolve(
          match: event.match,
          episodeUrl: event.episodeUrl,
          streams: event.streams,
          done: true,
        );
        return;
      }
    }

    for (var start = 0;
        selectedSource == null && start < ordered.length;
        start += sweepWaveSize) {
      if (gen != _sweepGen) {
        throw const PlaybackAborted();
      }

      final wave = <String>[];
      for (final sourceId in ordered.skip(start).take(sweepWaveSize)) {
        if (dead.contains(sourceId)) {
          note(sourceId, SweepReason.streamsDead);
          continue;
        }
        if (CfSolveNeeded.sourceFlagged(sourceId)) {
          note(sourceId, SweepReason.cloudflare);
          continue;
        }
        if (_health.isSkippable(sourceId)) {
          note(sourceId, SweepReason.unhealthy);
          continue;
        }
        if (_recentlyOverBudget(sourceId)) {
          note(sourceId, SweepReason.cooldown);
          continue;
        }
        wave.add(sourceId);
      }
      if (wave.isEmpty) continue;

      final pending = <String, Future<_Attempt?>>{
        for (final id in wave) id: ask(id),
      };
      final verdicts = <String, _Attempt?>{};
      var cursor = 0;
      while (verdicts.length < pending.length) {
        final landed = await Future.any([
          for (final entry in pending.entries)
            if (!verdicts.containsKey(entry.key))
              entry.value.then<({String id, _Attempt? attempt})>(
                (a) => (id: entry.key, attempt: a),
              ),
        ]);
        verdicts[landed.id] = landed.attempt;
        if (gen != _sweepGen) {
          throw const PlaybackAborted();
        }
        while (cursor < wave.length && verdicts.containsKey(wave[cursor])) {
          final id = wave[cursor++];
          final attempt = verdicts[id];
          if (attempt == null) continue;
          yield await recordHit(attempt);
        }
      }
      if (stopAfterFirstWave && firstHit != null) break;
    }

    final done = firstHit;
    if (done == null) {
      final blocked = _matcher.cfBlockedUrl(p.show.kind);
      if (blocked != null && !hadTitleMatch) {
        debugPrint(
          '[playback] resolveProgressive · CF blocked for kind=${p.show.kind} '
          'url=$blocked',
        );
      }
      _noSource[_winKey(zmEpisodeUrl, category)] = (
        at: DateTime.now(),
        hadTitleMatch: hadTitleMatch,
      );
      if (hadTitleMatch) {
        throw EpisodeNotAvailable(
          p.show,
          p.episode,
          hadTitleMatch: true,
          outcomes: outcomes,
          selectedSourceName: selectedSource == null
              ? null
              : _sources.displayName(selectedSource),
        );
      }
      throw NoSourceMatch(
        p.show,
        outcomes: outcomes,
        selectedSourceName: selectedSource == null
            ? null
            : _sources.displayName(selectedSource),
      );
    }
    yield ProgressiveResolve(
      match: done.match,
      episodeUrl: done.episodeUrl,
      streams: [...acc],
      done: true,
    );
  }

  Future<ResolvedPlayback> _resolve(
    String zmEpisodeUrl, {
    required bool fast,
    String category = 'sub',
    bool Function(List<VideoSource> streams)? accept,
  }) async {
    final gen = _sweepGen;
    final abortFuture = _abortSignal.future.then<_Attempt?>((_) => null);
    final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (p == null) {
      debugPrint('[playback] _resolve → ArgumentError: not a zm episode url');
      throw ArgumentError('not a metadata episode url: $zmEpisodeUrl');
    }
    debugPrint(
      '[playback] _resolve · url=$zmEpisodeUrl episode=${p.episode} '
      'show=${p.show.kind}/${p.show.id} fast=$fast',
    );
    final t = await _titleLookup(p.show);
    debugPrint(
      '[playback] _resolve · titleLookup → "${t.title}" '
      '(alt="${t.alt}" malId=${t.malId})',
    );

    final pinned = _matcher.pinnedSource(p.show);
    final ordered = _orderedCandidates(p.show);
    debugPrint(
      '[playback] _resolve · ${ordered.length} ordered candidates '
      '(${ordered.join(", ")})',
    );
    if (ordered.isEmpty) {
      debugPrint('[playback] _resolve → NoSourceMatch (no candidates)');
      throw NoSourceMatch(p.show);
    }

    final chosen = _chosenSources(p.show);
    final dead =
        _unplayable[_winKey(zmEpisodeUrl, category)] ?? const <String>{};
    final outcomes = <SweepOutcome>[];
    void note(String sourceId, SweepReason reason) => outcomes.add((
          sourceId: sourceId,
          name: _sources.displayName(sourceId),
          reason: reason,
        ));

    var hadTitleMatch = false;
    final aggregatedAttempts = <_Attempt>[];

    Future<_Attempt?> ask(String sourceId) async {
      debugPrint('[playback] _resolve · trying $sourceId');
      _Attempt? attempt;
      final budget = _budgetFor(sourceId, chosen);
      try {
        final call = _tryCandidate(
          p,
          sourceId,
          t,
          fast: fast,
          category: category,
          onTitleMatch: () => hadTitleMatch = true,
          onMiss: (reason) => note(sourceId, reason),
        ).timeout(budget);
        if (accept == null) {
          attempt = await Future.any<_Attempt?>([call, abortFuture]);
          if (attempt == null) {
            unawaited(call.then<void>((_) {}, onError: (_) {}));
          }
        } else {
          attempt = await call;
        }
      } on TimeoutException {
        _overBudget[sourceId] = DateTime.now();
        note(sourceId, SweepReason.timedOut);
        debugPrint(
          '[playback] _resolve · $sourceId → over ${budget.inSeconds}s '
          'budget, skipping it for ${overBudgetCooldown.inMinutes}m',
        );
      } catch (e) {
        note(sourceId, SweepReason.failed);
        debugPrint(
          '[playback] _resolve · $sourceId → error during resolution: $e',
        );
      }
      return attempt;
    }

    outer:
    for (var start = 0; start < ordered.length; start += sweepWaveSize) {
      if (accept == null && gen != _sweepGen) {
        debugPrint(
          '[playback] _resolve · abandoned before wave at $start — '
          'the viewer left',
        );
        throw const PlaybackAborted();
      }

      final wave = <String>[];
      for (final sourceId in ordered.skip(start).take(sweepWaveSize)) {
        if (dead.contains(sourceId)) {
          debugPrint(
            '[playback] _resolve · skip $sourceId (its links did not play)',
          );
          note(sourceId, SweepReason.streamsDead);
          continue;
        }
        if (CfSolveNeeded.sourceFlagged(sourceId)) {
          debugPrint('[playback] _resolve · skip $sourceId (CF blocked)');
          note(sourceId, SweepReason.cloudflare);
          continue;
        }
        if (_health.isSkippable(sourceId)) {
          debugPrint('[playback] _resolve · skip $sourceId (unhealthy)');
          note(sourceId, SweepReason.unhealthy);
          continue;
        }
        if (_recentlyOverBudget(sourceId)) {
          debugPrint(
            '[playback] _resolve · skip $sourceId (over budget recently)',
          );
          note(sourceId, SweepReason.cooldown);
          continue;
        }
        wave.add(sourceId);
      }
      if (wave.isEmpty) continue;

      final answers = await Future.wait([for (final id in wave) ask(id)]);

      if (accept == null && gen != _sweepGen) {
        debugPrint(
          '[playback] _resolve · abandoned mid-wave at $start — '
          'the viewer left',
        );
        throw const PlaybackAborted();
      }

      for (var i = 0; i < wave.length; i++) {
        final sourceId = wave[i];
        final attempt = answers[i];
        if (attempt == null) {
          if (accept == null && sourceId == pinned && gen == _sweepGen) {
            debugPrint(
              '[playback] _resolve · $sourceId was pinned by hand and did not '
              'answer — not substituting another source',
            );
            break outer;
          }
          continue;
        }

        if (accept != null && !accept(attempt.streams)) {
          debugPrint(
            '[playback] _resolve · ${attempt.match.sourceId} answered but the '
            'caller rejected its streams — next candidate',
          );
          continue;
        }

        if (accept != null) {
          return ResolvedPlayback(
            match: attempt.match,
            episodeUrl: attempt.episodeUrl,
            streams: attempt.streams,
            show: p.show,
            episode: p.episode,
          );
        }

        aggregatedAttempts.add(attempt);
        if (sourceId == pinned) {
          break outer;
        }
      }
    }

    if (aggregatedAttempts.isNotEmpty) {
      final primary = aggregatedAttempts.first;
      final allStreams = <VideoSource>[];
      final seenUrls = <String>{};

      for (final att in aggregatedAttempts) {
        for (final s in att.streams) {
          if (seenUrls.add(s.url)) {
            allStreams.add(s);
          }
        }
      }

      _winners[_winKey(zmEpisodeUrl, category)] = (
        episodeUrl: primary.episodeUrl,
        sourceId: primary.match.sourceId,
        match: primary.match,
      );

      if (!primary.match.pinned) {
        await _store.rememberLastPlayed(p.show, primary.match.sourceId);
        await _scores?.bump(primary.match.sourceId);
      }

      debugPrint(
        '[playback] aggregated ${allStreams.length} streams across '
        '${aggregatedAttempts.length} sources for $zmEpisodeUrl',
      );

      return ResolvedPlayback(
        match: primary.match,
        episodeUrl: primary.episodeUrl,
        streams: allStreams,
        show: p.show,
        episode: p.episode,
      );
    }

    final blocked = _matcher.cfBlockedUrl(p.show.kind);
    if (blocked != null && !hadTitleMatch) {
      debugPrint(
        '[playback] _resolve · CF blocked for kind=${p.show.kind} '
        'url=$blocked',
      );
    }

    _noSource[_winKey(zmEpisodeUrl, category)] = (
      at: DateTime.now(),
      hadTitleMatch: hadTitleMatch,
    );
    if (hadTitleMatch) {
      debugPrint(
        '[playback] _resolve → EpisodeNotAvailable '
        '(hadTitleMatch=true, episode=${p.episode})',
      );
      throw EpisodeNotAvailable(
        p.show,
        p.episode,
        hadTitleMatch: true,
        outcomes: outcomes,
      );
    }
    debugPrint(
      '[playback] _resolve → NoSourceMatch · '
      '${sweepFailureDetail(outcomes) ?? "every source answered"}',
    );
    throw NoSourceMatch(p.show, outcomes: outcomes);
  }

  Future<List<VideoSource>> sources(
    String zmEpisodeUrl, {
    bool fast = false,
    String category = 'sub',
  }) async {
    final hit = _winners[_winKey(zmEpisodeUrl, category)];
    if (hit != null) {
      return _sources.sources(
        hit.episodeUrl,
        sourceId: hit.sourceId,
        fast: fast,
      );
    }
    return (await resolveForPlayback(
      zmEpisodeUrl,
      fast: fast,
      category: category,
    ))
        .streams;
  }

  Future<({List<VideoSource> sources, bool done})> polledSources(
    String zmEpisodeUrl, {
    String category = 'sub',
  }) async {
    final key = _winKey(zmEpisodeUrl, category);
    var winner = _winners[key];
    if (winner == null) {
      await resolveForPlayback(zmEpisodeUrl, category: category);
      winner = _winners[key];
    }
    if (winner == null) {
      return (sources: const <VideoSource>[], done: true);
    }
    return _sources.polledSources(winner.episodeUrl, sourceId: winner.sourceId);
  }

  String? resolvedSourceId(String zmEpisodeUrl, {String category = 'sub'}) =>
      _winners[_winKey(zmEpisodeUrl, category)]?.sourceId;

  void invalidateWinner(String zmEpisodeUrl) {
    bool mine(String k) => k == zmEpisodeUrl || k.startsWith('$zmEpisodeUrl|');
    final winners = _winners.keys.where(mine).toList();
    final misses = _noSource.keys.where(mine).toList();
    for (final k in winners) {
      _winners.remove(k);
    }
    for (final k in misses) {
      _noSource.remove(k);
    }
    for (final k in _unplayable.keys.where(mine).toList()) {
      _unplayable.remove(k);
    }
    final clearedBudget = _overBudget.isNotEmpty;
    if (clearedBudget) _overBudget.clear();
    if (winners.isNotEmpty || misses.isNotEmpty || clearedBudget) {
      debugPrint(
        '[playback] invalidateWinner · $zmEpisodeUrl '
        '(${winners.length} winner(s), ${misses.length} miss(es)'
        '${clearedBudget ? ', over-budget cleared' : ''})',
      );
    }
  }

  void invalidateShow(ZCanonical c) {
    final prefix = '${ZmodeIds.showUrl(c)}/ep/';
    final winners = _winners.keys.where((k) => k.startsWith(prefix)).toList();
    final misses = _noSource.keys.where((k) => k.startsWith(prefix)).toList();
    final flights = _inFlight.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in winners) {
      _winners.remove(k);
    }
    for (final k in misses) {
      _noSource.remove(k);
    }
    for (final k in flights) {
      _inFlight.remove(k);
    }
    final clearedBudget = _overBudget.isNotEmpty;
    if (clearedBudget) _overBudget.clear();
    if (winners.isNotEmpty ||
        misses.isNotEmpty ||
        flights.isNotEmpty ||
        clearedBudget) {
      debugPrint(
        '[playback] invalidateShow · $prefix '
        '(${winners.length} winner(s), ${misses.length} miss(es)'
        '${clearedBudget ? ', over-budget cleared' : ''})',
      );
    }
  }

  static Episode? _episodeAtIndex(List<Episode> eps, int n) {
    final i = n - 1;
    if (i < 0 || i >= eps.length) return null;
    return eps[i];
  }

  static bool _isNativeSource(String id) =>
      id.startsWith('cs:') ||
      id.startsWith('ani:') ||
      id.startsWith('mihon:') ||
      id.startsWith('lnr:');

  List<({String id, String name})> candidatesForEpisode(String zmEpisodeUrl) {
    final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (p == null) return const [];
    return [
      for (final id in _orderedCandidates(p.show))
        (id: id, name: _sources.displayName(id)),
    ];
  }

  Stream<SourceProbe> probeEach(
    String zmEpisodeUrl, {
    Duration wallClock = const Duration(seconds: 20),
    Set<String> skip = const {},
  }) {
    final out = StreamController<SourceProbe>();
    final clock = Stopwatch()..start();
    var stopped = false;
    bool full() => stopped || out.isClosed || clock.elapsed > wallClock;

    Future<void> run() async {
      final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
      if (p == null) return;
      final t = await _titleLookup(p.show);
      final all = _orderedCandidates(
        p.show,
      ).where((id) => !skip.contains(id)).toList();
      debugPrint(
        '[probe] ── pass start · ${all.length} to ask · '
        'up to ${wallClock.inSeconds}s',
      );

      Future<bool> probeOne(String sourceId) async {
        if (full()) return false;
        final name = _sources.displayName(sourceId);
        if (CfSolveNeeded.sourceFlagged(sourceId) ||
            _health.isSkippable(sourceId) ||
            _recentlyOverBudget(sourceId)) {
          if (!out.isClosed) {
            out.add(SourceProbe(sourceId: sourceId, name: name, skipped: true));
          }
          return false;
        }
        if (full()) return false;
        if (!out.isClosed) {
          out.add(SourceProbe(sourceId: sourceId, name: name, checking: true));
        }
        Episode? srcEp;
        SourceMatch? match;
        final sw = Stopwatch()..start();
        var how = 'no';
        try {
          (match, srcEp) = await _passively(
            () => _hasEpisode(p, sourceId, t),
          ).timeout(probeBudget);
          how = srcEp != null ? 'HAS' : 'no';
        } on TimeoutException {
          _overBudget[sourceId] = DateTime.now();
          how = 'timeout';
        } catch (e) {
          how = 'error: $e';
        }
        debugPrint('[probe] $sourceId → $how (${sw.elapsedMilliseconds}ms)');
        final timedOut = how == 'timeout';
        if (!out.isClosed) {
          out.add(
            SourceProbe(
              sourceId: sourceId,
              name: name,
              episodeUrl: srcEp?.url,
              match: match,
            ),
          );
        }
        return timedOut;
      }

      final native = <String>[];
      final js = <String>[];
      for (final id in all) {
        (_isNativeSource(id) ? native : js).add(id);
      }

      var next = 0;
      Future<void> nativeWorker() async {
        while (!full()) {
          if (next >= native.length) return;
          final id = native[next++];
          await probeOne(id);
          await Future<void>.delayed(Duration.zero);
        }
      }

      Future<void> nativeLane() =>
          Future.wait([for (var i = 0; i < 5; i++) nativeWorker()]);

      Future<void> jsLane() async {
        for (final id in js) {
          if (full()) return;
          final timedOut = await probeOne(id);
          if (timedOut) {
            debugPrint(
              '[probe] JS lane stopped — runtime busy after $id timed out',
            );
            return;
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      await Future.wait([nativeLane(), jsLane()]);
    }

    out.onCancel = () => stopped = true;
    unawaited(
      run().whenComplete(() {
        if (!out.isClosed) out.close();
      }),
    );
    return out.stream;
  }

  Future<List<VideoSource>> sourcesFrom(
    String zmEpisodeUrl,
    String sourceId, {
    bool fast = false,
    String category = 'sub',
  }) async {
    final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (p == null) return const [];
    final t = await _titleLookup(p.show);
    final (match, ep) = await _hasEpisode(p, sourceId, t, category: category);
    if (match == null || ep == null) {
      debugPrint('[playback] sourcesFrom · $sourceId has no ep ${p.episode}');
      return const [];
    }
    return _sources.sources(ep.url, sourceId: match.sourceId, fast: fast);
  }

  Future<List<VideoSource>> prewarmRememberedSource(
    String zmEpisodeUrl, {
    String category = 'sub',
  }) async {
    final parsed = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (parsed == null) return const [];
    final remembered = _store.bestFor(parsed.show);
    if (remembered == null) return const [];
    final title = await _titleLookup(parsed.show);
    await _hasEpisode(parsed, remembered.sourceId, title, category: category);
    return const [];
  }

  Future<T> _passively<T>(Future<T> Function() body) =>
      sl.isRegistered<ProviderManager>()
          ? sl<ProviderManager>().asPassiveSweep(body)
          : body();

  Future<(SourceMatch?, Episode?)> _hasEpisode(
    ({ZCanonical show, int episode}) p,
    String sourceId,
    ({String title, String? alt, int? malId}) t, {
    String category = 'sub',
  }) async {
    final match = await _matcher.matchOn(
      p.show,
      sourceId,
      title: t.title,
      altTitle: t.alt,
      malId: t.malId,
    );
    if (match == null) return (null, null);
    final eps = await _sources.episodes(
      match.showUrl,
      sourceId: match.sourceId,
      category: category,
    );
    return (match, _episodeAtIndex(eps, p.episode));
  }

  Future<void> useProbed(String zmEpisodeUrl, SourceProbe probe) async {
    final url = probe.episodeUrl;
    final m = probe.match;
    if (url == null || m == null) return;
    _noSource.remove(zmEpisodeUrl);
    _winners[zmEpisodeUrl] = (episodeUrl: url, sourceId: m.sourceId, match: m);
    final p = ZmodeIds.parseEpisode(zmEpisodeUrl);
    if (p != null && !m.pinned) {
      await _store.rememberLastPlayed(p.show, m.sourceId);
      await _scores?.bump(m.sourceId);
    }
  }

  Future<_Attempt?> _tryCandidate(
    ({ZCanonical show, int episode}) p,
    String sourceId,
    ({String title, String? alt, int? malId}) t, {
    required bool fast,
    required void Function() onTitleMatch,
    required void Function(SweepReason) onMiss,
    String category = 'sub',
  }) async {
    final match = await _matcher.matchOn(
      p.show,
      sourceId,
      title: t.title,
      altTitle: t.alt,
      malId: t.malId,
    );
    if (match == null) {
      debugPrint('[playback] _resolve · $sourceId → no title match');
      onMiss(SweepReason.noTitleMatch);
      return null;
    }
    onTitleMatch();

    final srcEp = _episodeAtIndex(
      await _sources.episodes(
        match.showUrl,
        sourceId: match.sourceId,
        category: category,
      ),
      p.episode,
    );
    if (srcEp == null) {
      debugPrint(
        '[playback] _resolve · $sourceId → episode ${p.episode} not found',
      );
      onMiss(SweepReason.episodeMissing);
      return null;
    }

    final streams = await _sources.sources(
      srcEp.url,
      sourceId: match.sourceId,
      fast: fast,
    );
    if (streams.isEmpty) {
      debugPrint(
        '[playback] _resolve · $sourceId → 0 streams for ep ${p.episode}',
      );
      onMiss(SweepReason.noStreams);
      return null;
    }

    final providerTag = _sources.displayName(sourceId);
    final taggedStreams = streams.map((s) {
      final q = (s.quality != null && s.quality!.isNotEmpty) ? ' · ${s.quality}' : '';
      return s.copyWith(
        quality: '[$providerTag]$q',
      );
    }).toList();

    return _Attempt(match: match, episodeUrl: srcEp.url, streams: taggedStreams);
  }

  List<String> _orderedCandidates(ZCanonical c) {
    final all = _candidates(c.kind);
    if (all.isEmpty) return const [];

    final ids = all.map((s) => s.id).toList();
    final pinned = _matcher.pinnedSource(c);
    final last = _store.lastPlayed(c);
    final preferred = _prefs.get(c.kind);

    int rank(String id) {
      if (id == pinned) return 0;
      if (id == last) return 1;
      if (id == preferred) return 2;
      return 3 + _healthRank(id);
    }

    final position = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final sorted = ids.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : position[a]!.compareTo(position[b]!);
      });

    return sorted.take(_sweepCap(c.kind)).toList();
  }

  int _sweepCap(ZKind kind) => sl.isRegistered<SourceOrderPrefs>()
      ? sl<SourceOrderPrefs>().cap(kind)
      : 1 << 30;

  int _healthRank(String id) => switch (_health.statusOf(id)) {
        SourceHealth.ok => 0,
        SourceHealth.slow => 1,
        SourceHealth.dead => 2,
      };
}

class _Attempt {
  const _Attempt({
    required this.match,
    required this.episodeUrl,
    required this.streams,
  });
  final SourceMatch match;
  final String episodeUrl;
  final List<VideoSource> streams;
}

class SourceProbe {
  const SourceProbe({
    required this.sourceId,
    required this.name,
    this.pending = false,
    this.checking = false,
    this.skipped = false,
    this.episodeUrl,
    this.match,
  });

  final String sourceId;
  final String name;
  final bool pending;
  final bool checking;
  final bool skipped;
  final String? episodeUrl;
  final SourceMatch? match;

  bool get hasEpisode => episodeUrl != null;
}
