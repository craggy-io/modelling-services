// Run in a browser: flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:modeller/src/host.dart';
import 'package:modeller/src/platform/modelling_host.dart';

/// Defines window.modellingHost as a page would, in plain JavaScript.
void page(String script) => globalContext.callMethod('eval'.toJS, script.toJS);

const source = '''
  source: {
    label: 'Test account',
    saved: null,
    list: () => Promise.resolve([{id: 'a', title: 'Shop', subject: 'S', updatedAt: '2026-11-07T09:30:00Z'}, {id: 'b'}]),
    read: (id) => Promise.resolve({id, json: '{"x":1}'}),
    save(id, json, summary) {
      this.saved = [id, json, summary.title, summary.subject];
      return id === 'full' ? Promise.reject({code: 'quota', message: 'over'}) : Promise.resolve({id: id ?? 'new', title: summary.title, subject: summary.subject});
    },
    remove: (id) => Promise.reject(new Error('boom')),
  },''';

void main() {
  tearDown(() => page('delete window.modellingHost'));

  test('no host, or another contract, means files only', () {
    expect(findModellingHost(), isNull);
    page('window.modellingHost = {contract: 2, $source}');
    expect(findModellingHost(), isNull);
    page('window.modellingHost = {contract: "1", $source}');
    expect(findModellingHost(), isNull);
  });

  test('every member is optional', () {
    page('window.modellingHost = {contract: 1}');
    final host = findModellingHost()!;
    expect(host.account, isNull);
    expect(host.source, isNull);
  });

  test('the account: current user, and change events until unsubscribed', () {
    page('''window.modellingHost = {contract: 1, account: {
      user: null, listeners: [],
      current() { return this.user; },
      signIn() { this.user = {name: 'Ada', email: 'ada@example.com', initials: 'A'}; this.listeners.forEach(f => f()); },
      signOut() { return Promise.reject(new Error('offline')); },
      openAccount() {},
      onChange(f) { this.listeners.push(f); return () => { this.listeners = this.listeners.filter(g => g !== f); }; },
    }}''');
    final account = findModellingHost()!.account!;
    expect(account.current(), isNull);
    var changes = 0;
    final stop = account.onChange(() => changes++);
    account.signIn();
    expect(account.current(), (name: 'Ada', email: 'ada@example.com', initials: 'A'));
    expect(changes, 1);
    stop();
    account.signIn();
    expect(changes, 1);
    // A failed sign-out is not the user's problem.
    expect(account.signOut(), completes);
  });

  test('the source: list, read, save with its summary, and rejections as HostErrors', () async {
    page('window.modellingHost = {contract: 1, $source}');
    final s = findModellingHost()!.source!;
    expect(s.label, 'Test account');
    final entries = await s.list();
    expect(entries.first, (
      id: 'a',
      title: 'Shop',
      subject: 'S',
      updatedAt: DateTime.utc(2026, 11, 7, 9, 30).toLocal(),
    ));
    expect(entries.last, (id: 'b', title: '', subject: '', updatedAt: null));
    expect(await s.read('a'), '{"x":1}');
    expect(await s.save(null, '{}', title: 'T', subject: 'U'), 'new');
    final saved = (globalContext['modellingHost'] as JSObject)['source'] as JSObject;
    expect((saved['saved'] as JSArray).toDart.map((v) => v?.dartify()), [null, '{}', 'T', 'U']);
    await expectLater(
      s.save('full', '{}', title: 'T', subject: 'U'),
      throwsA(
        isA<HostError>().having((e) => e.code, 'code', HostErrorCode.quota).having((e) => e.message, 'message', 'over'),
      ),
    );
    await expectLater(
      s.remove('a'),
      throwsA(
        isA<HostError>()
            .having((e) => e.code, 'code', HostErrorCode.unavailable)
            .having((e) => e.message, 'message', 'boom'),
      ),
    );
  });
}
