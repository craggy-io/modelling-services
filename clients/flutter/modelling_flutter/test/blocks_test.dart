import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder area(String id) => find.byKey(ValueKey('model-area-$id'));

/// Matches a painting that draws [method] with a paint of [colour].
PaintPattern drawsWith(Symbol method, Color colour) => paints
  ..something((m, args) => m == method && args.whereType<Paint>().any((p) => p.color.toARGB32() == colour.toARGB32()));

Finder connectorPaint() =>
    find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter.runtimeType.toString() == 'ConnectorPainter');

void main() {
  group('board parity', () {
    testWidgets('draws nested areas, the status line and relationships', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);

      expect(find.text('Payment app'), findsOneWidget);
      expect(find.text('com.example.pay 4.2.1'), findsOneWidget);
      for (final id in ['app', 'ui', 'net', 'pinner', 'native', 'server']) {
        expect(area(id), findsOneWidget, reason: id);
      }
      expect(find.text('Showing 6 of 6 areas · 4 relationships'), findsOneWidget);
      expect(find.text('Relationships · 4'), findsOneWidget);
      // Read-only: no editing controls.
      expect(find.byTooltip('Undo'), findsNothing);
      expect(find.byTooltip('Edit Application'), findsNothing);
      // Nested areas sit inside their parents.
      expect(find.descendant(of: area('net'), matching: area('pinner')), findsOneWidget);
    });

    testWidgets('search narrows to matches and says where they are', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await tester.enterText(find.byKey(const ValueKey('model-search')).first, 'pinner');
      await tester.pumpAndSettle();
      expect(area('pinner'), findsOneWidget);
      expect(area('net'), findsNothing);
      expect(find.text('In Network layer'), findsOneWidget);
      expect(find.text('Search results across com.example.pay 4.2.1'), findsOneWidget);
      expect(find.text('Showing 1 of 6 areas · 4 relationships'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('model-search')).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching areas.'), findsOneWidget);
    });

    testWidgets('collapse and expand', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await tester.tap(find.byTooltip('Collapse Application'));
      await tester.pumpAndSettle();
      expect(find.text('2 areas collapsed'), findsOneWidget);
      expect(area('ui'), findsNothing);
      expect(c.collapsed, contains('app'));
      await tester.tap(find.byTooltip('Expand Application'));
      await tester.pumpAndSettle();
      expect(area('ui'), findsOneWidget);
    });

    testWidgets('areas deeper than openDepth start collapsed', (tester) async {
      final (deep, _) = apply(appModel(), [Op.nodeAdd(Node(id: 'pin2', label: 'Pin store', parent: 'pinner'))]);
      final c = ModelController(deep, readOnly: true);
      await pumpWorkspace(tester, c);
      expect(find.text('1 area collapsed'), findsOneWidget);
      expect(area('pin2'), findsNothing);
    });

    testWidgets('drill in and back to the parent area', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await tester.tap(find.byTooltip('Open Network layer'));
      await tester.pumpAndSettle();
      expect(c.trail, ['net']);
      expect(find.text('Back to parent area'), findsOneWidget);
      expect(area('ui'), findsNothing);
      expect(area('pinner'), findsOneWidget);
      await tester.tap(find.text('Back to parent area'));
      await tester.pumpAndSettle();
      expect(c.trail, isEmpty);
      expect(area('ui'), findsOneWidget);
    });

    testWidgets('pages with "Show more areas"', (tester) async {
      final c = ModelController(wideModel(50), readOnly: true);
      await pumpWorkspace(tester, c);
      expect(find.text('Showing 40 of 50 areas · 0 relationships'), findsOneWidget);
      await tester.ensureVisible(find.text('Show more areas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more areas'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 50 of 50 areas · 0 relationships'), findsOneWidget);
      expect(find.text('Show more areas'), findsNothing);
    });

    testWidgets('dots: hover previews the connector, click pins it', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      final dot = find.byTooltip('UI layer → calls → Network layer');
      expect(dot, findsWidgets);
      final colour = ModelTheme.of(tester.element(area('root'))).paletteAt(c.slotOf('e1'));
      final painter = tester.renderObject(connectorPaint());
      expect(painter, isNot(drawsWith(#drawCircle, colour)));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(dot.first));
      await tester.pump();
      expect(c.hovered.value, 'e1');
      expect(painter, drawsWith(#drawCircle, colour));

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(c.hovered.value, isNull);
      expect(painter, isNot(drawsWith(#drawCircle, colour)));

      await tester.tap(dot.first);
      await tester.pump();
      expect(c.isPinned('e1'), isTrue);
      expect(painter, drawsWith(#drawCircle, colour));
    });

    testWidgets('self-relationships paint a loop', (tester) async {
      final (m, _) = apply(appModel(), [Op.edgeAdd(Edge(id: 'self', from: 'net', to: 'net', label: 'retries'))]);
      final c = ModelController(m, readOnly: true)..togglePin('self');
      await pumpWorkspace(tester, c);
      expect(
        tester.renderObject(connectorPaint()),
        drawsWith(#drawPath, ModelTheme.of(tester.element(area('root'))).paletteAt(c.slotOf('self'))),
      );
    });

    testWidgets('inspector shows notes, relationships and evidence', (tester) async {
      Ref? opened;
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c, onEvidence: (r) => opened = r);
      await tester.tap(find.text('Network layer').first);
      await tester.pumpAndSettle();
      expect(c.selection, const ModelElementRef.node('net'));
      expect(find.text('Area · net'), findsOneWidget);
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('OkHttp with pinning.')), findsOneWidget);
      expect(find.text('RELATIONSHIPS'), findsOneWidget);
      expect(find.text('EVIDENCE'), findsOneWidget);
      expect(find.text('Pinner config'), findsOneWidget);
      expect(find.text('a1 · /res/xml/nsc.xml'), findsOneWidget);
      expect(find.text('CHECKS'), findsNothing); // only info findings without a profile? net has evidence

      await tester.tap(find.byTooltip('Open evidence'));
      await tester.pumpAndSettle();
      expect(opened, const Ref(scheme: 'artifact', id: 'a1', selector: '/res/xml/nsc.xml'));
    });

    testWidgets('inspector relationship rows open the relationship', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await tester.tap(find.text('2 relationships').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('calls').last);
      await tester.pumpAndSettle();
      expect(c.selection, isNotNull);
      expect(c.selection!.isNode, isFalse);
      expect(find.text('ENDS'), findsOneWidget);
    });

    testWidgets('link marker and the open-link action', (tester) async {
      Link? opened;
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c, onOpenLink: (l) => opened = l);
      expect(find.byKey(const ValueKey('link-native')), findsOneWidget);
      await tester.tap(find.text('Native libraries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened?.model, 'm-native');
    });
  });

  group('diff mode', () {
    testWidgets('marks changes, draws removed areas as ghosts, filters changed only', (tester) async {
      final c = ModelController(appRevision(), base: appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      expect(find.text('Showing 6 of 6 areas · 3 relationships · 4 changed from the base'), findsOneWidget);
      expect(area('server'), findsOneWidget); // ghost
      expect(find.bySemanticsLabel(RegExp('Area Payment server, removed since the base')), findsOneWidget);
      expect(find.byTooltip('Added: not in the base'), findsWidgets);
      expect(find.byTooltip('Changed from the base'), findsWidgets);
      expect(find.text('Relationships · 4'), findsOneWidget); // three, plus removed e2

      await tester.tap(find.text('Changed only'));
      await tester.pumpAndSettle();
      expect(c.changedOnly, isTrue);
      expect(area('native'), findsNothing);
      expect(area('cache'), findsOneWidget);
      expect(area('server'), findsOneWidget);

      await tester.tap(find.text('Payment server'));
      await tester.pumpAndSettle();
      expect(find.text('Area · server · Removed since the base'), findsOneWidget);
      expect(find.text('Delete area'), findsNothing);
    });

    testWidgets('inspector lists field changes', (tester) async {
      final c = ModelController(appRevision(), base: appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await tester.tap(find.text('Screens'));
      await tester.pumpAndSettle();
      expect(find.text('CHANGES FROM THE BASE'), findsOneWidget);
      expect(find.textContaining('UI layer', findRichText: true), findsWidgets);
    });
  });

  group('keyboard', () {
    testWidgets('arrows move, Enter inspects, Right drills in, Left goes back, Space folds', (tester) async {
      final c = ModelController(appModel(), readOnly: true);
      await pumpWorkspace(tester, c);
      await focusRenderer(tester, area('root'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.focused, 'app');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.focused, 'net');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.focused, 'ui');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('2 areas collapsed'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(c.trail, ['app']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(c.trail, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Area · app'), findsOneWidget);
    });
  });

  group('overlays and lint', () {
    testWidgets('overlay badges and legend, lint badges', (tester) async {
      const red = Color(0xFFFF0000);
      final c = ModelController(appModel(), profile: androidProfile(), readOnly: true)
        ..overlays = [
          const ModelOverlay(
            id: 'findings',
            label: 'Findings',
            legend: {'Open findings': red},
            marks: {'net': OverlayMark(badge: '3', color: red, value: 0.5)},
          ),
        ];
      await pumpWorkspace(tester, c);
      expect(find.byKey(const ValueKey('overlay-net')), findsNothing);
      expect(find.byKey(const ValueKey('lint-server')), findsOneWidget);

      c.activeOverlay = 'findings';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('overlay-net')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Open findings'), findsOneWidget);
    });
  });
}
