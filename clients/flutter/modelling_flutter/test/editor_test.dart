import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:modelling_flutter/src/editor/editor_panels.dart' show panelWidths;
import 'package:modelling_flutter/src/editor/editor_top_bar.dart' show EditorTopBar;
import 'package:modelling_flutter/src/editor/view_switcher.dart' show ViewSwitcher, trackInset;

import 'support/fixtures.dart';

Finder area(String id) => find.byKey(ValueKey('model-area-$id'));

Future<ModelController> pumpEditor(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  Model? model,
  ModelSaveHook? onSave,
  List<ModelRenderer> renderers = const [BlocksRenderer(grid: true), OutlineRenderer()],
  Widget? leading,
  Widget? trailing,
}) async {
  final c = ModelController(model ?? appModel(), profile: model == null ? androidProfile() : null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(panelWidths.clear);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ModelEditor(
          controller: c,
          onSave: onSave,
          profiles: [androidProfile()],
          renderers: renderers,
          leading: leading,
          trailing: trailing,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await g.moveBy(const Offset(12, 12));
  await tester.pump();
  await g.moveTo(to);
  await tester.pump();
  await g.moveBy(const Offset(1, 1));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the shell: top bar, palette, layers, docked overview, status bar', (tester) async {
    final c = await pumpEditor(tester);
    expect(find.byKey(const ValueKey('editor-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette-component')), findsOneWidget);
    expect(find.byKey(const ValueKey('layer-pinner')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-overview')), findsOneWidget);
    expect(find.text('6 areas  ·  4 relationships'), findsOneWidget);
    expect(find.text('No unsaved changes'), findsOneWidget);
    // The title is edited in place from the top bar.
    await tester.tap(find.byKey(const ValueKey('editor-title')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Pay');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.model.title, 'Pay');
    expect(find.byKey(const ValueKey('editor-dirty')), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('palette drag onto an area adds a child of that kind', (tester) async {
    final c = await pumpEditor(tester);
    await drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('palette-class'))),
      tester.getCenter(find.text('Native libraries').first),
    );
    final added = c.index.children('native').single;
    expect(c.index.node(added)!.kind, 'class');
    expect(c.labelOf(added), 'Class');
    expect(c.selection, ModelElementRef.node(added));
    // It is named in place.
    expect(find.byKey(const ValueKey('rename-field')), findsOneWidget);
  });

  testWidgets('palette drag onto the canvas adds at the top level; refused kinds explain why', (tester) async {
    final c = await pumpEditor(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey('grid-canvas')));
    await drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('palette-app'))),
      Offset(canvas.center.dx, canvas.bottom - 40),
    );
    expect(c.index.children('').length, 4);
    // The profile lets an application hold no classes directly.
    await drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('palette-class'))),
      tester.getCenter(find.descendant(of: area('app'), matching: find.text('Application')).first),
    );
    expect(c.index.children('app'), ['ui', 'net']);
    expect(c.notice.value, 'An Application cannot contain a Class.');
  });

  testWidgets('palette click adds inside the selection', (tester) async {
    final c = await pumpEditor(tester);
    c.select(const ModelElementRef.node('net'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-class')));
    await tester.pumpAndSettle();
    final added = c.index.children('net').last;
    expect(added, isNot('pinner'));
    expect(c.index.node(added)!.kind, 'class');
    c.undo();
    expect(c.index.children('net'), ['pinner']);
  });

  testWidgets('the docked inspector follows the selection and edits through ops', (tester) async {
    final c = await pumpEditor(tester);
    await tester.tap(area('ui'));
    await tester.pumpAndSettle();
    expect(c.selection, const ModelElementRef.node('ui'));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('docked-inspector-node:ui')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('inspector-label')), 'Screens');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.labelOf('ui'), 'Screens');
    c.undo();
    expect(c.labelOf('ui'), 'UI layer');
    // Clearing the selection shows the model overview, which edits the model.
    await tester.tap(find.byKey(const ValueKey('inspector-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('model-overview')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('overview-subject')), 'v2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.model.subject, 'v2');
  });

  testWidgets('layers select, and drag to reparent', (tester) async {
    final c = await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('layer-server')));
    await tester.pumpAndSettle();
    expect(c.selection, const ModelElementRef.node('server'));
    await drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('layer-server'))),
      tester.getCenter(find.byKey(const ValueKey('layer-native'))),
    );
    expect(c.index.parent('server'), 'native');
  });

  testWidgets('side panels collapse and resize by their edge', (tester) async {
    await pumpEditor(tester);
    final left = find.byKey(const ValueKey('panel-left'));
    final right = find.byKey(const ValueKey('panel-right'));
    expect(tester.getSize(left).width, 264);
    await drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('panel-edge-left'))),
      tester.getCenter(find.byKey(const ValueKey('panel-edge-left'))) + const Offset(48, 0),
    );
    expect(tester.getSize(left).width, greaterThan(300));
    await tester.tap(find.byKey(const ValueKey('toggle-left-panel')));
    await tester.pumpAndSettle();
    expect(tester.getSize(left).width, 0);
    await tester.tap(find.byKey(const ValueKey('toggle-right-panel')));
    await tester.pumpAndSettle();
    expect(tester.getSize(right).width, 0);
    // Reopened, the left panel keeps the width it was dragged to.
    await tester.tap(find.byKey(const ValueKey('toggle-left-panel')));
    await tester.pumpAndSettle();
    expect(tester.getSize(left).width, greaterThan(300));
  });

  testWidgets('the narrow layout uses drawers', (tester) async {
    final c = await pumpEditor(tester, size: const Size(820, 760));
    expect(find.byKey(const ValueKey('panel-left')), findsNothing);
    final drawer = find.byKey(const ValueKey('drawer-left'));
    expect(tester.getRect(drawer).right, lessThanOrEqualTo(0));
    await tester.tap(find.byKey(const ValueKey('toggle-left-panel')));
    await tester.pumpAndSettle();
    expect(tester.getRect(drawer).left, 0);
    await tester.tapAt(const Offset(800, 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(drawer).right, lessThanOrEqualTo(0));
    // Inspecting opens the inspector drawer.
    await tester.tap(area('ui'));
    await tester.pumpAndSettle();
    expect(c.selection, const ModelElementRef.node('ui'));
    expect(tester.getRect(find.byKey(const ValueKey('drawer-right'))).right, 820);
  });

  testWidgets('the top bar never wraps: narrow widths fold search and actions into menus', (tester) async {
    await pumpEditor(tester, size: const Size(820, 760));
    expect(find.byKey(const ValueKey('toggle-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-search')), findsNothing);
    final bar = tester.getRect(find.byKey(const ValueKey('editor-title')));
    expect(bar.top, lessThan(48));
  });

  testWidgets('empty model: a polished empty state that adds a first area', (tester) async {
    final c = await pumpEditor(tester, model: Model.empty('Blank', 'nothing'));
    expect(find.byKey(const ValueKey('empty-board')), findsOneWidget);
    expect(find.text('Start your model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty-add-area')));
    await tester.pumpAndSettle();
    expect(c.model.nodes, hasLength(1));
  });

  testWidgets('save from the top bar and Ctrl+S', (tester) async {
    var saved = 0;
    final c = await pumpEditor(tester, onSave: (ops, result) async => saved++);
    c.rename(const ModelElementRef.node('ui'), 'Screens');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-save')));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(c.dirty, isFalse);
  });

  testWidgets('the top bar: left group at the start, switcher on the centre, right group flush', (tester) async {
    await pumpEditor(tester, size: const Size(1900, 1000), onSave: (ops, result) async {}, leading: const Text('File'));
    final bar = tester.getRect(find.byType(EditorTopBar));
    const padding = 8.0;
    final right = tester.getRect(find.byKey(const ValueKey('toggle-right-panel')));
    expect(bar.right - right.right, lessThanOrEqualTo(padding + 0.5));
    expect(tester.getRect(find.byKey(const ValueKey('editor-save'))).right, lessThan(right.left));
    final switcher = tester.getRect(find.byType(ViewSwitcher));
    expect(switcher.center.dx, closeTo(bar.center.dx, 0.5));
    expect(tester.getRect(find.byKey(const ValueKey('toggle-left-panel'))).left - bar.left, lessThanOrEqualTo(padding));
    // The title has room, so it is not cut short.
    final title = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('editor-title')));
    expect(title.didExceedMaxLines, isFalse);
  });

  testWidgets("the host's trailing widget ends the bar, after the inspector toggle", (tester) async {
    for (final width in [1900.0, 800.0]) {
      await pumpEditor(
        tester,
        size: Size(width, 1000),
        onSave: (ops, result) async {},
        trailing: const SizedBox.square(key: ValueKey('host-trailing'), dimension: 32),
      );
      final bar = tester.getRect(find.byType(EditorTopBar));
      final trailing = tester.getRect(find.byKey(const ValueKey('host-trailing')));
      expect(bar.right - trailing.right, lessThanOrEqualTo(8.5), reason: 'at $width');
      expect(tester.getRect(find.byKey(const ValueKey('toggle-right-panel'))).right, lessThan(trailing.left));
    }
  });

  testWidgets('a badged menu button shows its badge and opens its menu', (tester) async {
    var picked = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ModelChrome.of(context).menuButton(
                icon: Icons.account_circle,
                badge: 'AL',
                tooltip: 'Signed in as Ada',
                items: [ModelMenuItem(label: 'Sign out', onSelected: () => picked++)],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('AL'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle), findsNothing);
    await tester.tap(find.text('AL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('a long title ellipsizes before it reaches the switcher', (tester) async {
    final c = await pumpEditor(tester, size: const Size(1100, 800));
    c.tryApply([
      Op.modelSet({'title': 'A remarkably long model title that cannot possibly fit beside the view switcher'}),
    ]);
    await tester.pumpAndSettle();
    final title = tester.getRect(find.byKey(const ValueKey('editor-title')));
    final switcher = tester.getRect(find.byType(ViewSwitcher));
    expect(title.right, lessThan(switcher.left));
    expect(tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('editor-title'))).didExceedMaxLines, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the raised view segment is a rounded rectangle concentric with its track', (tester) async {
    await pumpEditor(tester, size: const Size(1400, 900));
    final t = ModelTheme.fallback();
    final segment = find.descendant(
      of: find.byKey(const ValueKey('renderer-blocks')),
      matching: find.byType(AnimatedContainer),
    );
    final box = tester.widget<AnimatedContainer>(segment).decoration! as BoxDecoration;
    final inset = trackInset + t.borderWidth;
    expect(box.borderRadius, BorderRadius.circular(t.radius - inset));
    // It fills the track's height, so its corners are not a pill's.
    final track = tester.getRect(find.byType(ViewSwitcher));
    expect(tester.getSize(segment).height, track.height - 2 * inset);
    expect(t.radius - inset, lessThan(tester.getSize(segment).height / 2));
  });

  testWidgets('icons sit on the centre of their buttons', (tester) async {
    await pumpEditor(tester);
    void centred(Finder button) {
      final icon = find.descendant(of: button, matching: find.byType(Icon)).first;
      final b = tester.getCenter(button), i = tester.getCenter(icon);
      expect((b - i).distance, lessThan(0.5), reason: '$button');
    }

    centred(find.byTooltip('Edit UI layer'));
    centred(find.byTooltip('Drag to relate UI layer to another area'));
    centred(find.byTooltip('Export'));
    centred(find.byTooltip('Inspector'));
    // The card's toolbar holds its buttons on one centre line.
    final menu = tester.getRect(find.byTooltip('Edit UI layer'));
    final relate = tester.getRect(find.byTooltip('Drag to relate UI layer to another area'));
    expect(menu.center.dy, closeTo(relate.center.dy, 0.5));
    expect(menu.height, relate.height);
  });

  testWidgets('palette drag beside a card previews the new card and places it there', (tester) async {
    final c = await pumpEditor(tester);
    final native = tester.getRect(area('native'));
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('palette-component'))),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(12, 12));
    await tester.pump();
    await g.moveTo(Offset(native.left + 5, native.center.dy - 1));
    await tester.pump();
    await g.moveTo(Offset(native.left + 6, native.center.dy));
    await tester.pump();
    final preview = find.byKey(const ValueKey('drop-preview'));
    expect(preview, findsOneWidget);
    await tester.pumpAndSettle();
    // The new card's placeholder takes the place of Native libraries,
    // which reflows (here onto the next row) to make room.
    expect(tester.getRect(preview).left, closeTo(native.left, 1));
    final moved = tester.getRect(area('native'));
    expect(moved.left > native.left || moved.top > native.top, isTrue);
    await g.up();
    await tester.pumpAndSettle();
    final added = c.index.children('').singleWhere((id) => !['app', 'native', 'server'].contains(id));
    expect(c.index.children(''), ['app', added, 'native', 'server']);
    expect(c.index.node(added)!.kind, 'component');
    expect(preview, findsNothing);
    c.undo();
    expect(c.index.children(''), ['app', 'native', 'server']);
  });

  testWidgets('outline, graph, matrix and table fill the whole board', (tester) async {
    final c = await pumpEditor(tester, renderers: allRenderers);
    for (final id in ['outline', 'graph', 'matrix', 'table']) {
      c.renderer = id;
      c.select(const ModelElementRef.node('app'));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byKey(ValueKey('renderer-view-$id')));
      final view = switch (id) {
        'outline' => find.byKey(const ValueKey('outline-app')),
        'table' => find.byKey(const ValueKey('table-row-app')),
        _ => find.byType(InteractiveViewer),
      };
      final r = tester.getRect(view);
      // Edge to edge: rows (and their highlight) span the board, and the
      // canvases take all of it, their toolbars floating over them.
      expect(r.left, closeTo(board.left, 0.5), reason: id);
      // A table wider than the board scrolls sideways past its edge.
      expect(r.right, id == 'table' ? greaterThanOrEqualTo(board.right - 0.5) : closeTo(board.right, 0.5), reason: id);
      if (id == 'graph' || id == 'matrix') {
        expect(r.top, closeTo(board.top, 0.5), reason: id);
        expect(r.bottom, closeTo(board.bottom, 0.5), reason: id);
      }
    }
  });

  testWidgets('a table narrower than the board widens its columns to fill it', (tester) async {
    final c = await pumpEditor(tester, size: const Size(1900, 1000), model: appModel(), renderers: allRenderers);
    c.renderer = 'table';
    await tester.pumpAndSettle();
    final board = tester.getRect(find.byKey(const ValueKey('renderer-view-table')));
    final row = tester.getRect(find.byKey(const ValueKey('table-row-app')));
    expect(row.left, closeTo(board.left, 0.5));
    expect(row.right, closeTo(board.right, 0.5));
  });
}
