import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder row(String id) => find.byKey(ValueKey('table-row-$id'));
Finder editor(String id, String column) => find.byKey(ValueKey('table-edit-$id-$column'));

List<String> rowOrder(WidgetTester tester) => [
  for (final w in tester.widgetList<GestureDetector>(
    find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('table-row-'),
    ),
  ))
    (w.key as ValueKey<String>).value.substring('table-row-'.length),
];

void main() {
  testWidgets('areas as rows with the profile properties as columns', (tester) async {
    final c = ModelController(appModel(), renderer: 'table', readOnly: true, profile: androidProfile());
    await pumpWorkspace(tester, c, renderers: allRenderers);
    expect(rowOrder(tester), ['app', 'ui', 'net', 'pinner', 'native', 'server']);
    for (final title in ['Id', 'Label', 'Kind', 'Parent', 'Tags', 'exported', 'language']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('attack-surface'), findsOneWidget);
    // Read-only: values, no editors.
    expect(editor('ui', 'label'), findsNothing);
    expect(find.descendant(of: row('pinner'), matching: find.text('Network layer')), findsOneWidget);
  });

  testWidgets('relationships, sorting and filtering', (tester) async {
    final c = ModelController(appModel(), renderer: 'table', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tester.tap(find.byKey(const ValueKey('table-relationships')));
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['e1', 'e2', 'e3', 'e4']);
    expect(find.text('From'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('table-sort-label')));
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['e1', 'e3', 'e4', 'e2']);
    await tester.tap(find.byKey(const ValueKey('table-sort-label')));
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['e2', 'e4', 'e3', 'e1']);
    await tester.tap(find.byKey(const ValueKey('table-sort-label')));
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['e1', 'e2', 'e3', 'e4']);

    await tester.enterText(find.byKey(const ValueKey('table-filter')), 'native');
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['e3', 'e4']);
  });

  testWidgets('tapping a row selects; inspect opens the inspector', (tester) async {
    final c = ModelController(appModel(), renderer: 'table', readOnly: true);
    await pumpWorkspace(tester, c, renderers: allRenderers);
    await tester.tap(find.descendant(of: row('net'), matching: find.text('net')));
    await tester.pumpAndSettle();
    expect(c.selection, const ModelElementRef.node('net'));
    await tester.tap(find.byTooltip('Inspect Certificate pinner'));
    await tester.pumpAndSettle();
    expect(find.text('Area · pinner'), findsOneWidget);
  });

  testWidgets('inline edits are undoable', (tester) async {
    final c = ModelController(appModel(), renderer: 'table', profile: androidProfile());
    await pumpWorkspace(tester, c, renderers: allRenderers);

    await tester.enterText(find.descendant(of: editor('ui', 'label'), matching: find.byType(EditableText)), 'Screens');
    await tester.pumpAndSettle();
    expect(c.model.nodeById('ui')!.label, 'Screens');

    // Tags edit as chips here too: Enter adds one, × removes one.
    await tester.enterText(find.descendant(of: editor('net', 'tags'), matching: find.byType(EditableText)), 'a');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.model.nodeById('net')!.tags, ['attack-surface', 'a']);
    await tester.tap(find.descendant(of: editor('net', 'tags'), matching: find.byTooltip('Remove attack-surface')));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('net')!.tags, ['a']);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('net')!.tags, ['attack-surface', 'a']);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('net')!.tags, ['attack-surface']);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('ui')!.label, 'UI layer');
    expect(c.dirty, isFalse);
  });

  testWidgets('diff mode shows removed rows without editors', (tester) async {
    final c = ModelController(appRevision(), base: appModel(), renderer: 'table');
    await pumpWorkspace(tester, c, renderers: allRenderers);
    expect(row('server'), findsOneWidget);
    expect(editor('server', 'label'), findsNothing);
    expect(editor('cache', 'label'), findsOneWidget);
    expect(find.descendant(of: row('cache'), matching: find.byType(ChangeMarker)), findsOneWidget);
  });
}
