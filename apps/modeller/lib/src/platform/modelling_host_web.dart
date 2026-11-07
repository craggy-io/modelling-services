// modelling_host_web.dart: window.modellingHost (design §6.2), which the
// page may define before the app starts. Only contract 1 is used; each
// member is optional. Rejections `{code, message}` become HostErrors.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show VoidCallback;

import '../host.dart';

@JS('modellingHost')
external _Host? get _host;

extension type _Host._(JSObject _) implements JSObject {
  external JSAny? get contract;
  external _Account? get account;
  external _Source? get source;
}

extension type _Account._(JSObject _) implements JSObject {
  external _User? current();
  external void signIn();
  external JSPromise<JSAny?>? signOut();
  external void openAccount();
  external JSFunction onChange(JSFunction callback);
}

extension type _User._(JSObject _) implements JSObject {
  external String? get name;
  external String? get email;
  external String? get initials;
}

extension type _Source._(JSObject _) implements JSObject {
  external String? get label;
  external JSPromise<JSArray<_Entry>> list();
  external JSPromise<_Read> read(String id);
  external JSPromise<_Saved> save(String? id, String json, _Summary summary);
  external JSPromise<JSAny?> remove(String id);
}

extension type _Entry._(JSObject _) implements JSObject {
  external String get id;
  external String? get title;
  external String? get subject;
  external String? get updatedAt;
}

extension type _Read._(JSObject _) implements JSObject {
  external String get json;
}

extension type _Saved._(JSObject _) implements JSObject {
  external String get id;
}

extension type _Summary._(JSObject _) implements JSObject {
  external factory _Summary({String title, String subject});
}

ModellingHost? findModellingHost() {
  final host = _host;
  final contract = host?.contract;
  if (host == null || !contract.isA<JSNumber>() || (contract as JSNumber).toDartDouble != 1) return null;
  final account = host.account, source = host.source;
  return ModellingHost(
    account: account == null ? null : _JsAccount(account),
    source: source == null ? null : _JsSource(source),
  );
}

/// Runs a host call, turning a throw or a rejection into a [HostError].
Future<T> _call<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on Object catch (e) {
    throw _hostError(e);
  }
}

HostError _hostError(Object e) {
  try {
    final o = e as JSObject;
    final code = o['code'], message = o['message'];
    return HostError(
      HostErrorCode.of(code.isA<JSString>() ? (code as JSString).toDart : null),
      message.isA<JSString>() ? (message as JSString).toDart : '',
    );
  } on Object {
    return HostError(HostErrorCode.unavailable, '$e');
  }
}

class _JsAccount implements HostAccount {
  _JsAccount(this._js);

  final _Account _js;

  @override
  HostUser? current() {
    final u = _js.current();
    return u == null ? null : (name: u.name ?? '', email: u.email ?? '', initials: u.initials ?? '');
  }

  @override
  void signIn() => _js.signIn();

  /// The session is gone from this page even when the host's sign-out
  /// fails, so that failure isn't the user's to handle.
  @override
  Future<void> signOut() async {
    try {
      await _js.signOut()?.toDart;
    } on Object {
      // Signed out here; only the host didn't confirm it.
    }
  }

  @override
  void openAccount() => _js.openAccount();

  @override
  VoidCallback onChange(VoidCallback callback) {
    final unsubscribe = _js.onChange(callback.toJS);
    return () => unsubscribe.callAsFunction();
  }
}

class _JsSource implements HostSource {
  _JsSource(this._js);

  final _Source _js;

  @override
  String get label => _js.label ?? 'Account';

  @override
  Future<List<HostEntry>> list() => _call(() async {
    final entries = (await _js.list().toDart).toDart;
    return [
      for (final e in entries)
        (
          id: e.id,
          title: e.title ?? '',
          subject: e.subject ?? '',
          updatedAt: DateTime.tryParse(e.updatedAt ?? '')?.toLocal(),
        ),
    ];
  });

  @override
  Future<String> read(String id) => _call(() async => (await _js.read(id).toDart).json);

  @override
  Future<String> save(String? id, String json, {required String title, required String subject}) =>
      _call(() async => (await _js.save(id, json, _Summary(title: title, subject: subject)).toDart).id);

  @override
  Future<void> remove(String id) => _call(() => _js.remove(id).toDart);
}
