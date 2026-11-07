// craggy_account_web.dart: window.craggyAccount, which the website's
// account.js puts on every craggy.io page.

import 'dart:js_interop';
import 'dart:ui' show VoidCallback;

import 'package:web/web.dart' as web;

typedef CraggyUser = ({String name, String email, String initials});

@JS('craggyAccount')
external _Account? get _account;

extension type _Account._(JSObject _) implements JSObject {
  external _User? current();
  external String signInUrl([String returnTo]);
  external JSPromise<JSAny?> signOut();
  external String get site;
}

extension type _User._(JSObject _) implements JSObject {
  external String get name;
  external String get email;
  external String get initials;
}

bool craggyAccountAvailable() => _account != null;

CraggyUser? craggyUser() {
  final u = _account?.current();
  return u == null ? null : (name: u.name, email: u.email, initials: u.initials);
}

/// account.js fires "craggy-account-change" once it has loaded (which may
/// be after the app starts), on sign-out, and when another tab signed in
/// or out.
VoidCallback watchCraggyAccount(VoidCallback onChange) {
  final listener = ((web.Event _) => onChange()).toJS;
  web.document.addEventListener('craggy-account-change', listener);
  return () => web.document.removeEventListener('craggy-account-change', listener);
}

void craggySignIn() {
  final account = _account;
  if (account != null) web.window.location.assign(account.signInUrl(web.window.location.href));
}

void openCraggyAccountPage() {
  final account = _account;
  if (account != null) web.window.open('${account.site}/account/', '_blank', 'noopener');
}

/// The session is gone from this browser even when the server's sign-out
/// fails, so that failure isn't the user's to handle.
Future<void> craggySignOut() async {
  try {
    await _account?.signOut().toDart;
  } on Object {
    // Signed out here; only the server didn't confirm it.
  }
}
