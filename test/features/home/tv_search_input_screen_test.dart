import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';
import 'package:watch_app/features/home/tv_search_input_screen.dart';

Future<void> openInput(WidgetTester tester, {String initial = ''}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => TvSearchInputScreen(initialQuery: initial),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only keyboard keys take D-pad focus; no system IME', (
    tester,
  ) async {
    await openInput(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        final context = tester.binding.focusManager.primaryFocus!.context!;
        final button = context.findAncestorWidgetOfExactType<TvFocusable>();
        expect(button, isNotNull);
        expect(button!.key.toString(), contains('tv-key-'));
      }
    }
    expect(
      find.byKey(const ValueKey('tv-search-input-screen')),
      findsOneWidget,
    );
  });

  testWidgets('remote OK types one key and Done returns the query', (
    tester,
  ) async {
    await openInput(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'q',
    );
    await tester.tap(find.byKey(const ValueKey('tv-key-space')));
    await tester.tap(find.byKey(const ValueKey('tv-key-a')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'q a',
    );
    await tester.tap(find.byKey(const ValueKey('tv-key-delete')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'q ',
    );
    await tester.tap(find.byKey(const ValueKey('tv-key-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
  });

  testWidgets('system Back needs two presses and keeps draft on first', (
    tester,
  ) async {
    await openInput(tester, initial: 'naruto');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tv-search-input-screen')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'naruto',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('tv-search-back-hint')))
          .data,
      isNotEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
  });

  testWidgets('remote Back confirmation resets when typing resumes', (
    tester,
  ) async {
    await openInput(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tv-search-input-screen')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-search-input-screen')), findsNothing);
  });

  testWidgets('delete removes a complete Unicode character and Clear empties', (
    tester,
  ) async {
    await openInput(tester, initial: 'a👨‍👩‍👧');
    await tester.tap(find.byKey(const ValueKey('tv-key-delete')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      'a',
    );
    await tester.tap(find.byKey(const ValueKey('tv-key-clear')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tv-search-draft'))).data,
      '|',
    );
  });
}
