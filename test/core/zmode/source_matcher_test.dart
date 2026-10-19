import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/zmode/match_store.dart';
import 'package:watch_app/core/zmode/zmode_source_prefs.dart';
import 'package:watch_app/core/zmode/source_matcher.dart';
import 'package:watch_app/core/zmode/zmode_ids.dart';

MediaItem _hit(String src, String title, {int? malId, String? englishTitle}) =>
    MediaItem(
      id: title.toLowerCase(),
      title: title,
      url: 'https://$src/$title',
      type: ProviderType.anime,
      sourceId: src,
      malId: malId,
      englishTitle: englishTitle,
    );

/// search() per source id. Sources not listed throw, like a dead source.
/// [installed] backs [hasSource] — defaults to every id [bySource] AND
/// [candidates] mention, so a test has to opt IN to an uninstalled source
/// rather than accidentally getting one from a bare `bySource` map.
class _FakeSources implements SourceRepository {
  _FakeSources(this.bySource, {Set<String>? installed, Set<String>? candidates})
    : installed = installed ?? {...bySource.keys, ...?candidates};
  final Map<String, List<MediaItem>> bySource;
  final Set<String> installed;
  final searched = <String>[];

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  // Added with the on-demand resolver: SourceMatcher now asks whether a JS
  // provider is loaded before searching it. These fakes are already "loaded".
  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  List<({String id, String name})> get pickableSources => loadedSources;

  @override
  bool hasSource(String sourceId) => installed.contains(sourceId);

  @override
  Future<List<MediaItem>> search(
    String query, {
    String category = 'sub',
    String? sourceId,
  }) async {
    searched.add(sourceId!);
    final r = bySource[sourceId];
    if (r == null) throw StateError('dead');
    return r;
  }
}

class _GatedFakeSources extends _FakeSources {
  _GatedFakeSources(this.started, this.gate)
    : super({}, candidates: {'allanime', 'hianime'});

  final Completer<void> started;
  final Completer<List<MediaItem>> gate;

  @override
  Future<List<MediaItem>> search(
    String query, {
    String category = 'sub',
    String? sourceId,
  }) async {
    searched.add(sourceId!);
    if (!started.isCompleted) started.complete();
    return gate.future;
  }
}

void main() {
  late Directory dir;
  late MatchStore store;
  late ZSourcePrefs prefs;
  const fma = ZCanonical(ZKind.anime, 'mal:5114');
  final two = [
    (id: 'allanime', name: 'AllAnime'),
    (id: 'hianime', name: 'HiAnime'),
  ];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('matcher');
    Hive.init(dir.path);
    store = await MatchStore.open();
    prefs = await ZSourcePrefs.open();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('resolveOn', () {
    test('matches on exactly the named source', () async {
      final repo = _FakeSources(
        {
          'allanime': [_hit('allanime', 'Naruto')],
          'hianime': [_hit('hianime', 'Fullmetal Alchemist Brotherhood')],
        },
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolveOn(
        fma,
        'hianime',
        title: 'Fullmetal Alchemist: Brotherhood',
      );
      expect(r?.sourceId, 'hianime');
      expect(repo.searched, ['hianime']); // allanime was never touched
      expect(store.get(fma, 'hianime')?.sourceId, 'hianime');
    });

    test(
      'returns null (not a throw) when the named source genuinely lacks it',
      () async {
        final repo = _FakeSources({
          'allanime': [_hit('allanime', 'Naruto')],
        });
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => two,
        );
        final r = await m.resolveOn(
          fma,
          'allanime',
          title: 'Fullmetal Alchemist: Brotherhood',
        );
        expect(r, isNull);
        expect(store.get(fma, 'allanime'), isNull);
      },
    );

    test('a throwing source returns null, not an exception', () async {
      final repo = _FakeSources({}, candidates: {'allanime'});
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      expect(await m.resolveOn(fma, 'allanime', title: 'anything'), isNull);
    });
  });

  group('resolve', () {
    test(
      'a second caller observes progress from the shared in-flight sweep',
      () async {
        final started = Completer<void>();
        final gate = Completer<List<MediaItem>>();
        final repo = _GatedFakeSources(started, gate);
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => two,
        );

        final original = m.resolve(
          fma,
          title: 'Fullmetal Alchemist: Brotherhood',
        );
        await started.future;

        final progress = <({String sourceName, int current, int total})>[];
        final observer = m.resolve(
          fma,
          title: 'Fullmetal Alchemist: Brotherhood',
          onProgress: (sourceName, current, total) => progress.add((
            sourceName: sourceName,
            current: current,
            total: total,
          )),
        );

        expect(progress, [(sourceName: 'AllAnime', current: 1, total: 2)]);
        gate.complete(const []);
        expect(await original, isNull);
        expect(await observer, isNull);
        expect(progress, [
          (sourceName: 'AllAnime', current: 1, total: 2),
          (sourceName: 'HiAnime', current: 2, total: 2),
        ]);
      },
    );

    test('with no stored pick, the first candidate is the source', () async {
      final repo = _FakeSources({
        'allanime': [_hit('allanime', 'Fullmetal Alchemist Brotherhood')],
        'hianime': [_hit('hianime', 'Fullmetal Alchemist Brotherhood')],
      });
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'Fullmetal Alchemist: Brotherhood');
      expect(r?.sourceId, 'allanime');
      expect(store.get(fma, 'allanime')?.sourceId, 'allanime');
      // The defining rule: one source is asked, never a sweep of all of them.
      expect(repo.searched, ['allanime']);
    });

    test('honours a stored selection over candidate order', () async {
      await store.save(
        fma,
        const SourceMatch(
          sourceId: 'hianime',
          showUrl: 'u',
          showId: 'i',
          showTitle: 't',
          pinned: false,
        ),
      );
      prefs.set(fma.kind, 'hianime');
      final repo = _FakeSources(
        {
          'allanime': [_hit('allanime', 'Fullmetal Alchemist Brotherhood')],
        },
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'anything');
      expect(r?.sourceId, 'hianime');
      expect(repo.searched, isEmpty); // selection short-circuited the sweep
    });

    test(
      'a selected, installed source with no match returns null honestly, no fallback sweep',
      () async {
        prefs.set(fma.kind, 'allanime');
        final repo = _FakeSources(
          {
            'allanime': [_hit('allanime', 'Naruto')], // genuinely not FMA
            'hianime': [_hit('hianime', 'Fullmetal Alchemist Brotherhood')],
          },
          candidates: {'allanime', 'hianime'},
        );
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => two,
        );
        final r = await m.resolve(
          fma,
          title: 'Fullmetal Alchemist: Brotherhood',
        );
        expect(r, isNull);
        expect(repo.searched, ['allanime']); // hianime never tried
        expect(prefs.get(fma.kind), 'allanime'); // selection unchanged
      },
    );

    test(
      'a pick that was uninstalled falls back to one that still exists',
      () async {
        await store.save(
          fma,
          const SourceMatch(
            sourceId: 'allanime',
            showUrl: 'u',
            showId: 'i',
            showTitle: 't',
            pinned: false,
          ),
        );
        await prefs.set(fma.kind, 'allanime');
        // allanime is gone — candidatesForKind only ever lists installed sources,
        // so the stored pick no longer appears in it.
        final repo = _FakeSources(
          {
            'hianime': [_hit('hianime', 'FMA')],
          },
          installed: {'hianime'},
        );
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => [(id: 'hianime', name: 'HiAnime')],
        );
        final r = await m.resolve(fma, title: 'FMA');
        expect(r?.sourceId, 'hianime');
        expect(store.get(fma, 'hianime')?.sourceId, 'hianime');
        // The stored pick is NOT rewritten by falling back — reinstall allanime
        // and it is the source again, without the user re-choosing it.
        expect(prefs.get(fma.kind), 'allanime');
      },
    );

    test(
      'a saved PINNED match on an uninstalled source is still honoured',
      () async {
        await store.pin(
          fma,
          const SourceMatch(
            sourceId: 'allanime',
            showUrl: 'u',
            showId: 'i',
            showTitle: 't',
            pinned: true,
          ),
        );
        prefs.set(fma.kind, 'allanime');
        final repo = _FakeSources(
          {
            'hianime': [_hit('hianime', 'FMA')],
          },
          installed: {'hianime'},
        );
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => two,
        );
        final r = await m.resolve(fma, title: 'FMA');
        expect(r?.sourceId, 'allanime');
        expect(repo.searched, isEmpty);
      },
    );

    test('a dead source is swept past, not fatal', () async {
      // allanime throws. Under Auto Resolve the sweep carries on to hianime
      // rather than giving up — the whole point of resolving on demand.
      final repo = _FakeSources(
        {
          'hianime': [_hit('hianime', 'FMA')],
        },
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      expect((await m.resolve(fma, title: 'FMA'))?.sourceId, 'hianime');
    });

    test('nothing anywhere returns null and saves/selects nothing', () async {
      final repo = _FakeSources({'allanime': [], 'hianime': []});
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      expect(await m.resolve(fma, title: 'x'), isNull);
      expect(prefs.get(fma.kind), isNull);
    });

    test('a MAL id on the result beats a closer title', () async {
      final repo = _FakeSources({
        'allanime': [
          _hit('allanime', 'Fullmetal Alchemist', malId: 121),
          _hit('allanime', 'FMA Brotherhood', malId: 5114),
        ],
      });
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => [two.first],
      );
      final r = await m.resolve(fma, title: 'Fullmetal Alchemist', malId: 5114);
      expect(r?.showUrl, 'https://allanime/FMA Brotherhood');
    });

    test(
      'no source genuinely has the title returns null and saves nothing',
      () async {
        final repo = _FakeSources({
          'allanime': [_hit('allanime', 'Naruto')],
          'hianime': [_hit('hianime', 'One Piece')],
        });
        final m = SourceMatcher(
          sources: repo,
          store: store,
          prefs: prefs,
          candidates: (_) => two,
        );
        final r = await m.resolve(
          fma,
          title: 'Fullmetal Alchemist: Brotherhood',
        );
        expect(r, isNull);
        expect(prefs.get(fma.kind), isNull);
      },
    );

    test('a genuine match on the first source stops the search', () async {
      final repo = _FakeSources({
        'allanime': [_hit('allanime', 'Fullmetal Alchemist Brotherhood')],
        'hianime': [_hit('hianime', 'Should not be reached')],
      });
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'Fullmetal Alchemist: Brotherhood');
      expect(r?.sourceId, 'allanime');
      expect(repo.searched, ['allanime']);
    });

    test('a romaji title with a matching englishTitle is accepted', () async {
      final repo = _FakeSources({
        'allanime': [
          _hit(
            'allanime',
            'Hagane no Renkinjutsushi',
            englishTitle: 'Fullmetal Alchemist: Brotherhood',
          ),
        ],
        'hianime': [_hit('hianime', 'Should not be reached')],
      });
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'Fullmetal Alchemist: Brotherhood');
      expect(r?.sourceId, 'allanime');
      expect(r?.showTitle, 'Hagane no Renkinjutsushi');
      expect(store.get(fma, 'allanime')?.sourceId, 'allanime');
    });

    test('the last candidate source throwing does not propagate', () async {
      // allanime is alive but has nothing; hianime (the last candidate) is dead.
      final repo = _FakeSources(
        {'allanime': []},
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      expect(await m.resolve(fma, title: 'anything'), isNull);
      expect(prefs.get(fma.kind), isNull);
    });
  });

  group('saved', () {
    test('answers for the selected source only', () async {
      await store.save(
        fma,
        const SourceMatch(
          sourceId: 'allanime',
          showUrl: 'a',
          showId: 'a',
          showTitle: 'a',
          pinned: false,
        ),
      );
      await store.save(
        fma,
        const SourceMatch(
          sourceId: 'hianime',
          showUrl: 'h',
          showId: 'h',
          showTitle: 'h',
          pinned: false,
        ),
      );
      final m = SourceMatcher(
        sources: _FakeSources({}),
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      // No stored pick, so there is no selected source to answer for: Auto
      // Resolve decides at play time instead of a standing kind default.
      expect(m.selectedFor(fma.kind), isNull);
      await prefs.set(fma.kind, 'hianime');
      expect(m.saved(fma)?.sourceId, 'hianime');
    });
  });

  group('pinManual', () {
    test('pins the pick without touching the kind default', () async {
      final repo = _FakeSources({});
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.pinManual(fma, _hit('hianime', 'FMA'));
      expect(r.pinned, isTrue);
      expect(store.get(fma, 'hianime')?.pinned, isTrue);
      // The pin alone is what makes this title play on hianime.
      expect(m.sourceForTitle(fma), 'hianime');
      // ...and every OTHER title is untouched, so Auto Resolve still runs.
      expect(prefs.get(fma.kind), isNull);
    });
  });

  group('no negative miss cache', () {
    // Every candidate answers, none of them with this title.
    _FakeSources noneHaveIt() => _FakeSources({
      'allanime': [_hit('allanime', 'Something Else')],
      'hianime': [_hit('hianime', 'Another Thing')],
    });

    test('a source that said no is asked again on the next resolve', () async {
      final repo = noneHaveIt();
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );

      expect(await m.resolve(fma, title: 'Fullmetal Alchemist'), isNull);
      expect(repo.searched, ['allanime', 'hianime']);

      // Episode taps / re-opens must re-search — a prior miss is not sticky.
      repo.searched.clear();
      expect(await m.resolve(fma, title: 'Fullmetal Alchemist'), isNull);
      expect(repo.searched, ['allanime', 'hianime']);
    });

    test('a successful match is still reused without re-searching', () async {
      final repo = _FakeSources({
        'allanime': [_hit('allanime', 'Fullmetal Alchemist')],
        'hianime': [_hit('hianime', 'Another Thing')],
      });
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );

      final first = await m.resolve(fma, title: 'Fullmetal Alchemist');
      expect(first?.sourceId, 'allanime');
      expect(repo.searched, ['allanime']);

      repo.searched.clear();
      final second = await m.resolve(fma, title: 'Fullmetal Alchemist');
      expect(second?.sourceId, 'allanime');
      expect(
        repo.searched,
        isEmpty,
        reason: 'cached / auto-resolve winner must still short-circuit',
      );
    });
  });
  group('abandoned sweep', () {
    // Fast back-and-tap through detail screens used to leave each sweep running,
    // so one live search piled up per screen and every new tap waited behind the
    // abandoned ones. The sweep has to stop between sources.

    test('a sweep searches nothing once the viewer has gone', () async {
      final repo = _FakeSources(
        {
          'allanime': [_hit('allanime', 'Naruto')],
          'hianime': [_hit('hianime', 'Naruto')],
        },
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'Naruto', abandoned: () => true);
      expect(r, isNull, reason: 'nobody is waiting for this match');
      expect(
        repo.searched,
        isEmpty,
        reason: 'no source searched after leaving',
      );
    });

    test('a pinned source is not queried once the caller has gone', () async {
      final repo = _FakeSources(
        {
          'allanime': [_hit('allanime', 'Naruto')],
        },
        candidates: {'allanime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      await m.pinManual(fma, _hit('allanime', 'Naruto'));

      final r = await m.resolve(fma, title: 'Naruto', abandoned: () => true);

      expect(r, isNull, reason: 'nobody is waiting for this pinned match');
      expect(
        repo.searched,
        isEmpty,
        reason: 'no source searched after leaving',
      );
    });

    test('a sweep the viewer stays for still matches', () async {
      final repo = _FakeSources(
        {
          'allanime': [_hit('allanime', 'Naruto')],
          'hianime': [_hit('hianime', 'Naruto')],
        },
        candidates: {'allanime', 'hianime'},
      );
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => two,
      );
      final r = await m.resolve(fma, title: 'Naruto', abandoned: () => false);
      expect(r?.sourceId, 'allanime');
      expect(repo.searched, ['allanime']);
    });

    test('leaving mid-sweep stops the pile growing', () async {
      var searches = 0;
      final repo = _countingSources(onSearch: () => searches++);
      final m = SourceMatcher(
        sources: repo,
        store: store,
        prefs: prefs,
        candidates: (_) => [
          (id: 'a', name: 'A'),
          (id: 'b', name: 'B'),
          (id: 'c', name: 'C'),
        ],
      );
      var checks = 0;
      await m.resolve(
        fma,
        title: 'Nothing matches',
        abandoned: () => ++checks > 1,
      );
      expect(
        searches,
        lessThan(3),
        reason: 'later sources must never be searched once the viewer left',
      );
    });
  });
}

/// Searches nothing on any source, so a sweep walks its whole candidate list and
/// the between-sources abandonment check is the only thing that can end it.
class _countingSources implements SourceRepository {
  _countingSources({required this.onSearch});
  final void Function() onSearch;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  bool hasSource(String sourceId) => true;

  @override
  List<({String id, String name})> get pickableSources => const [];

  @override
  Future<List<MediaItem>> search(
    String query, {
    String category = 'sub',
    String? sourceId,
  }) async {
    onSearch();
    return const [];
  }
}
