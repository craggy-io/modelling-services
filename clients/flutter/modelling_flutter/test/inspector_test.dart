import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

final tagsInput = find.byKey(const ValueKey('tags-input'));

Future<void> openInspector(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump(kDoubleTapTimeout); // edit mode also listens for a double-click
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String option) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typed property editors follow the profile', (tester) async {
    final c = ModelController(appModel(), profile: androidProfile());
    await pumpWorkspace(tester, c);
    await openInspector(tester, 'Network layer');

    expect(inDialog(find.byKey(const ValueKey('prop-language'))), findsOneWidget);
    expect(inDialog(find.byKey(const ValueKey('prop-exported'))), findsOneWidget);

    await choose(tester, 'prop-language', 'java');
    expect(c.model.nodeById('net')!.properties['language'], 'java');

    await choose(tester, 'prop-exported', 'true');
    expect(c.model.nodeById('net')!.properties['exported'], true);

    await choose(tester, 'prop-exported', '(not set)');
    expect(c.model.nodeById('net')!.properties.containsKey('exported'), isFalse);

    await choose(tester, 'inspector-kind', 'Class');
    expect(c.model.nodeById('net')!.kind, 'class');
  });

  testWidgets('free properties: add, edit as typed, remove', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await openInspector(tester, 'Payment server');

    await tester.enterText(inDialog(find.byKey(const ValueKey('new-property-key'))), 'port');
    await tester.enterText(inDialog(find.byKey(const ValueKey('new-property-value'))), '443');
    await tester.tap(find.byTooltip('Add property'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('server')!.properties['port'], 443);

    await tester.enterText(inDialog(find.byKey(const ValueKey('prop-port'))), 'x');
    await tester.pumpAndSettle();
    expect(find.text('Enter a number'), findsOneWidget);
    expect(c.model.nodeById('server')!.properties['port'], 443);
    await tester.enterText(inDialog(find.byKey(const ValueKey('prop-port'))), '8443');
    await tester.pumpAndSettle();
    expect(c.model.nodeById('server')!.properties['port'], 8443);

    await tester.ensureVisible(find.byTooltip('Remove port'));
    await tester.tap(find.byTooltip('Remove port'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('server')!.properties, isEmpty);
  });

  testWidgets('label, notes and tags edit through undoable ops', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await openInspector(tester, 'UI layer');
    final label = inDialog(find.byKey(const ValueKey('inspector-label')));
    await tester.enterText(label, 'S');
    await tester.enterText(label, 'Screens');
    await tester.pump();
    expect(c.labelOf('ui'), 'Screens');
    await tester.enterText(label, '');
    await tester.pump();
    expect(find.text('A label cannot be blank'), findsOneWidget);
    expect(c.labelOf('ui'), 'Screens');

    await tester.enterText(inDialog(find.byKey(const ValueKey('inspector-notes'))), 'Compose UI.');
    // A comma turns the text so far into a tag.
    await tester.enterText(inDialog(tagsInput), 'ui, entry');
    await tester.pump();
    expect(c.model.nodeById('ui')!.tags, ['ui']);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final n = c.model.nodeById('ui')!;
    expect(n.notes, 'Compose UI.');
    expect(n.tags, ['ui', 'entry']);

    // Each tag was one step, the notes one, and typing the label one.
    c.undo();
    c.undo();
    expect(c.model.nodeById('ui')!.tags, isEmpty);
    c.undo();
    expect(c.model.nodeById('ui')!.notes, isEmpty);
    expect(c.labelOf('ui'), 'Screens');
    c.undo();
    expect(c.labelOf('ui'), 'UI layer');
  });

  testWidgets('tags: Enter makes a chip, × and Backspace remove, duplicates are ignored, all undoable', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    await openInspector(tester, 'Network layer');
    expect(inDialog(find.byKey(const ValueKey('tag-attack-surface'))), findsOneWidget);

    await tester.enterText(inDialog(tagsInput), ' tls ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.model.nodeById('net')!.tags, ['attack-surface', 'tls']);
    expect(inDialog(find.byKey(const ValueKey('tag-tls'))), findsOneWidget);
    // The input is cleared and keeps focus for the next tag.
    expect(tester.widget<TextField>(inDialog(tagsInput)).controller!.text, isEmpty);
    expect(tester.widget<TextField>(inDialog(tagsInput)).focusNode!.hasFocus, isTrue);

    // A duplicate changes nothing.
    await tester.enterText(inDialog(tagsInput), 'tls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.model.nodeById('net')!.tags, ['attack-surface', 'tls']);

    // Backspace in the empty input removes the last tag.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.model.nodeById('net')!.tags, ['attack-surface']);

    // The chip's × removes it.
    await tester.tap(inDialog(find.byTooltip('Remove attack-surface')));
    await tester.pump();
    expect(c.model.nodeById('net')!.tags, isEmpty);
    expect(inDialog(find.byKey(const ValueKey('tag-attack-surface'))), findsNothing);

    c.undo();
    expect(c.model.nodeById('net')!.tags, ['attack-surface']);
    c.undo();
    expect(c.model.nodeById('net')!.tags, ['attack-surface', 'tls']);
    c.undo();
    expect(c.model.nodeById('net')!.tags, ['attack-surface']);
  });

  testWidgets('evidence: open, remove, attach through the host', (tester) async {
    ModelElementRef? attachTo;
    final c = ModelController(appModel());
    await pumpWorkspace(
      tester,
      c,
      onEvidence: (_) {},
      onAttachEvidence: (ref) {
        attachTo = ref;
        c.attachEvidence(ref, [
          const Evidence(
            caption: 'Proxy log',
            ref: Ref(scheme: 'url', id: 'https://x.test/log'),
          ),
        ]);
      },
    );
    await openInspector(tester, 'Network layer');
    await tester.ensureVisible(find.byTooltip('Remove evidence Pinner config'));
    await tester.tap(find.byTooltip('Remove evidence Pinner config'));
    await tester.pumpAndSettle();
    expect(c.model.nodeById('net')!.evidence, isEmpty);
    expect(inDialog(find.text('No evidence cited.')), findsOneWidget);

    await tester.tap(find.text('Attach evidence'));
    await tester.pumpAndSettle();
    expect(attachTo, const ModelElementRef.node('net'));
    expect(c.model.nodeById('net')!.evidence.single.caption, 'Proxy log');
  });

  testWidgets('relationship inspector edits ends, kind and direction', (tester) async {
    final c = ModelController(appModel(), profile: androidProfile());
    await pumpWorkspace(tester, c);
    await tester.tap(find.text('Relationships · 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('loads'));
    await tester.pumpAndSettle();
    expect(find.text('Certificate pinner → Native libraries'), findsWidgets);

    await choose(tester, 'inspector-kind', 'calls');
    expect(c.model.edgeById('e3')!.kind, 'calls');
    await choose(tester, 'inspector-to', 'Payment server');
    expect(c.model.edgeById('e3')!.to, 'server');
    await tester.tap(inDialog(find.text('Undirected')));
    await tester.pumpAndSettle();
    expect(c.model.edgeById('e3')!.undirected, isTrue);

    await tester.tap(find.text('Delete relationship'));
    await tester.pumpAndSettle();
    expect(c.model.edgeById('e3'), isNull);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('read-only shows values and lint, no editors', (tester) async {
    final c = ModelController(appModel(), profile: androidProfile(), readOnly: true);
    await pumpWorkspace(tester, c);
    await openInspector(tester, 'Payment server');
    expect(inDialog(find.byKey(const ValueKey('inspector-label'))), findsNothing);
    expect(find.text('Delete area'), findsNothing);
    expect(inDialog(find.text('CHECKS')), findsOneWidget);
    expect(inDialog(find.textContaining('has no kind')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await openInspector(tester, 'Network layer');
    expect(inDialog(find.text('PROPERTIES')), findsOneWidget);
    expect(inDialog(find.textContaining('kotlin', findRichText: true)), findsOneWidget);
  });
}
