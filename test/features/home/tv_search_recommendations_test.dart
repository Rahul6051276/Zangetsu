import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/features/home/tv_search_input_screen.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';

const solo = MediaItem(
  id: 'solo',
  title: 'Solo Leveling',
  url: '/solo',
  type: ProviderType.anime,
  sourceId: 'metadata',
);
const solanin = MediaItem(
  id: 'solanin',
  title: 'Solanin',
  url: '/solanin',
  type: ProviderType.anime,
  sourceId: 'metadata',
);
const unrelated = MediaItem(
  id: 'naruto',
  title: 'Naruto',
  url: '/naruto',
  type: ProviderType.anime,
  sourceId: 'metadata',
);
const alternative = MediaItem(
  id: 'solo2',
  title: 'Ore dake Level Up na Ken',
  englishTitle: 'Solo Leveling Season 2',
  url: '/solo2',
  type: ProviderType.anime,
  sourceId: 'metadata',
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('OK opening Search cannot type A on its release on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) => opened
                  ? const TvSearchInputScreen(
                      initialQuery: '',
                      compactStyle: true,
                      inlineSearch: true,
                    )
                  : TvFocusable(
                      autofocus: true,
                      onTap: () => update(() => opened = true),
                      child: const Text('Search'),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(opened, isTrue);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'tv-new-search-first-key',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('tv-search-draft')))
              .data,
          'Search',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('tv-search-draft')))
              .data,
          'A',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  testWidgets('New starts on the keyboard when its shell tab becomes active', (
    tester,
  ) async {
    var active = false;
    final shellEntry = FocusNode();
    addTearDown(shellEntry.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ExcludeFocus(
              excluding: !active,
              child: TvSearchInputScreen(
                initialQuery: '',
                compactStyle: true,
                inlineSearch: true,
                controls: Focus(
                  focusNode: shellEntry,
                  child: const Text('Filters'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => active = true);
    await tester.pumpAndSettle();
    // RootShell seeds a focusable leaf after enabling the destination.
    shellEntry.requestFocus();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.debugLabel,
      'tv-new-search-first-key',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'H',
    );
  });
  testWidgets(
    'Tanya matches inside English titles and preserves catalogue aliases',
    (tester) async {
      tester.view.physicalSize = const Size(960, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const tanya = MediaItem(
        id: 'tanya',
        title: 'Youjo Senki',
        englishTitle: 'The Saga of Tanya the Evil',
        url: '/tanya',
        type: ProviderType.anime,
        sourceId: 'metadata',
        cover: 'https://artwork.invalid/tanya-poster.jpg',
        banner: 'https://artwork.invalid/tanya-banner.jpg',
      );
      const alias = MediaItem(
        id: 'alias',
        title: 'Youjo Senki Movie',
        url: '/movie',
        type: ProviderType.anime,
        sourceId: 'metadata',
      );
      const short = MediaItem(
        id: 'short',
        title: 'Tanya',
        url: '/short',
        type: ProviderType.anime,
        sourceId: 'metadata',
      );
      var revision = 0;
      late StateSetter update;
      final queries = <String>[];
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TvSearchInputScreen(
                initialQuery: 'tanya',
                compactStyle: true,
                inlineSearch: true,
                requestKey: revision,
                controls: const SizedBox(
                  height: 34,
                  child: Text('Filters and genres'),
                ),
                onSearchSubmitted: submitted.add,
                loadRecommendations: (query) async {
                  queries.add(query);
                  return [tanya, alias, short];
                },
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(queries, ['tanya']);
      expect(find.text('The Saga of Tanya the Evil'), findsNWidgets(2));
      expect(find.text('Youjo Senki Movie'), findsNWidgets(2));
      expect(
        tester.getSize(find.byKey(const ValueKey('tv-search-keyboard'))).width,
        300,
      );
      final longArt = tester.getSize(
        find.byKey(const ValueKey('tv-recommendation-art-metadata-tanya')),
      );
      final shortArt = tester.getSize(
        find.byKey(const ValueKey('tv-recommendation-art-metadata-short')),
      );
      expect(longArt, shortArt);
      expect(longArt.width / longArt.height, closeTo(2 / 3, 0.001));
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(
            const ValueKey('tv-recommendation-art-metadata-tanya'),
          ),
          matching: find.byType(Image),
        ),
      );
      expect(
        ((image.image as ResizeImage).imageProvider as NetworkImage).url,
        tanya.cover,
      );
      final keyboard = tester.getRect(
        find.byKey(const ValueKey('tv-search-keyboard')),
      );
      final controls = tester.getRect(
        find.byKey(const ValueKey('tv-search-keyboard-controls')),
      );
      final history = tester.getRect(
        find.byKey(const ValueKey('tv-search-history-column')),
      );
      expect(history.width, lessThanOrEqualTo(360));
      expect(keyboard.left - history.right, closeTo(24, 0.01));
      expect(controls.left, keyboard.left);
      expect(controls.right, keyboard.right);
      expect(controls.top, greaterThanOrEqualTo(keyboard.bottom));
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('tv-recommendation-metadata-tanya')),
            )
            .dy,
        lessThan(500),
      );
      await tester.tap(find.byKey(const ValueKey('tv-key-done')));
      await tester.pumpAndSettle();
      expect(submitted, ['tanya']);
      expect(find.byKey(const ValueKey('tv-key-A')), findsOneWidget);
      expect(find.text('Results'), findsOneWidget);
      update(() => revision++);
      await tester.pumpAndSettle();
      expect(queries, ['tanya', 'tanya', 'tanya']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'typos predict recent text and matching cards in a compact TV viewport',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: TvSearchInputScreen(
            initialQuery: 'slo',
            compactStyle: true,
            recentQueries: const ['Solo Leveling', 'Naruto'],
            loadRecommendations: (query) async {
              requests.add(query);
              return query == 'Solo Leveling' ? [solo] : [];
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requests, ['slo', 'Solo Leveling']);
      expect(find.text('Search suggestions'), findsOneWidget);
      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Naruto'), findsNothing);
      expect(find.text('Solo Leveling'), findsNWidgets(2));
      final card = find.byKey(
        const ValueKey('tv-recommendation-metadata-solo'),
      );
      expect(tester.getBottomRight(card).dy, lessThan(540));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tv-key-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Search suggestions'), findsNothing);
      expect(find.text('Naruto'), findsOneWidget);
    },
  );
  testWidgets(
    'recommendations start at three characters and only match title prefixes',
    (tester) async {
      final requests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: TvSearchInputScreen(
            initialQuery: '',
            compactStyle: true,
            loadRecommendations: (query) async {
              requests.add(query);
              return [solo, solanin, unrelated, alternative, solo];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in ['S', 'O']) {
        await tester.tap(find.byKey(ValueKey('tv-key-$key')));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, isEmpty);
      expect(find.text('Recommendations'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tv-key-L')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(requests, ['Sol']);
      expect(find.text('Solo Leveling'), findsNWidgets(2));
      expect(find.text('Solanin'), findsNWidgets(2));
      expect(find.text('Solo Leveling Season 2'), findsNWidgets(2));
      expect(find.text('Naruto'), findsNothing);
      expect(
        find.byKey(const ValueKey('tv-recommendation-metadata-solo')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('tv-key-delete')));
      await tester.pump();
      expect(find.text('Recommendations'), findsNothing);
      expect(find.text('Solo Leveling'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, ['Sol']);
    },
  );

  testWidgets(
    'late recommendations cannot reappear after deleting below three characters',
    (tester) async {
      final pending = Completer<List<MediaItem>>();
      await tester.pumpWidget(
        MaterialApp(
          home: TvSearchInputScreen(
            initialQuery: 'sol',
            compactStyle: true,
            loadRecommendations: (_) => pending.future,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('tv-key-delete')));
      await tester.pump();
      pending.complete([solo]);
      await tester.pumpAndSettle();
      expect(find.text('Recommendations'), findsNothing);
      expect(find.text('Solo Leveling'), findsNothing);
    },
  );

  testWidgets('choosing a recommendation completes typing with its title', (
    tester,
  ) async {
    MediaItem? selected;
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => TvSearchInputScreen(
                    initialQuery: 'sol',
                    compactStyle: true,
                    loadRecommendations: (_) async => [solo],
                    onRecommendationSelected: (item) => selected = item,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tv-recommendation-metadata-solo')),
    );
    await tester.pumpAndSettle();
    expect(selected, solo);
    expect(result, 'Solo Leveling');
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
  });
}
