// host.dart: the page that hosts the modeller (design §6.2,
// window.modellingHost, contract 1), as Dart sees it. A host may supply
// an account (the toolbar's sign-in) and a source (where signed-in users'
// models live). Without a host the app works with files only.

import 'dart:ui' show VoidCallback;

/// Who is signed in to the host.
typedef HostUser = ({String name, String email, String initials});

/// A model the host's source lists.
typedef HostEntry = ({String id, String title, String subject, DateTime? updatedAt});

/// The host's account: the toolbar's sign-in control.
abstract interface class HostAccount {
  /// The signed-in user, or null.
  HostUser? current();

  /// Starts signing in (the host may leave the page and come back).
  void signIn();

  Future<void> signOut();

  /// Shows the user's account page.
  void openAccount();

  /// Calls [callback] whenever who is signed in may have changed; returns
  /// the function that stops it.
  VoidCallback onChange(VoidCallback callback);
}

/// Where the host keeps signed-in users' models: whole documents, as
/// `.model.json` text. Each model's version stays inside the host, which
/// answers [HostErrorCode.conflict] when a save would overwrite a change
/// made elsewhere.
abstract interface class HostSource {
  /// What the source is called in Open and Save ("My account").
  String get label;

  Future<List<HostEntry>> list();

  /// The model's `.model.json` text.
  Future<String> read(String id);

  /// Stores [json] as model [id], or as a new model when [id] is null;
  /// answers the stored model's id.
  Future<String> save(String? id, String json, {required String title, required String subject});

  Future<void> remove(String id);
}

/// What the page hosting the modeller offers; either member may be absent.
class ModellingHost {
  const ModellingHost({this.account, this.source});

  final HostAccount? account;

  /// Used only while [account] has a signed-in user.
  final HostSource? source;
}

/// Why a host call failed: the contract's error codes.
enum HostErrorCode {
  conflict('conflict'),
  quota('quota'),
  tooLarge('too_large'),
  signedOut('signed_out'),
  unavailable('unavailable');

  const HostErrorCode(this.wire);

  /// The code as the host sends it.
  final String wire;

  /// The code named [wire]; anything unknown is [unavailable].
  static HostErrorCode of(String? wire) => values.firstWhere((c) => c.wire == wire, orElse: () => unavailable);
}

/// A host call's rejection, `{code, message}`.
class HostError implements Exception {
  const HostError(this.code, [this.message = '']);

  final HostErrorCode code;

  /// The host's own words; shown only for [HostErrorCode.unavailable].
  final String message;

  @override
  String toString() => 'HostError(${code.wire}${message.isEmpty ? '' : ': $message'})';
}

/// What went wrong with [e], for the user, in words that follow "Could
/// not save: " or "Could not open: ". [label] names the host's source.
String describeHostError(HostError e, String label) => switch (e.code) {
  HostErrorCode.conflict => 'the model was changed in another tab or on another device.',
  HostErrorCode.quota => '$label is full. Delete models you no longer need from File › Open, then save again.',
  HostErrorCode.tooLarge => 'the model is too large for $label. Export it to a file instead, from File › Export.',
  HostErrorCode.signedOut => 'you have been signed out. Sign in again, or export the model to a file.',
  HostErrorCode.unavailable =>
    '$label is not available${e.message.isEmpty ? '' : ' (${e.message})'}. Try again, or export the model to a file.',
};
