import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder area(String id) => find.byKey(ValueKey('model-area-$id'));

Future<void> menu(WidgetTester tester, String title, String item) async {
  await tester.tap(find.byTooltip('Edit $title'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> typeAndSubmit(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add an area inside another, then name it inline', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await menu(tester, 'Application', 'Add area inside');
    final added = c.selection!.id;
    expect(c.index.parent(added), 'app');
    final field = find.byKey(const ValueKey('rename-field'));
    expect(field, findsOneWidget);
    await typeAndSubmit(tester, field, 'Storage');
    expect(c.labelOf(added), 'Storage');
    expect(find.text('Storage'), findsOneWidget);
    // One step to add, one to rename.
    c.undo();
    expect(c.labelOf(added), 'New area');
  });

  testWidgets('add an area beside another', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await menu(tester, 'UI layer', 'Add area beside');
    await typeAndSubmit(tester, find.byKey(const ValueKey('rename-field')), 'Data');
    expect(c.index.children('app').map(c.labelOf), ['UI layer', 'Data', 'Network layer']);
  });

  testWidgets('add a top-level area from the root', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await tester.tap(find.byTooltip('Add area'));
    await tester.pumpAndSettle();
    await typeAndSubmit(tester, find.byKey(const ValueKey('rename-field')), 'Backend');
    expect(c.index.children('').map(c.labelOf), contains('Backend'));
  });

  testWidgets('rename by double-click, Escape cancels', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await tester.tap(find.text('UI layer'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('UI layer'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('rename-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Nope');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(c.labelOf('ui'), 'UI layer');

    await tester.tap(find.text('UI layer'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('UI layer'));
    await tester.pumpAndSettle();
    await typeAndSubmit(tester, field, 'Screens');
    expect(c.labelOf('ui'), 'Screens');
  });

  testWidgets('F2 renames and Delete deletes the focused area', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await focusRenderer(tester, area('root'));
    c.focus('server');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await typeAndSubmit(tester, find.byKey(const ValueKey('rename-field')), 'Bank');
    expect(c.labelOf('server'), 'Bank');

    // server has a relationship (e2), so deleting asks first.
    c.focus('server');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('Delete Bank?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.index.node('server'), isNull);
    expect(c.model.edgeById('e2'), isNull);
  });

  testWidgets('delete asks before taking nested areas and relationships', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await menu(tester, 'Network layer', 'Delete');
    expect(find.text('Delete Network layer?'), findsOneWidget);
    expect(find.text('This also deletes 1 nested area and 3 relationships.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.index.node('net'), isNotNull);

    await menu(tester, 'Network layer', 'Delete');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.index.node('net'), isNull);
    expect(c.index.node('pinner'), isNull);
    expect(area('net'), findsNothing);
    c.undo();
    await tester.pumpAndSettle();
    expect(area('pinner'), findsOneWidget);
  });

  testWidgets('drag an area onto another to reparent it', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await dragTo(
      tester,
      find.byTooltip('Drag to move Payment server into another area'),
      find.text('Native libraries'),
    );
    expect(c.index.parent('server'), 'native');
    expect(find.descendant(of: area('native'), matching: area('server')), findsOneWidget);
  });

  testWidgets('reparenting into its own contents is refused with a reason', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await dragTo(tester, find.byTooltip('Drag to move Application into another area'), find.text('Certificate pinner'));
    expect(c.index.parent('app'), '');
    expect(find.byKey(const ValueKey('model-notice')), findsOneWidget);
    expect(find.textContaining('cannot move into it'), findsOneWidget);
  });

  testWidgets('reparenting against the profile is refused with a reason', (tester) async {
    final c = ModelController(appModel(), profile: androidProfile());
    await pumpWorkspace(tester, c);
    await dragTo(tester, find.byTooltip('Drag to move Certificate pinner into another area'), find.text('Application'));
    expect(c.index.parent('pinner'), 'net');
    expect(find.text('An Application cannot contain a Class.'), findsOneWidget);
  });

  testWidgets('drag from the connection handle to draw a relationship', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await dragTo(
      tester,
      find.byTooltip('Drag to relate Payment server to another area'),
      find.text('Native libraries'),
    );
    expect(find.text('New relationship'), findsOneWidget);
    expect(find.text('Payment server → Native libraries'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('relationship-label')), 'settles with');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final e = c.model.edges.last;
    expect((e.from, e.to, e.label), ('server', 'native', 'settles with'));
    expect(find.text('Relationships · 5'), findsOneWidget);
  });

  testWidgets('a profile picks the relationship kind', (tester) async {
    final c = ModelController(appModel(), profile: androidProfile());
    await pumpWorkspace(tester, c);
    await dragTo(tester, find.byTooltip('Drag to relate Network layer to another area'), find.text('UI layer'));
    expect(find.byKey(const ValueKey('relationship-kind')), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final e = c.model.edges.last;
    expect((e.from, e.to, e.kind, e.label), ('net', 'ui', 'calls', 'calls'));
  });

  testWidgets('undo and redo from the toolbar and keyboard', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    c.rename(const ModelElementRef.node('ui'), 'Screens');
    await tester.pumpAndSettle();
    expect(find.text('Screens'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('UI layer'), findsOneWidget);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(find.text('Screens'), findsOneWidget);
    await focusRenderer(tester, area('root'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(c.labelOf('ui'), 'UI layer');
  });
}
