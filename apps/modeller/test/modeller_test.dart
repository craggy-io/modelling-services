import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:modeller/src/modeller_app.dart';
import 'package:modeller/src/samples.dart';

Finder title(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('modeller-title') && w.data == text);

Future<void> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bundled = await tester.runAsync(() => Bundled.load(rootBundle));
  await tester.pumpWidget(ModellerApp(bundled: bundled!));
  await tester.pumpAndSettle();
}

Future<void> menu(WidgetTester tester, List<String> path) async {
  for (final item in path) {
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }
}

Future<void> renderer(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('renderer-$id')).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('boots on a blank model with every renderer', (tester) async {
    await boot(tester);
    expect(title('Untitled model'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    for (final label in ['Blocks', 'Outline', 'Graph', 'Matrix', 'Table']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('No profile'), findsOneWidget);
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
    expect(find.text('Showing 3 of 3 areas · 1 relationship'), findsOneWidget);
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
    expect(title('System context •'), findsOneWidget);

    await menu(tester, ['File', 'New blank']);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(title('System context •'), findsOneWidget);

    await menu(tester, ['File', 'New blank']);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(title('Untitled model'), findsOneWidget);
  });

  testWidgets('the gallery shows every renderer on each sample', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Gallery'));
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
