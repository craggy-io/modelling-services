import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'harness.dart';

Future<void> renderer(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('renderer-$id')).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('boots on a blank model with every renderer', (tester) async {
    await boot(tester);
    expect(title('Untitled model'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette-area')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-board')), findsOneWidget);
    for (final label in ['Blocks', 'Outline', 'Graph', 'Matrix', 'Table']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('No profile'), findsOneWidget);
  });

  testWidgets('the File menu: themed rows with icons, shortcut hints, dividers and a submenu', (tester) async {
    await boot(tester);
    // The trigger is a top bar button like the others, not a menu bar.
    expect(find.byType(MenuBar), findsNothing);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    for (final label in [
      'New blank',
      'New from template',
      'Import Mermaid or outline…',
      'Open…',
      'Save',
      'Save as…',
      'Export',
    ]) {
      expect(find.byKey(ValueKey('menu-$label')), findsOneWidget, reason: label);
    }
    for (final (label, keys) in [
      ('New blank', 'Ctrl+N'),
      ('Open…', 'Ctrl+O'),
      ('Save', 'Ctrl+S'),
      ('Save as…', 'Ctrl+Shift+S'),
    ]) {
      final row = find.byKey(ValueKey('menu-$label'));
      final hint = find.descendant(of: row, matching: find.text(keys));
      expect(hint, findsOneWidget, reason: label);
      // Hints line up on the right of their rows.
      expect(tester.getRect(hint).right, closeTo(tester.getRect(row).right - 8, 1), reason: label);
    }
    final rows = [
      for (final l in ['New blank', 'Open…', 'Save']) tester.getRect(find.byKey(ValueKey('menu-$l'))),
    ];
    expect(rows.map((r) => r.height).toSet(), {30});
    expect(find.descendant(of: find.byKey(const ValueKey('menu-Open…')), matching: find.byType(Icon)), findsOneWidget);
    // Submenus open beside, styled the same.
    await tester.tap(find.byKey(const ValueKey('menu-Export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-Copy Mermaid')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('menu-Copy Mermaid'))).left,
      greaterThan(tester.getRect(find.byKey(const ValueKey('menu-Export'))).right - 8),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('Ctrl+N starts a new model from anywhere in the editor', (tester) async {
    await boot(tester);
    await menu(tester, ['File', 'New from template', 'System context']);
    expect(title('System context'), findsOneWidget);
    Focus.of(tester.element(find.byKey(const ValueKey('grid-canvas')))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(title('Untitled model'), findsOneWidget);
  });

  testWidgets('new from template, then switch renderer', (tester) async {
    await boot(tester);
    await menu(tester, ['File', 'New from template', 'Payment app (Android)']);
    expect(title('Payment app'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-area-net')), findsOneWidget);
    // The template names the bundled profile, so it is picked.
    expect(find.text('Android application'), findsOneWidget);

    await renderer(tester, 'graph');
    expect(find.byKey(const ValueKey('graph-node-net')), findsOneWidget);
    await renderer(tester, 'matrix');
    expect(find.byKey(const ValueKey('matrix-row-net')), findsOneWidget);
    await renderer(tester, 'table');
    expect(find.byKey(const ValueKey('table-row-net')), findsOneWidget);
    await renderer(tester, 'outline');
    expect(find.byKey(const ValueKey('outline-net')), findsOneWidget);

    // The renderer survives opening another model.
    await menu(tester, ['File', 'New from template', 'System context']);
    expect(title('System context'), findsOneWidget);
    expect(find.byKey(const ValueKey('outline-shop')), findsOneWidget);
  });

  testWidgets('imports pasted Mermaid', (tester) async {
    await boot(tester);
    await menu(tester, ['File', 'Import Mermaid or outline…']);
    await tester.enterText(
      find.byKey(const ValueKey('import-text')),
      '---\ntitle: Pasted\n---\nflowchart TD\n  subgraph app[Application]\n    ui[UI] --> api[API]\n  end\n',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(title('Pasted'), findsOneWidget);
    expect(find.text('UI'), findsWidgets);
    expect(counts('3 areas  ·  1 relationship'), findsOneWidget);
  });

  testWidgets('bad import text explains itself', (tester) async {
    await boot(tester);
    await menu(tester, ['File', 'Import Mermaid or outline…']);
    await tester.enterText(find.byKey(const ValueKey('import-text')), 'flowchart TD\n  ???\n');
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mermaid line 2'), findsOneWidget);
    expect(title('Untitled model'), findsOneWidget);
  });

  testWidgets('choosing a profile edits the model; unsaved edits are confirmed before discarding', (tester) async {
    await boot(tester);
    await menu(tester, ['File', 'New from template', 'System context']);
    await tester.tap(find.byKey(const ValueKey('profile-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Android application').last);
    await tester.pumpAndSettle();
    expect(title('System context'), findsOneWidget);
    expect(dirty, findsOneWidget);

    await menu(tester, ['File', 'New blank']);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(title('System context'), findsOneWidget);
    expect(dirty, findsOneWidget);

    await menu(tester, ['File', 'New blank']);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(title('Untitled model'), findsOneWidget);
    expect(dirty, findsNothing);
  });

  testWidgets('the gallery shows every renderer on each sample', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('open-gallery')));
    await tester.pumpAndSettle();
    for (final id in ['blocks', 'outline', 'graph', 'matrix']) {
      expect(find.byKey(ValueKey('gallery-panel-$id')), findsOneWidget, reason: id);
    }
    await tester.tap(find.byKey(const ValueKey('sample-Diff: base vs revised')));
    await tester.pumpAndSettle();
    expect(find.textContaining('changed from the base'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sample-Overlay: open findings')));
    await tester.pumpAndSettle();
    expect(find.text('Open findings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gallery-panel-table')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('gallery-panel-table')), findsOneWidget);
  });
}
