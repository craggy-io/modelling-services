import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder row(String id) => find.byKey(ValueKey('outline-$id'));

Future<ModelController> pumpOutline(WidgetTester tester, ModelController c, {Size size = const Size(1000, 900)}) async {
  c.renderer = 'outline';
  await pumpWorkspace(tester, c, size: size);
  await focusRenderer(tester, row(c.model.nodes.first.id));
  return c;
}

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool shift = false,
  bool alt = false,
  bool control = false,
}) async {
  final mods = [
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (control) LogicalKeyboardKey.controlLeft,
  ];
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(k);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists areas indented with relationships under them', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel(), readOnly: true));
    for (final id in ['app', 'ui', 'net', 'pinner', 'native', 'server']) {
      expect(row(id), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('outline-edge-e1')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Network layer')).dx,
      greaterThan(tester.getTopLeft(find.text('Application')).dx),
    );
    expect(find.text('Showing 6 of 6 areas · 4 relationships'), findsOneWidget);
    expect(find.text('Add area'), findsNothing);

    c.search = 'pinner';
    await tester.pumpAndSettle();
    expect(row('pinner'), findsOneWidget);
    expect(row('app'), findsNothing);
  });

  testWidgets('switching renderer keeps the place', (tester) async {
    final c = ModelController(appModel(), readOnly: true);
    await pumpWorkspace(tester, c);
    await tester.tap(find.byTooltip('Collapse Application'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(c.renderer, 'outline');
    expect(row('app'), findsOneWidget);
    expect(row('ui'), findsNothing);
    await tester.tap(find.text('Blocks'));
    await tester.pumpAndSettle();
    expect(find.text('2 areas collapsed'), findsOneWidget);
  });

  testWidgets('keyboard navigation and folding', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel(), readOnly: true));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(c.focused, 'app');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(c.focused, 'ui');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.focused, 'app');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(row('ui'), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(row('ui'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.space);
    expect(row('ui'), findsNothing);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.text('Area · app'), findsOneWidget);
  });

  testWidgets('Enter adds a sibling and names it', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel()));
    c.focus('ui');
    await key(tester, LogicalKeyboardKey.enter);
    final field = find.byKey(const ValueKey('rename-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Data');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.index.children('app').map(c.labelOf), ['UI layer', 'Data', 'Network layer']);
  });

  testWidgets('Tab and Shift+Tab reparent, Alt+arrows reorder', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel()));
    c.focus('net');
    await key(tester, LogicalKeyboardKey.tab);
    expect(c.index.parent('net'), 'ui');
    await key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(c.index.parent('net'), 'app');
    expect(c.index.children('app'), ['ui', 'net']);
    await key(tester, LogicalKeyboardKey.arrowUp, alt: true);
    expect(c.index.children('app'), ['net', 'ui']);
    await key(tester, LogicalKeyboardKey.arrowDown, alt: true);
    expect(c.index.children('app'), ['ui', 'net']);
    // The first child cannot indent: nothing before it.
    c.focus('ui');
    await key(tester, LogicalKeyboardKey.tab);
    expect(c.index.parent('ui'), 'app');
  });

  testWidgets('Tab into a kind the profile forbids is refused', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel(), profile: androidProfile()));
    c.focus('native');
    await key(tester, LogicalKeyboardKey.tab); // into app: a component is fine
    expect(c.index.parent('native'), 'app');
    c.setFields(const ModelElementRef.node('server'), {'kind': 'class'});
    c.focus('server');
    await key(tester, LogicalKeyboardKey.tab); // into app: a class is not allowed
    expect(c.index.parent('server'), '');
    expect(find.text('An Application cannot contain a Class.'), findsOneWidget);
  });

  testWidgets('F2 renames, Delete deletes with a confirm', (tester) async {
    final c = await pumpOutline(tester, ModelController(appModel()));
    c.focus('pinner');
    await key(tester, LogicalKeyboardKey.f2);
    await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Pinner');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.labelOf('pinner'), 'Pinner');

    c.focus('pinner');
    await key(tester, LogicalKeyboardKey.delete);
    expect(find.text('This also deletes 1 relationship.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.index.node('pinner'), isNull);
    expect(row('pinner'), findsNothing);
  });

  testWidgets('diff markers and removed ghosts', (tester) async {
    await pumpOutline(tester, ModelController(appRevision(), base: appModel(), readOnly: true));
    expect(row('server'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Area Payment server.*removed since the base')), findsOneWidget);
    expect(find.byKey(const ValueKey('outline-edge-e2')), findsOneWidget);
    expect(find.byTooltip('Added: not in the base'), findsWidgets);
  });

  testWidgets('works on a narrow screen', (tester) async {
    await pumpOutline(tester, ModelController(appModel()), size: const Size(360, 700));
    expect(tester.takeException(), isNull);
    expect(row('pinner'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-search')), findsOneWidget);
  });
}
