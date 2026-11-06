import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

void main() {
  testWidgets('save sends pending ops to the source and marks saved', (tester) async {
    final source = MemoryModelSource({'app': appModel()});
    final loaded = await source.read('app');
    final c = ModelController(loaded.model);
    List<Op>? sent;
    await pumpWorkspace(
      tester,
      c,
      onSave: (ops, result) async {
        sent = ops;
        await source.save(loaded, ops, result);
      },
    );
    expect(find.text('Save'), findsOneWidget);

    c.rename(const ModelElementRef.node('ui'), 'Screens');
    c.addChild('net');
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(sent!.map((o) => o.op), ['node.set', 'node.add']);
    expect(c.dirty, isFalse);
    expect(source['app'], c.model);
    expect(find.textContaining('unsaved changes'), findsNothing);
  });

  testWidgets('a failed save keeps the edits and says why', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c, onSave: (_, _) async => throw StateError('offline'));
    c.rename(const ModelElementRef.node('ui'), 'Screens');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.dirty, isTrue);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('a new revision from the host keeps the place', (tester) async {
    final c = ModelController(appModel(), readOnly: true);
    await pumpWorkspace(tester, c);
    await tester.tap(find.byTooltip('Open Network layer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'pin');
    await tester.pumpAndSettle();
    c.search = '';
    c.drillIn('net');
    c.togglePin('e3');
    final (next, _) = apply(appModel(), [
      Op.nodeSet('pinner', {'label': 'Pinner v2'}),
    ]);
    c.replace(next);
    await tester.pumpAndSettle();
    expect(find.text('Back to parent area'), findsOneWidget);
    expect(find.text('Pinner v2'), findsOneWidget);
    expect(c.isPinned('e3'), isTrue);
  });

  testWidgets('export copies Mermaid and outline text', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = ModelController(appModel(), readOnly: true);
    await pumpWorkspace(tester, c);
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Mermaid'));
    await tester.pumpAndSettle();
    expect(copied, toMermaid(c.model));
    expect(find.text('Copied the model as Mermaid.'), findsOneWidget);

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy outline'));
    await tester.pumpAndSettle();
    expect(copied, toOutline(c.model));
  });

  testWidgets('the renderer captures as PNG', (tester) async {
    final c = ModelController(appModel(), readOnly: true);
    final hooks = ModelHooks(captureKey: GlobalKey());
    await pumpApp(
      tester,
      ModelHooksScope(
        hooks: hooks,
        child: BlocksBoard(controller: c),
      ),
    );
    final png = await tester.runAsync(() => captureBoundaryPng(hooks.captureKey!, pixelRatio: 1));
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('host theme and chrome replace the defaults', (tester) async {
    final theme = ModelTheme.fallback(Brightness.light).copyWith(areaBackground: const Color(0xFF123456), maxDots: 1);
    final c = ModelController(appModel(), readOnly: true);
    await pumpApp(tester, ModelWorkspace(controller: c, theme: theme, chrome: const _LoudChrome()));
    final root = tester.widget<Container>(find.byKey(const ValueKey('model-area-root')));
    expect((root.decoration! as BoxDecoration).color, const Color(0xFF123456));
    expect(find.text('FIND AREA'), findsOneWidget);
    // maxDots 1: one dot per area before the count link.
    expect(find.byTooltip('UI layer → shares data with → Native libraries'), findsNothing);
  });

  testWidgets('saved views from the toolbar of the controller', (tester) async {
    final c = ModelController(appModel());
    await pumpWorkspace(tester, c);
    c.applyView(c.model.views.single);
    await tester.pumpAndSettle();
    expect(find.text('1 area collapsed'), findsOneWidget);
  });

  test('MemoryModelSource round trip', () async {
    final source = MemoryModelSource({'app': appModel()}, {'app': appModel()});
    expect(
      (await source.list()).single,
      const ModelSummary(id: 'app', title: 'Payment app', subject: 'com.example.pay 4.2.1'),
    );
    final loaded = await source.read('app');
    expect(loaded.editable, isTrue);
    expect(loaded.base, appModel());
    final c = ModelController(loaded.model, base: loaded.base);
    c.addRelationship('ui', 'server', label: 'pays');
    c.saveView('mine');
    final summary = await source.save(loaded, c.pendingOps, c.model);
    expect(summary.id, 'app');
    expect(source['app'], c.model);
    expect((await source.read('app')).model.views.map((v) => v.id), ['overview', 'mine']);
    source.readOnly.add('app');
    expect((await source.read('app')).editable, isFalse);
    expect(() => source.save(loaded, const [], c.model), throwsStateError);
    expect(() => source.read('nope'), throwsStateError);
  });

  test('FileModelSource reads models, Mermaid and outlines by extension', () async {
    final files = FileModelSource();
    final doc = files.load('a/app.model.json', appModel().encode());
    expect(doc.model, appModel());
    final mmd = files.load('flow.mmd', toMermaid(appModel()));
    expect(mmd.model.nodes.map((n) => n.label), contains('Network layer'));
    final md = files.load('notes.md', toOutline(appModel()));
    expect(md.model.edges, hasLength(4));
    expect((await files.list()).map((s) => s.id), ['notes.md', 'flow.mmd', 'a/app.model.json']);
    expect((await files.read('flow.mmd')).model, mmd.model);
  });
}

class _LoudChrome extends MaterialModelChrome {
  const _LoudChrome();

  @override
  Widget searchField({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    String hint = 'Search',
    ValueChanged<String>? onChanged,
  }) => Column(
    children: [
      Text(hint.toUpperCase()),
      super.searchField(key: key, controller: controller, focusNode: focusNode, hint: hint, onChanged: onChanged),
    ],
  );
}
