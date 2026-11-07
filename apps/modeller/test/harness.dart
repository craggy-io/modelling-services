// harness.dart: booting the modeller in widget tests, and finding its
// title, dirty marker, counts and status notice.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modeller/src/host.dart';
import 'package:modeller/src/modeller_app.dart';
import 'package:modeller/src/samples.dart';

Finder title(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('editor-title') && w.data == text);

final dirty = find.byKey(const ValueKey('editor-dirty'));

Finder counts(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('editor-counts') && w.data == text);

/// Starts the app at a desktop size, inside [host] if given.
Future<void> boot(WidgetTester tester, {ModellingHost? host}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bundled = await tester.runAsync(() => Bundled.load(rootBundle));
  await tester.pumpWidget(ModellerApp(bundled: bundled!, host: host));
  await tester.pumpAndSettle();
}

/// Taps each label in [path] in turn (a menu, then its items).
Future<void> menu(WidgetTester tester, List<String> path) async {
  for (final item in path) {
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }
}
