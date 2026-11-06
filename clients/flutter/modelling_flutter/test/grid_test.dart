import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';
import 'package:modelling_flutter/src/renderers/blocks/grid_drop.dart' show DropPlaceholder;
import 'package:modelling_flutter/src/renderers/blocks/grid_layout.dart' show spanFor, GridFlow;
import 'package:modelling_flutter/src/shared/slop_draggable.dart';

import 'support/fixtures.dart';

Finder area(String id) => find.byKey(ValueKey('model-area-$id'));

Future<ModelController> pumpGrid(WidgetTester tester) async {
  final c = ModelController(appModel(), profile: androidProfile());
  await pumpApp(tester, BlocksBoard(controller: c, grid: true));
  return c;
}

final preview = find.byKey(const ValueKey('drop-preview'));

/// Presses at [from] and moves past the drag slop, so a drag is under way.
Future<TestGesture> lift(WidgetTester tester, Offset from) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await g.moveBy(const Offset(12, 12));
  await tester.pump();
  return g;
}

/// Moves a lifted drag to [to] (in two steps, as a pointer does).
Future<void> hover(WidgetTester tester, TestGesture g, Offset to) async {
  await g.moveTo(to - const Offset(1, 1));
  await tester.pump();
  await g.moveTo(to);
  await tester.pump();
}

/// The width of the grid that lays out [id].
double gridWidth(WidgetTester tester, String id) =>
    tester.getSize(find.ancestor(of: area(id), matching: find.byType(GridFlow)).first).width;

void main() {
  group('packGrid', () {
    test('auto children share a row, spare columns go to them', () {
      expect(packGrid([null, null, null]), const [GridSlot(0, 0, 4), GridSlot(0, 4, 3), GridSlot(0, 7, 3)]);
      expect(packGrid([null, null]), const [GridSlot(0, 0, 5), GridSlot(0, 5, 5)]);
      expect(packGrid([null]), const [GridSlot(0, 0, 10)]);
    });

    test('explicit widths keep their span and rows wrap past 10', () {
      expect(packGrid([4, 4, 4]), const [GridSlot(0, 0, 4), GridSlot(0, 4, 4), GridSlot(1, 0, 4)]);
      expect(packGrid([7, null]), const [GridSlot(0, 0, 7), GridSlot(0, 7, 3)]);
      expect(packGrid([10, 3]), const [GridSlot(0, 0, 10), GridSlot(1, 0, 3)]);
    });

    test('a wide (container) child takes at least half a row; fewer auto columns stack', () {
      expect(packGrid([null, null, null], wide: [true]), const [
        GridSlot(0, 0, 6),
        GridSlot(0, 6, 4),
        GridSlot(1, 0, 10),
      ]);
      expect(packGrid([null, null], autoColumns: 1), const [GridSlot(0, 0, 10), GridSlot(1, 0, 10)]);
      expect(autoSpan(5, 3), 3);
    });
  });

  testWidgets('grid mode is off by default and the default blocks look is unchanged', (tester) async {
    expect(const BlocksRenderer().grid, isFalse);
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    expect(find.byKey(const ValueKey('model-area-root')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-canvas')), findsNothing);
    expect(find.byKey(const ValueKey('resize-corner-ui')), findsNothing);
    // The root area still carries the model title, as labs' board does.
    expect(find.text('Payment app'), findsOneWidget);
  });

  testWidgets('grid mode puts the top level on the canvas, without a root card', (tester) async {
    await pumpGrid(tester);
    expect(find.byKey(const ValueKey('grid-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-area-root')), findsNothing);
    expect(find.text('Payment app'), findsNothing);
    expect(area('app'), findsOneWidget);
  });

  testWidgets('resize snaps to tenths and rows, shows the size, and writes one undoable view.put', (tester) async {
    final c = await pumpGrid(tester);
    final width = gridWidth(tester, 'ui');
    const gap = 12.0;
    final column = (width - 9 * gap) / 10;
    final start = spanFor(tester.getSize(area('ui')).width, width, gap);

    // Right edge: one column wider, plus a little that snaps away.
    final edge = find.byKey(const ValueKey('resize-right-ui'));
    final g = await tester.startGesture(tester.getCenter(edge), kind: PointerDeviceKind.mouse);
    await g.moveBy(Offset(column + gap + column * 0.3, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('resize-readout')), findsOneWidget);
    expect(find.text('${(start + 1) * 10}% · auto'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(c.sizes['ui'], NodeSize(w: start + 1));
    expect(c.model.views.where((v) => v.id == 'layout').single.sizes, {'ui': NodeSize(w: start + 1)});
    expect(find.byKey(const ValueKey('resize-readout')), findsNothing);
    expect(spanFor(tester.getSize(area('ui')).width, width, gap), start + 1);

    // Bottom edge: to 3 rows (3 × 44 + 2 gaps), keeping the width.
    final height = tester.getSize(area('ui')).height;
    final bottom = find.byKey(const ValueKey('resize-bottom-ui'));
    final g2 = await tester.startGesture(tester.getCenter(bottom), kind: PointerDeviceKind.mouse);
    await g2.moveBy(Offset(0, 3 * 44 + 2 * gap - height + 5));
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();
    expect(c.sizes['ui'], NodeSize(w: start + 1, h: 3));
    expect(tester.getSize(area('ui')).height, 3 * 44 + 2 * gap);

    c.undo();
    await tester.pumpAndSettle();
    expect(c.sizes['ui'], NodeSize(w: start + 1));
    c.undo();
    await tester.pumpAndSettle();
    expect(c.sizes, isEmpty);
    expect(c.model.views.where((v) => v.id == 'layout'), isEmpty);
  });

  testWidgets('double-clicking a resize handle returns the area to auto', (tester) async {
    final c = await pumpGrid(tester);
    c.setSizes({'ui': const NodeSize(w: 3, h: 2)});
    await tester.pumpAndSettle();
    final corner = find.byKey(const ValueKey('resize-corner-ui'));
    await tester.tap(corner);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(corner);
    await tester.pumpAndSettle();
    expect(c.sizes.containsKey('ui'), isFalse);
  });

  testWidgets('a card drags from anywhere on its body; a click still selects it', (tester) async {
    final c = await pumpGrid(tester);
    expect(find.byTooltip('Drag to move or reorder UI layer'), findsNothing);
    // A click inspects the card (here in a dialog, as there is no docked
    // inspector).
    await tapOnce(tester, find.descendant(of: area('ui'), matching: find.text('UI layer')));
    expect(c.selection, const ModelElementRef.node('ui'));
    expect(find.text('Area · ui'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(c.index.children('app'), ['ui', 'net']);

    final net = tester.getRect(area('net'));
    final g = await lift(tester, tester.getCenter(find.descendant(of: area('ui'), matching: find.text('UI layer'))));
    await hover(tester, g, Offset(net.right - 16, net.top + 30));
    expect(preview, findsOneWidget);
    // The placeholder stands where the card would land: after Network
    // layer (the card itself stays put, faded, until it lands).
    await tester.pumpAndSettle();
    final p = tester.getRect(preview), n = tester.getRect(area('net'));
    expect(p.top > n.top || p.left > n.left, isTrue);
    await g.up();
    await tester.pumpAndSettle();
    expect(c.index.children('app'), ['net', 'ui']);
    expect(preview, findsNothing);
    c.undo();
    expect(c.index.children('app'), ['ui', 'net']);
  });

  testWidgets('dragging a card onto the middle of another moves it inside, with an inside highlight', (tester) async {
    final c = await pumpGrid(tester);
    final g = await lift(tester, tester.getCenter(find.descendant(of: area('ui'), matching: find.text('UI layer'))));
    await hover(tester, g, tester.getCenter(find.text('Native libraries')));
    // Inside, not beside: no placeholder, the card lights up.
    expect(preview, findsNothing);
    final native = tester.widget<AnimatedContainer>(area('native'));
    expect((native.decoration! as BoxDecoration).border!.top.width, 1.5);
    await g.up();
    await tester.pumpAndSettle();
    expect(c.index.parent('ui'), 'native');
    c.undo();
    expect(c.index.parent('ui'), 'app');
  });

  testWidgets('a card dropped beside one in another area and row moves there in one edit', (tester) async {
    final c = await pumpGrid(tester);
    final server = find.descendant(of: area('server'), matching: find.text('Payment server'));
    final ui = tester.getRect(area('ui'));
    final g = await lift(tester, tester.getCenter(server));
    await hover(tester, g, Offset(ui.left + 6, ui.center.dy));
    expect(preview, findsOneWidget);
    // The preview sits in UI layer's grid, ahead of it, and UI layer moves
    // over to make room.
    await tester.pumpAndSettle();
    expect(find.ancestor(of: preview, matching: area('app')), findsOneWidget);
    expect(tester.getRect(area('ui')).left, greaterThan(ui.left));
    expect(tester.getRect(preview).left, closeTo(ui.left, 1));
    await g.up();
    await tester.pumpAndSettle();
    expect(c.index.parent('server'), 'app');
    expect(c.index.children('app'), ['server', 'ui', 'net']);
    c.undo();
    expect(c.index.parent('server'), '');
  });

  testWidgets('a refused drop previews in the error colour and explains itself', (tester) async {
    final c = await pumpGrid(tester);
    // The profile keeps classes out of applications: Certificate pinner
    // cannot sit beside UI layer.
    final ui = tester.getRect(area('ui'));
    final g = await lift(tester, tester.getCenter(find.text('Certificate pinner')));
    await hover(tester, g, Offset(ui.left + 6, ui.center.dy));
    expect(find.byWidgetPredicate((w) => w is DropPlaceholder && w.refused), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(c.index.parent('pinner'), 'net');
    expect(c.notice.value, isNotNull);
  });

  testWidgets('the reflow glides, and snaps under reduced motion', (tester) async {
    for (final reduced in [false, true]) {
      final c = ModelController(appModel(), profile: androidProfile());
      await pumpApp(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: BlocksBoard(controller: c, grid: true),
          ),
        ),
      );
      final ui = tester.getRect(area('ui'));
      final g = await lift(tester, tester.getCenter(find.text('Payment server')));
      await hover(tester, g, Offset(ui.left + 6, ui.center.dy));
      expect(preview, findsOneWidget);
      expect(tester.hasRunningAnimations, !reduced, reason: 'reduced: $reduced');
      await g.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the relate handle still draws a relationship from inside a draggable card', (tester) async {
    final c = ModelController(appModel());
    await pumpApp(tester, BlocksBoard(controller: c, grid: true));
    await dragTo(
      tester,
      find.byTooltip('Drag to relate Payment server to another area'),
      find.text('Native libraries'),
    );
    expect(find.text('Payment server → Native libraries'), findsOneWidget);
    // The card itself did not move.
    expect(c.index.parent('server'), '');
  });

  testWidgets('read-only grid has no handles', (tester) async {
    final c = ModelController(appModel(), readOnly: true);
    await pumpApp(tester, BlocksBoard(controller: c, grid: true));
    expect(area('ui'), findsOneWidget);
    expect(find.byKey(const ValueKey('resize-corner-ui')), findsNothing);
    expect(find.byType(SlopDraggable<Object>), findsNothing);
  });

  testWidgets('the board zoom scales the grid like page zoom: same width, smaller text', (tester) async {
    final c = await pumpGrid(tester);
    final card = tester.getRect(area('app')).width;
    final text = tester.getRect(find.text('Application').first).height;
    c.zoom.value = 0.5;
    await tester.pumpAndSettle();
    expect(tester.getRect(area('app')).width, closeTo(card, 5));
    expect(tester.getRect(find.text('Application').first).height, closeTo(text / 2, 1));
  });
}
