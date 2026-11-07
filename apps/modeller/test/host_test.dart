import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modeller/src/host.dart';
import 'package:modeller/src/host_model_source.dart';
import 'package:modeller/src/samples.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart' show ModelSummary;

import 'fake_host.dart';
import 'harness.dart';

const ada = (name: 'Ada', email: 'ada@example.com', initials: 'A');

final openDialog = find.byKey(const ValueKey('account-open-dialog'));

String? notice(WidgetTester tester) =>
    tester.widgetList<Text>(find.byKey(const ValueKey('model-notice'))).map((t) => t.data).firstOrNull;

Future<void> fileMenu(WidgetTester tester, String item) async {
  await tester.tap(find.text('File'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('menu-$item')));
  await tester.pumpAndSettle();
}

/// A signed-in fake host holding [models] as m1, m2, ...
FakeHost signedIn([List<Model> models = const []]) {
  final host = FakeHost(user: ada);
  for (final m in models) {
    host.save(null, m.encode(), title: m.title, subject: m.subject);
  }
  host.calls.clear();
  return host;
}

Model named(String title) => Model.empty(title, 'About $title');

void main() {
  testWidgets('without a host there is no account control and Open uses files', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
    expect(find.byKey(const ValueKey('account-menu')), findsNothing);
    await fileMenu(tester, 'Open…');
    expect(openDialog, findsNothing);
  });

  testWidgets('signed out, the host only offers sign-in; models stay in files', (tester) async {
    final host = FakeHost();
    await boot(tester, host: host.host);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    await fileMenu(tester, 'Open…');
    expect(openDialog, findsNothing);
    await fileMenu(tester, 'Save');
    expect(host.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('account-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-menu')), findsOneWidget);
    await fileMenu(tester, 'Open…');
    expect(openDialog, findsOneWidget);
  });

  testWidgets('signed in, Save writes to the account and Save as makes a new model', (tester) async {
    final host = signedIn();
    await boot(tester, host: host.host);
    await menu(tester, ['File', 'New from template', 'System context']);

    await fileMenu(tester, 'Save');
    expect(host.calls, ['save new']);
    expect(host.summaries['m1']?.title, 'System context');
    expect(notice(tester), 'Saved to Test account.');

    await fileMenu(tester, 'Save');
    expect(host.calls.last, 'save m1');
    await fileMenu(tester, 'Save as…');
    expect(host.calls.last, 'save new');
    expect(host.stored.keys, ['m1', 'm2']);
  });

  testWidgets('Open lists the account models first, deletes one and opens another', (tester) async {
    final host = signedIn([named('Shop'), named('Bank')]);
    await boot(tester, host: host.host);
    await fileMenu(tester, 'Open…');
    expect(find.text('Open from Test account'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-model-m1')), findsOneWidget);
    expect(find.text('About Bank · Saved 2026-11-07 09:30'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-file')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-delete-m2')));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Bank"?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(host.calls, contains('remove m2'));
    expect(find.byKey(const ValueKey('account-model-m2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('account-model-m1')));
    await tester.pumpAndSettle();
    expect(openDialog, findsNothing);
    expect(title('Shop'), findsOneWidget);

    // Saving the opened model overwrites it.
    await fileMenu(tester, 'Save');
    expect(host.calls.last, 'save m1');
  });

  for (final (choice, expectTitle, expectCall) in [
    ('Save as a copy', 'Shop', 'save new'),
    ('Reload', 'Shop, edited elsewhere', 'read m1'),
  ]) {
    testWidgets('a conflict offers "$choice"', (tester) async {
      final host = signedIn([named('Shop')]);
      await boot(tester, host: host.host);
      await fileMenu(tester, 'Open…');
      await tester.tap(find.byKey(const ValueKey('account-model-m1')));
      await tester.pumpAndSettle();
      host.editElsewhere('m1', named('Shop, edited elsewhere').encode());

      await fileMenu(tester, 'Save');
      expect(find.byKey(const ValueKey('conflict-dialog')), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(host.calls.last, expectCall);
      expect(title(expectTitle), findsOneWidget);
      if (choice == 'Save as a copy') expect(host.summaries['m2']?.title, 'Shop');
    });
  }

  testWidgets('cancelling a conflict leaves the model unsaved and says why', (tester) async {
    final host = signedIn([named('Shop')]);
    await boot(tester, host: host.host);
    await fileMenu(tester, 'Open…');
    await tester.tap(find.byKey(const ValueKey('account-model-m1')));
    await tester.pumpAndSettle();
    host.editElsewhere('m1', named('Other').encode());
    await fileMenu(tester, 'Save');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(notice(tester), contains('changed in another tab'));
    expect(host.summaries['m1']?.title, 'Shop');
  });

  for (final (code, words) in [
    (HostErrorCode.quota, 'Test account is full. Delete models you no longer need from File › Open'),
    (HostErrorCode.tooLarge, 'too large for Test account. Export it to a file'),
    (HostErrorCode.signedOut, 'you have been signed out. Sign in again'),
    (HostErrorCode.unavailable, 'Test account is not available (fake unavailable)'),
  ]) {
    testWidgets('a ${code.wire} error on save explains itself', (tester) async {
      final host = signedIn();
      await boot(tester, host: host.host);
      host.failNext = code;
      await fileMenu(tester, 'Save');
      expect(notice(tester), allOf(startsWith('Could not save: '), contains(words)));
      expect(host.stored, isEmpty);
    });
  }

  testWidgets('a failed list shows in the Open dialog', (tester) async {
    final host = signedIn()..failNext = HostErrorCode.unavailable;
    await boot(tester, host: host.host);
    await fileMenu(tester, 'Open…');
    expect(find.byKey(const ValueKey('account-open-error')), findsOneWidget);
  });

  testWidgets('signing out falls back to files', (tester) async {
    final host = signedIn([named('Shop')]);
    await boot(tester, host: host.host);
    host.switchUser(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    await fileMenu(tester, 'Open…');
    expect(openDialog, findsNothing);
    expect(host.calls, isEmpty);
  });

  test('JSON the host returns loads to the model that was saved', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bundled = await Bundled.load(rootBundle);
    final host = FakeHost(user: ada);
    final source = HostModelSource(host);
    for (final model in bundled.templates.values) {
      final saved = await source.saveAs(model);
      // The fake stores the JSON reordered, as a JSON database would.
      expect(host.stored[saved.id], isNot(model.encode()));
      expect(saved, ModelSummary.of(saved.id, model));
      final read = await source.read(saved.id);
      expect(read.model, model, reason: model.title);
      expect(read.summary, saved);
    }
  });
}
