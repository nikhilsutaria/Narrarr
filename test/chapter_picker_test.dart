import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/chapter_picker.dart';

/// Widget coverage for the Contents (TOC) picker bottom sheet: it lists
/// chapters, marks the current one, and resolves to the tapped index (or null
/// on dismiss).
void main() {
  const titles = ['Book IX', 'Book X', 'Book XI'];

  // Pumps a button that opens the picker and records its result.
  Future<int?> openPicker(WidgetTester tester, {int current = 0}) async {
    int? result;
    var resolved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showChapterPicker(
                context,
                titles: titles,
                currentIndex: current,
              );
              resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return Future.value(resolved ? result : null);
  }

  testWidgets('lists every chapter title and the Contents header',
      (tester) async {
    await openPicker(tester);
    expect(find.text('Contents'), findsOneWidget);
    for (final t in titles) {
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('marks the currently-narrating chapter as "Now playing"',
      (tester) async {
    await openPicker(tester, current: 1);
    expect(find.text('Now playing'), findsOneWidget);
    // The "Now playing" label sits on the current chapter's tile.
    final tile = find.ancestor(
      of: find.text('Now playing'),
      matching: find.byType(ListTile),
    );
    expect(find.descendant(of: tile, matching: find.text('Book X')),
        findsOneWidget);
  });

  testWidgets('tapping a chapter returns its index', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showChapterPicker(
                context,
                titles: titles,
                currentIndex: 0,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book XI'));
    await tester.pumpAndSettle();

    expect(picked, 2);
  });

  testWidgets('dismissing without choosing returns null', (tester) async {
    int? picked = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showChapterPicker(
                context,
                titles: titles,
                currentIndex: 0,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the scrim (top-left, outside the sheet) to dismiss.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });
}
