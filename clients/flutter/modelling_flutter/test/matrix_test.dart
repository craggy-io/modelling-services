import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder row(String id) => find.byKey(ValueKey('matrix-row-$id'));
Finder cell(String from, String to) => find.byKey(ValueKey('matrix-cell-$from-$to'));

void main() {
  test('rows follow containment; cells count relationships, undirected both ways', () {
    final l = layoutMatrix(ModelController(appModel()));
    expect([for (final n in l.nodes) n.id], ['app', 'ui', 'net', 'pinner', 'native', 'server']);
    expect(l.spans, [(0, 3), (2, 3)]);
    expect(l.cells[(row: 1, column: 2)], ['e1']);
    expect(l.cells[(row: 1, column: 4)], ['e4']);
    expect(l.cells[(row: 4, column: 1)], ['e4']);
    expect(l.cells[(row: 2, column: 1)], isNull);
  });

  testWidgets('draws a row per area and counts in cells', (tester) async {
    final c = ModelController(appModel(), renderer: 'matrix', readOnly: true, profile: androidProfile());
    await pumpWorkspace(tester, c, renderers: allRenderers);
    for (final id in ['app', 'ui', 'net', 'pinner', 'native', 'server']) {
      expect(row(id), findsOneWidget, reason: id);
    }
    expect(find.descendant(of: cell('ui', 'net'), matching: find.text('1')), findsOneWidget);
    expect(cell('native', 'ui'), findsOneWidget);
    expect(cell('net', 'ui'), findsNothing);
  });

  testWidgets('tapping a row selects its area', (tester) async {
    final c = ModelController(appModel(), renderer: 'matrix', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tapOnce(tester, row('net'));
    expect(c.selection, const ModelElementRef.node('net'));
  });

  testWidgets('tapping a cell lists its relationships; each can be inspected', (tester) async {
    final c = ModelController(appModel(), renderer: 'matrix', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tester.tap(cell('net', 'server'));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('matrix-cell-list'));
    expect(list, findsOneWidget);
    expect(
      find.descendant(of: list, matching: find.text('Network layer → Payment server · 1 relationship')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: list, matching: find.text('talks to')));
    await tester.pumpAndSettle();
    expect(c.selection, const ModelElementRef.edge('e2'));
    expect(find.text('Traffic capture'), findsOneWidget);

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(list, findsNothing);
  });

  testWidgets('diff mode keeps removed areas and relationships as ghosts', (tester) async {
    final c = ModelController(appRevision(), base: appModel(), renderer: 'matrix', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    expect(row('server'), findsOneWidget);
    expect(row('cache'), findsOneWidget);
    expect(cell('net', 'server'), findsOneWidget);

    c.changedOnly = true;
    await tester.pumpAndSettle();
    expect(row('pinner'), findsNothing);
  });
}
