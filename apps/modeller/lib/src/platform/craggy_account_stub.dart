// craggy_account_stub.dart: desktop has no craggy.io sign-in.

import 'dart:ui' show VoidCallback;

/// Who is signed in to craggy.io.
typedef CraggyUser = ({String name, String email, String initials});

/// Whether this page has the craggy.io sign-in (it doesn't off the web).
bool craggyAccountAvailable() => false;

/// The signed-in user, or null.
CraggyUser? craggyUser() => null;

/// Calls [onChange] whenever who is signed in may have changed; returns
/// the function that stops it.
VoidCallback watchCraggyAccount(VoidCallback onChange) => () {};

/// Goes to the craggy.io sign-in page, which comes back here.
void craggySignIn() {}

/// Opens the craggy.io account page in a new tab.
void openCraggyAccountPage() {}

/// Signs out of every craggy.io site.
Future<void> craggySignOut() async {}
