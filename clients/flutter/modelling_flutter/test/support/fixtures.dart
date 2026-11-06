// Shared fixtures and pump helpers for the widget tests.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

const _fixtures = '../../../conformance/fixtures';

/// conformance/fixtures/app.json.
Model appModel() => Model.decode(File('$_fixtures/app.json').readAsStringSync());

/// conformance/fixtures/android-profile.json.
Profile androidProfile() => Profile.decode(File('$_fixtures/android-profile.json').readAsStringSync());

/// A revision of [appModel] to compare against it: "server" (and e2 with
/// it) removed, "ui" relabelled, "cache" added inside "app".
Model appRevision() {
  final (m, _) = apply(appModel(), [
    Op.nodeRemove('server', cascade: true),
    Op.nodeSet('ui', {'label': 'Screens'}),
    Op.nodeAdd(Node(id: 'cache', label: 'Cache', parent: 'app', kind: 'component')),
  ]);
  return m;
}

/// [count] top-level areas, for paging.
Model wideModel(int count) => Model(
  title: 'Wide',
  subject: 'many areas',
  nodes: [for (var i = 0; i < count; i++) Node(id: 'n$i', label: 'Area $i')],
);

/// Pumps [child] in a large window under a MaterialApp.
Future<void> pumpApp(WidgetTester tester, Widget child, {Size size = const Size(1400, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps a workspace over [c].
Future<void> pumpWorkspace(
  WidgetTester tester,
  ModelController c, {
  ModelSaveHook? onSave,
  ModelEvidenceHook? onEvidence,
  ModelAttachHook? onAttachEvidence,
  ModelLinkHook? onOpenLink,
  List<ModelRenderer> renderers = const [BlocksRenderer(), OutlineRenderer()],
  Size size = const Size(1400, 1200),
}) => pumpApp(
  tester,
  ModelWorkspace(
    controller: c,
    renderers: renderers,
    onSave: onSave,
    onEvidence: onEvidence,
    onAttachEvidence: onAttachEvidence,
    onOpenLink: onOpenLink,
  ),
  size: size,
);

/// Drags from [from] to [to] with a mouse, in steps so drag targets see it.
Future<void> dragTo(WidgetTester tester, Finder from, Finder to) async {
  final g = await tester.startGesture(tester.getCenter(from), kind: PointerDeviceKind.mouse);
  await tester.pump();
  await g.moveBy(const Offset(12, 12));
  await tester.pump();
  await g.moveTo(tester.getCenter(to));
  await tester.pump();
  await g.moveBy(const Offset(1, 1));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

/// Every renderer the package ships.
const allRenderers = [BlocksRenderer(), OutlineRenderer(), GraphRenderer(), MatrixRenderer(), TableRenderer()];

/// Taps [f] and waits out the double-tap timeout, so a single tap lands.
Future<void> tapOnce(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

/// Gives keyboard focus to the renderer that contains [inside].
Future<void> focusRenderer(WidgetTester tester, Finder inside) async {
  Focus.of(tester.element(inside)).requestFocus();
  await tester.pump();
}
