import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/search_history.dart';
import 'package:watch_app/core/playback/search_prefs.dart';
import 'package:watch_app/core/playback/search_scope.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/search/title_suggestion_service.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';
import 'package:watch_app/core/tv/tv_list_focusable.dart';
import 'package:watch_app/core/tv/tv_text_field.dart';
import 'package:watch_app/core/zmode/metadata_repository.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';
import 'package:watch_app/core/ui/dock_visibility.dart';
import 'package:watch_app/features/home/search_screen_tv.dart';
import 'package:watch_app/features/home/tv_search_input_screen.dart';
import 'package:watch_app/features/search/bloc/search_bloc.dart';
import 'package:watch_app/features/search/bloc/search_event.dart';
import 'package:watch_app/features/search/bloc/search_state.dart';

// ── Minimal stubs ─────────────────────────────────────────────────────────────

/// [SearchHistory] stub: no Hive dependency, returns empty history.
class _StubSearchHistory extends SearchHistory {
  @override
  List<String> recent() => const [];
  @override
  Future<void> add(String query) async {}
  @override
  Future<void> remove(String query) async {}
  @override
  Future<void> clear() async {}
}

/// [SearchHistory] stub with a mutable list so Clear can be asserted.
class _MutableSearchHistory extends SearchHistory {
  _MutableSearchHistory(this._recent);
  List<String> _recent;

  @override
  List<String> recent() => List.unmodifiable(_recent);

  @override
  Future<void> add(String query) async {}

  @override
  Future<void> remove(String query) async {}

  @override
  Future<void> clear() async {
    _recent = [];
  }
}

/// [SearchPrefs] stub: no Hive dependency, returns safe defaults.
/// Only the getters that [SearchBloc._restoredState] calls are overridden.
class _StubSearchPrefs extends SearchPrefs {
  @override
  String? get contentFilterName => null;
  @override
  String? get audioFilterName => null;
  @override
  String? get statusFilterName => null;
  @override
  String? get sortName => null;
  @override
  String? get genre => null;
  @override
  int? get decade => null;
  @override
  bool get currentSourceOnly => true;
}

/// [TitleSuggestionService] stub: never makes network calls.
class _NewSearchPrefs extends _StubSearchPrefs {
  String style = 'new';
  @override
  String get tvSearchStyle => style;
  void choose(String value) {
    style = value;
    notifyListeners();
  }
}

class _StubSuggestions extends TitleSuggestionService {
  _StubSuggestions() : super(Dio());

  @override
  Future<List<String>> suggest(String query, {int limit = 8}) async => const [];
}

/// [SourceRepository] stub: implements the class interface.
/// All un-overridden methods are guarded by [noSuchMethod].
class _StubSourceRepository implements SourceRepository {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  // Added with the on-demand resolver: SourceMatcher now asks whether a JS
  // provider is loaded before searching it. These fakes are already "loaded".
  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  List<({String id, String name})> get pickableSources => loadedSources;

  @override
  String get sourceId => 'stub';

  @override
  List<({String id, String name})> get loadedSources => const [];

  @override
  String displayName(String id) => id;

  @override
  bool hasSource(String id) => false;

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async => const [];
}

/// Fake [SearchBloc] that extends the real class (so it satisfies
/// [BlocProvider<SearchBloc>]'s type constraint) but is initialised with stub
/// dependencies and then immediately emits a preset [SearchState].
///
/// All event handlers inherited from [SearchBloc] are registered but never
/// invoked in tests — no events are dispatched — so no real repo/history calls
/// are made.
class _FakeSearchBloc extends SearchBloc {
  final submittedQueries = <String?>[];

  void showResults(List<SourceResultGroup> groups) {
    emit(
      state.copyWith(
        query: 'Naruto',
        status: SearchStatus.success,
        groups: groups,
      ),
    );
  }

  @override
  void add(SearchEvent event) {
    if (event is SearchRunRequested) {
      submittedQueries.add(event.query);
      return;
    }
    super.add(event);
  }

  _FakeSearchBloc(SearchState targetState)
    : super(
        repo: _StubSourceRepository(),
        history: _StubSearchHistory(),
        prefs: _StubSearchPrefs(),
        suggestions: _StubSuggestions(),
      ) {
    // Override the state set by _restoredState() with the desired test state.
    emit(targetState);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildUnderTest(
  _FakeSearchBloc bloc, {
  SearchHistory? history,
  SearchScope scope = SearchScope.sources,
  String? initialQuery,
  String? fixedSourceId,
  String? fixedSourceName,
}) => BlocProvider<SearchBloc>.value(
  value: bloc,
  child: MaterialApp(
    home: SearchScreenTv(
      history: history,
      scope: scope,
      initialQuery: initialQuery,
      fixedSourceId: fixedSourceId,
      fixedSourceName: fixedSourceName,
    ),
  ),
);

/// The Genres entry reads only [MetadataRepository.supportsFilters]; stubbing
/// the rest would be fiction. Same shape as schedule_nav_test's _FiltersRepo.
class _FiltersRepo implements MetadataRepository {
  _FiltersRepo({this.supports = true});
  final bool supports;
  @override
  bool get supportsFilters => supports;
  final requests = <({String query, MetaFilters? filters})>[];
  @override
  Future<List<MediaItem>> searchFiltered(
    String query, {
    MetaFilters? filters,
    int page = 1,
  }) async {
    requests.add((query: query, filters: filters));
    return const [];
  }

  @override
  Future<List<MediaItem>> tvSearchWithSourceRecovery(
    String query, {
    MetaFilters? filters,
  }) => searchFiltered(query, filters: filters);

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const item1 = MediaItem(
    id: '1',
    title: 'Attack on Titan',
    url: '/aot',
    type: ProviderType.anime,
    sourceId: 'test',
  );
  const item2 = MediaItem(
    id: '2',
    title: 'Demon Slayer',
    url: '/ds',
    type: ProviderType.anime,
    sourceId: 'test',
  );

  group('Genres entry (restored after 097192ba dropped it)', () {
    tearDown(GetIt.I.reset);

    testWidgets('appears on the idle body when the catalogue can filter', (
      tester,
    ) async {
      GetIt.I.registerSingleton<MetadataRepository>(_FiltersRepo());
      final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildUnderTest(bloc));
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-search-genres')), findsOneWidget);
      expect(find.text('Genres'), findsOneWidget);
    });

    testWidgets('still reachable once there are recent searches', (
      tester,
    ) async {
      GetIt.I.registerSingleton<MetadataRepository>(_FiltersRepo());
      final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        _buildUnderTest(bloc, history: _MutableSearchHistory(['naruto'])),
      );
      await tester.pump();

      // main only drew it on the empty branch, so one search hid it for good.
      expect(find.byKey(const ValueKey('tv-search-genres')), findsOneWidget);
    });

    testWidgets('hidden when the catalogue cannot filter', (tester) async {
      GetIt.I.registerSingleton<MetadataRepository>(
        _FiltersRepo(supports: false),
      );
      final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildUnderTest(bloc));
      await tester.pump();

      expect(find.byKey(const ValueKey('tv-search-genres')), findsNothing);
    });
  });

  testWidgets('SearchScreenTv renders an autofocus-capable search field', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState());
    addTearDown(bloc.close);

    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pump();

    // Leanback-safe field: nav chrome autofocuses; edit node stays unfocused.
    expect(find.byType(TvTextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(find.byType(TextField), findsOneWidget);
    expect(field.autofocus, isFalse);
    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets('Classic OK opens the original system keyboard in place', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState());
    addTearDown(bloc.close);
    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
    expect(
      find.byKey(const ValueKey('tv-search-scope-current')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'tanya');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(bloc.submittedQueries, ['tanya']);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-key-A')), findsNothing);
  });
  testWidgets('Classic tap opens the original system keyboard', (tester) async {
    final bloc = _FakeSearchBloc(SearchState());
    addTearDown(bloc.close);
    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
    expect(
      find.byKey(const ValueKey('tv-search-scope-current')),
      findsOneWidget,
    );
  });
  testWidgets(
    'New replaces Classic directly and Search keeps the keyboard visible',
    (tester) async {
      GetIt.I.registerSingleton<SearchPrefs>(_NewSearchPrefs());
      addTearDown(() => GetIt.I.unregister<SearchPrefs>());
      final bloc = _FakeSearchBloc(SearchState());
      addTearDown(bloc.close);
      await tester.pumpWidget(_buildUnderTest(bloc));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('tv-key-A')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-key-q')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tv-key-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-key-A')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(bloc.submittedQueries, ['A']);
      expect(shellBackIntercepted.value, isFalse);
    },
  );

  testWidgets('New source search submits through the multi-source bloc', (
    tester,
  ) async {
    GetIt.I.registerSingleton<SearchPrefs>(_NewSearchPrefs());
    addTearDown(() => GetIt.I.unregister<SearchPrefs>());
    final bloc = _FakeSearchBloc(SearchState(currentSourceOnly: false));
    addTearDown(bloc.close);
    await tester.pumpWidget(_buildUnderTest(bloc, initialQuery: 'Naruto'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tv-key-done')));
    await tester.pump();
    expect(bloc.submittedQueries, ['Naruto']);
    bloc.showResults(const [
      SourceResultGroup(
        sourceId: 'first',
        sourceName: 'First',
        items: [
          MediaItem(
            id: 'a',
            title: 'Naruto A',
            url: '/a',
            type: ProviderType.anime,
            sourceId: 'first',
          ),
        ],
      ),
      SourceResultGroup(
        sourceId: 'second',
        sourceName: 'Second',
        items: [
          MediaItem(
            id: 'b',
            title: 'Naruto B',
            url: '/b',
            type: ProviderType.anime,
            sourceId: 'second',
          ),
        ],
      ),
    ]);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('tv-recommendation-first-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tv-recommendation-second-b')),
      findsOneWidget,
    );
  });

  testWidgets('opening a submitted source result does not search again', (
    tester,
  ) async {
    const item = MediaItem(
      id: 'naruto',
      title: 'Naruto',
      url: '/naruto',
      type: ProviderType.anime,
      sourceId: 'first',
    );
    final submitted = <String>[];
    MediaItem? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: TvSearchInputScreen(
          initialQuery: 'Naruto',
          compactStyle: true,
          inlineSearch: true,
          loadRecommendations: (_) async => const [],
          submittedResults: const [item],
          onSearchSubmitted: submitted.add,
          onRecommendationSelected: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tv-key-done')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tv-recommendation-first-naruto')),
    );
    await tester.pump();
    expect(submitted, ['Naruto']);
    expect(selected, item);
  });

  testWidgets('one Back from New returns Home without a Classic frame', (
    tester,
  ) async {
    GetIt.I.registerSingleton<SearchPrefs>(_NewSearchPrefs());
    addTearDown(() => GetIt.I.unregister<SearchPrefs>());
    final bloc = _FakeSearchBloc(SearchState(query: 'tanya'));
    addTearDown(bloc.close);
    var home = false;
    await tester.pumpWidget(
      BlocProvider<SearchBloc>.value(
        value: bloc,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && !shellBackIntercepted.value) {
                  update(() => home = true);
                }
              },
              child: home
                  ? const Text('Home destination')
                  : const SearchScreenTv(scope: SearchScope.library),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-search-filters')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-genres')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(home, isTrue);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Home destination'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Apple TV New keyboard returns Home on remote Back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      GetIt.I.registerSingleton<SearchPrefs>(_NewSearchPrefs());
      addTearDown(() => GetIt.I.unregister<SearchPrefs>());
      final bloc = _FakeSearchBloc(SearchState(query: 'tanya'));
      addTearDown(bloc.close);
      var home = false;
      await tester.pumpWidget(
        BlocProvider<SearchBloc>.value(
          value: bloc,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) => PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && !shellBackIntercepted.value) {
                    update(() => home = true);
                  }
                },
                child: home
                    ? const Text('Home destination')
                    : const SearchScreenTv(scope: SearchScope.library),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-search-filters')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-search-genres')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(home, isTrue);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Home destination'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('changing Search style replaces the mounted search view', (
    tester,
  ) async {
    final prefs = _NewSearchPrefs();
    GetIt.I.registerSingleton<SearchPrefs>(prefs);
    addTearDown(() => GetIt.I.unregister<SearchPrefs>());
    final bloc = _FakeSearchBloc(SearchState());
    addTearDown(bloc.close);
    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    prefs.choose('classic');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    prefs.choose('new');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(const ValueKey('tv-key-A')), findsOneWidget);
  });

  testWidgets('New applies a genre and clears it without opening Classic', (
    tester,
  ) async {
    GetIt.I.registerSingleton<SearchPrefs>(_NewSearchPrefs());
    addTearDown(() => GetIt.I.unregister<SearchPrefs>());
    final repo = _FiltersRepo();
    GetIt.I.registerSingleton<MetadataRepository>(repo);
    addTearDown(() => GetIt.I.unregister<MetadataRepository>());
    final bloc = _FakeSearchBloc(SearchState());
    addTearDown(bloc.close);
    await tester.pumpWidget(_buildUnderTest(bloc, scope: SearchScope.library));
    await tester.pumpAndSettle();
    final space = tester.getRect(find.byKey(const ValueKey('tv-key-space')));
    final clear = tester.getRect(find.byKey(const ValueKey('tv-key-clear')));
    final filters = tester.getRect(
      find.byKey(const ValueKey('tv-search-filters')),
    );
    final genres = tester.getRect(
      find.byKey(const ValueKey('tv-search-genres')),
    );
    expect(filters.left, closeTo(space.left, 0.01));
    expect(filters.width, closeTo(space.width, 0.01));
    expect(filters.height, space.height);
    expect(genres.left, closeTo(clear.left, 0.01));
    expect(genres.width, closeTo(clear.width, 0.01));
    expect(genres.height, clear.height);
    await tester.tap(find.byKey(const ValueKey('tv-search-genres')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    expect(repo.requests.single.query, '');
    expect(repo.requests.single.filters!.genres, ['Action']);
    expect(find.byKey(const ValueKey('tv-key-A')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tv-search-clear-filters')));
    await tester.pumpAndSettle();
    expect(repo.requests.last.filters!.genres, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('SearchScreenTv shows idle state when bloc is idle', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
    addTearDown(bloc.close);

    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pump();

    expect(find.text('Search for something to watch'), findsOneWidget);
    // The scope chips are always visible (2 TvFocusables), but no result
    // cards exist in idle state. Clear history is hidden until recents exist.
    expect(find.byType(TvFocusable), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('tv-search-scope-current')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tv-search-clear-history')), findsNothing);
  });

  testWidgets('fixed Home source replaces all/current source controls', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      _buildUnderTest(
        bloc,
        fixedSourceId: 'cs:selected',
        fixedSourceName: 'Selected Source',
      ),
    );
    await tester.pump();

    expect(find.text('Searching Selected Source'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-scope-all')), findsNothing);
    expect(find.byKey(const ValueKey('tv-search-scope-current')), findsNothing);
  });

  testWidgets(
    'SearchScreenTv renders result poster cards wrapped in TvFocusable '
    'and the first result card has autofocus',
    (tester) async {
      final group = SourceResultGroup(
        sourceId: 'test',
        sourceName: 'Test Source',
        items: [item1, item2],
        arrivalIndex: 0,
      );
      final bloc = _FakeSearchBloc(
        SearchState(
          status: SearchStatus.success,
          query: 'titan',
          groups: [group],
          sourceFilter: kAllSources,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildUnderTest(bloc));
      await tester.pump();

      // Both titles render as poster cards.
      expect(find.text('Attack on Titan'), findsOneWidget);
      expect(find.text('Demon Slayer'), findsOneWidget);

      // Each result card is wrapped in TvFocusable (plus the 2 scope chips
      // that render above the results regardless of state).
      final focusables = tester
          .widgetList<TvFocusable>(find.byType(TvFocusable))
          .toList();
      expect(focusables.length, greaterThanOrEqualTo(4));

      // The first result card (not the scope chips) carries autofocus=true
      // so D-pad DOWN from the search field lands here immediately.
      final firstCard = focusables.firstWhere((f) => f.autofocus);
      expect(firstCard.key, isNot(const ValueKey('tv-search-scope-current')));
      expect(firstCard.key, isNot(const ValueKey('tv-search-scope-all')));
    },
  );

  testWidgets('SearchScreenTv shows error state when bloc emits error', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.error));
    addTearDown(bloc.close);

    await tester.pumpWidget(_buildUnderTest(bloc));
    await tester.pump();

    expect(find.text('Search failed — try again'), findsOneWidget);
  });

  testWidgets(
    'SearchScreenTv shows no-results message on success with empty groups',
    (tester) async {
      final bloc = _FakeSearchBloc(
        SearchState(
          status: SearchStatus.success,
          query: 'xyznotfound',
          groups: [],
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildUnderTest(bloc));
      await tester.pump();

      expect(find.textContaining('No results for'), findsOneWidget);
    },
  );

  // ── TvTextField: arrowDown leaves the field regardless of accessibleNav ───
  //
  // A bare TextField plus the leanback IME used to trap D-pad DOWN. TvTextField
  // routes arrows to focusInDirection while not editing. The scope chips
  // ("All sources"/"Current source") render unconditionally below the field,
  // so they're always a valid down-traversal target regardless of search
  // state.

  testWidgets(
    'SearchScreenTv TvTextField: arrowDown moves focus out of the field when '
    'a screen reader is OFF (sighted user, original behaviour)',
    (tester) async {
      final bloc = _FakeSearchBloc(SearchState());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        BlocProvider<SearchBloc>.value(
          value: bloc,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(accessibleNavigation: false),
              child: const SearchScreenTv(scope: SearchScope.sources),
            ),
          ),
        ),
      );
      await tester.pump();

      // Autofocus lands on the nav chrome (not the edit node), so the IME
      // stays closed and arrows can leave the field.
      final editNode = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(editNode.hasFocus, isFalse);
      final before = tester.binding.focusManager.primaryFocus;
      expect(before, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(tester.binding.focusManager.primaryFocus, isNot(same(before)));
      expect(editNode.hasFocus, isFalse);
    },
  );

  testWidgets(
    'SearchScreenTv TvTextField: arrowDown still moves focus out of the field '
    'when a screen reader is ON (D-pad stays live even when the TV falsely '
    'reports one)',
    (tester) async {
      final bloc = _FakeSearchBloc(SearchState());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        BlocProvider<SearchBloc>.value(
          value: bloc,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(accessibleNavigation: true),
              child: const SearchScreenTv(scope: SearchScope.sources),
            ),
          ),
        ),
      );
      await tester.pump();

      final editNode = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(editNode.hasFocus, isFalse);
      final before = tester.binding.focusManager.primaryFocus;
      expect(before, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(tester.binding.focusManager.primaryFocus, isNot(same(before)));
      expect(editNode.hasFocus, isFalse);
    },
  );

  testWidgets('SearchScreenTv idle lists recent searches and a Clear button', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
    addTearDown(bloc.close);
    final history = _MutableSearchHistory(['Naruto', 'One Piece']);

    await tester.pumpWidget(_buildUnderTest(bloc, history: history));
    await tester.pump();

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Naruto'), findsOneWidget);
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tv-search-clear-history')),
      findsOneWidget,
    );
    expect(find.text('Search for something to watch'), findsNothing);
    // OK must fire on KeyUp. KeyDown would dispose this row and land the
    // leftover KeyUp on Filters, which then opens the filter dialog.
    final recents = tester
        .widgetList<TvListFocusable>(find.byType(TvListFocusable))
        .toList();
    expect(recents, isNotEmpty);
    expect(recents.every((r) => r.waitForKeyUp), isTrue);
  });

  testWidgets(
    'SearchScreenTv Clear wipes recents and returns to the empty idle prompt',
    (tester) async {
      final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
      addTearDown(bloc.close);
      final history = _MutableSearchHistory(['Naruto']);

      await tester.pumpWidget(_buildUnderTest(bloc, history: history));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('tv-search-clear-history')));
      await tester.pump();

      expect(history.recent(), isEmpty);
      expect(find.text('Recent searches'), findsNothing);
      expect(
        find.byKey(const ValueKey('tv-search-clear-history')),
        findsNothing,
      );
      expect(find.text('Search for something to watch'), findsOneWidget);
    },
  );

  testWidgets('Back from results clears the query and returns to idle Search', (
    tester,
  ) async {
    final group = SourceResultGroup(
      sourceId: 'test',
      sourceName: 'Test Source',
      items: [item1],
      arrivalIndex: 0,
    );
    final bloc = _FakeSearchBloc(
      SearchState(
        status: SearchStatus.success,
        query: 'titan',
        groups: [group],
        sourceFilter: kAllSources,
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_buildUnderTest(bloc, initialQuery: 'titan'));
    await tester.pump();

    expect(find.text('Attack on Titan'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(bloc.state.query, isEmpty);
    expect(bloc.state.status, SearchStatus.idle);
    expect(find.text('Attack on Titan'), findsNothing);
    expect(find.text('Search for something to watch'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('Back from a pushed idle Search still pops the route', (
    tester,
  ) async {
    final bloc = _FakeSearchBloc(SearchState(status: SearchStatus.idle));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider<SearchBloc>.value(
        value: bloc,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const SearchScreenTv(scope: SearchScope.sources),
                  ),
                ),
                child: const Text('open-search'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreenTv), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreenTv), findsNothing);
    expect(find.text('open-search'), findsOneWidget);
  });
}
