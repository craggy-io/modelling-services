import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder node(String id) => find.byKey(ValueKey('graph-node-$id'));
Finder edge(String id) => find.byKey(ValueKey('graph-edge-$id'));

void main() {
  group('layout', () {
    test('contains nested areas in compound boxes and layers along relationships', () {
      final c = ModelController(appModel());
      final l = layoutGraph(c, ModelTheme.fallback());
      final box = {for (final b in l.boxes.values) b.id: b.rect};
      expect(box.keys, ['app', 'ui', 'net', 'pinner', 'native', 'server']);
      expect(l.boxes['app']!.container, isTrue);
      expect(box['app']!.contains(box['ui']!.center), isTrue);
      expect(box['net']!.contains(box['pinner']!.center), isTrue);
      // ui calls net: net's layer is to the right of ui's.
      expect(box['net']!.left, greaterThan(box['ui']!.right));
      // app (lifted from pinner, net) points at native and server.
      expect(box['server']!.left, greaterThan(box['app']!.right));
      expect(l.edges, ['e1', 'e2', 'e3', 'e4']);
    });

    test('is deterministic and honours saved positions', () {
      final c = ModelController(appModel());
      final t = ModelTheme.fallback();
      final a = layoutGraph(c, t), b = layoutGraph(c, t);
      expect([for (final x in a.boxes.values) x.rect], [for (final x in b.boxes.values) x.rect]);

      c.setPositions({'net': (900, 700)});
      final moved = layoutGraph(c, t);
      expect(moved.boxes['net']!.rect.topLeft, const Offset(900, 700));
      // The contents move with it and the container grows to enclose it.
      expect(moved.boxes['net']!.rect.contains(moved.boxes['pinner']!.rect.center), isTrue);
      expect(moved.boxes['app']!.rect.contains(const Offset(905, 705)), isTrue);
    });
  });

  testWidgets('draws areas and relationship labels with marks', (tester) async {
    final c = ModelController(appModel(), renderer: 'graph', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    for (final id in ['app', 'ui', 'net', 'pinner', 'native', 'server']) {
      expect(node(id), findsOneWidget, reason: id);
    }
    for (final id in ['e1', 'e2', 'e3', 'e4']) {
      expect(edge(id), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('link-native')), findsOneWidget);
    expect(find.text('Showing 6 of 6 areas · 4 relationships'), findsOneWidget);
    expect(find.byTooltip('Zoom to fit'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom to fit'));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping selects; double-tapping inspects', (tester) async {
    final c = ModelController(appModel(), renderer: 'graph', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tapOnce(tester, node('net'));
    expect(c.selection, const ModelElementRef.node('net'));
    await tapOnce(tester, edge('e1'));
    expect(c.selection, const ModelElementRef.edge('e1'));

    await tester.tap(node('server'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node('server'));
    await tester.pumpAndSettle();
    expect(find.text('Area · server'), findsOneWidget);
  });

  testWidgets('dragging an area saves its position in the view, undoably', (tester) async {
    final c = ModelController(appModel(), renderer: 'graph');
    await pumpWorkspace(tester, c, renderers: allRenderers);
    final before = layoutGraph(c, ModelTheme.fallback()).boxes['server']!.place;
    await tester.drag(node('server'), const Offset(0, 160));
    await tester.pumpAndSettle();

    final p = c.positions['server'];
    expect(p, isNotNull);
    expect(p!.$1, before.dx);
    expect(p.$2, greaterThan(before.dy));
    expect(c.model.views.where((v) => v.positions.containsKey('server')), hasLength(1));
    expect(c.dirty, isTrue);
    expect(find.text('Auto layout'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(c.positions, isEmpty);
  });

  testWidgets('read-only areas do not move', (tester) async {
    final c = ModelController(appModel(), renderer: 'graph', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tester.drag(node('server'), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(c.positions, isEmpty);
    expect(c.dirty, isFalse);
  });

  testWidgets('diff mode shows removed ghosts and change marks; search narrows', (tester) async {
    final c = ModelController(appRevision(), base: appModel(), renderer: 'graph', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    expect(node('server'), findsOneWidget);
    expect(edge('e2'), findsOneWidget);
    expect(find.byType(ChangeMarker), findsWidgets);

    c.search = 'pinner';
    await tester.pumpAndSettle();
    expect(node('pinner'), findsOneWidget);
    expect(node('ui'), findsNothing);
  });
}
