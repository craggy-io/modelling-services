import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modeller/src/agent_dialog.dart';
import 'package:modeller/src/model_link.dart';
import 'package:modeller/src/modeller_app.dart';
import 'package:modeller/src/samples.dart';
import 'package:modelling/modelling.dart' hide View;

/// The conformance directory: the nearest ancestor of the working directory
/// with conformance/documents.json (the app root is apps/modeller).
final Directory conformance = () {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final candidate = Directory('${dir.path}${Platform.pathSeparator}conformance');
    if (File('${candidate.path}${Platform.pathSeparator}documents.json').existsSync()) return candidate;
    if (dir.parent.path == dir.path) throw StateError('no conformance/ directory above ${Directory.current.path}');
  }
}();

String readConformance(String relative) => File('${conformance.path}/$relative').readAsStringSync();

final link = jsonDecode(readConformance('link.json')) as Map<String, Object?>;
final fragment = link['fragment']! as String;
Model fixture() => Model.decode(readConformance(link['fixture']! as String));

void main() {
  group('decodeModelFragment', () {
    test('decodes the conformance link to its fixture', () async {
      expect(await decodeModelFragment('m=$fragment'), fixture());
    });

    test('takes a leading # and other parameters', () async {
      expect(await decodeModelFragment('#m=$fragment'), fixture());
      expect(await decodeModelFragment('#view=blocks&m=$fragment&x=1'), fixture());
    });

    test('is null without an m parameter', () async {
      expect(await decodeModelFragment(''), isNull);
      expect(await decodeModelFragment('#'), isNull);
      expect(await decodeModelFragment('#/'), isNull);
      expect(await decodeModelFragment('view=blocks&x=1'), isNull);
    });

    test('refuses corrupt data', () async {
      final corrupt = throwsA(
        isA<FormatException>().having((e) => e.message, 'message', contains('the linked model is corrupt')),
      );
      await expectLater(decodeModelFragment('m='), corrupt);
      await expectLater(decodeModelFragment('m=not*base64'), corrupt);
      await expectLater(decodeModelFragment('m=${fragment.substring(0, fragment.length ~/ 2)}'), corrupt);
      await expectLater(decodeModelFragment('m=${base64Url.encode(utf8.encode('{"title": "x"}'))}'), corrupt);
    });
  });

  group('the app', () {
    Future<void> boot(WidgetTester tester, String link) async {
      final linked = (await tester.runAsync(() => readLinkedModel(link)))!;
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bundled = await tester.runAsync(() => Bundled.load(rootBundle));
      await tester.pumpWidget(ModellerApp(bundled: bundled!, linked: linked));
      await tester.pumpAndSettle();
    }

    Finder title(String text) =>
        find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('editor-title') && w.data == text);

    testWidgets('opens a linked model unsaved', (tester) async {
      await boot(tester, 'm=$fragment');
      expect(title('Payment app'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-dirty')), findsOneWidget);
      expect(find.byKey(const ValueKey('model-notice')), findsNothing);
    });

    testWidgets('reports a corrupt link and starts blank', (tester) async {
      await boot(tester, 'm=garbage');
      expect(title('Untitled model'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-dirty')), findsNothing);
      final notice = tester.widget<Text>(find.byKey(const ValueKey('model-notice')));
      expect(notice.data, startsWith('Could not open the linked model: the linked model is corrupt'));
    });

    testWidgets('shows how to connect an agent', (tester) async {
      await boot(tester, '');
      await tester.tap(find.byKey(const ValueKey('connect-agent')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-dialog')), findsOneWidget);
      expect(find.text(mcpUrl), findsOneWidget);
      expect(find.byTooltip('Copy'), findsNWidgets(agentSetups.length));
    });
  });
}
