// fake_host.dart: a ModellingHost in memory for widget tests. Its source
// stores each model's JSON re-encoded with its keys in another order, as
// a JSON database would, and keeps a version per model so a save over a
// change made "elsewhere" is a conflict.

import 'dart:convert';
import 'dart:ui' show VoidCallback;

import 'package:modeller/src/host.dart';

class FakeHost implements HostAccount, HostSource {
  FakeHost({this.user});

  HostUser? user;
  final _listeners = <VoidCallback>[];

  /// Stored JSON by id, and the version this page last saw of each.
  final stored = <String, String>{};
  final summaries = <String, ({String title, String subject})>{};
  final _version = <String, int>{}, _seen = <String, int>{};
  var _next = 1;

  /// The error the next call answers with, once.
  HostErrorCode? failNext;

  /// Every source call, by name.
  final calls = <String>[];

  ModellingHost get host => ModellingHost(account: this, source: this);

  /// Signs [next] in (or out, for null) and tells the app.
  void switchUser(HostUser? next) {
    user = next;
    for (final l in [..._listeners]) {
      l();
    }
  }

  /// Changes [id] as another tab would.
  void editElsewhere(String id, String json) {
    stored[id] = _reorder(json);
    _version[id] = _version[id]! + 1;
  }

  void _fail() {
    final code = failNext;
    failNext = null;
    if (code != null) throw HostError(code, 'fake ${code.wire}');
    if (user == null) throw const HostError(HostErrorCode.signedOut);
  }

  /// [json] with every object's keys reversed.
  static String _reorder(String json) => jsonEncode(_reversed(jsonDecode(json)));

  static Object? _reversed(Object? v) => switch (v) {
    Map() => {for (final k in v.keys.toList().reversed) k: _reversed(v[k])},
    List() => [for (final e in v) _reversed(e)],
    _ => v,
  };

  @override
  HostUser? current() => user;

  @override
  void signIn() => switchUser((name: 'Ada', email: 'ada@example.com', initials: 'A'));

  @override
  Future<void> signOut() async => switchUser(null);

  @override
  void openAccount() {}

  @override
  VoidCallback onChange(VoidCallback callback) {
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  @override
  String get label => 'Test account';

  @override
  Future<List<HostEntry>> list() async {
    calls.add('list');
    _fail();
    return [
      for (final MapEntry(key: id, value: s) in summaries.entries)
        (id: id, title: s.title, subject: s.subject, updatedAt: DateTime(2026, 11, 7, 9, 30)),
    ];
  }

  @override
  Future<String> read(String id) async {
    calls.add('read $id');
    _fail();
    _seen[id] = _version[id]!;
    return stored[id]!;
  }

  @override
  Future<String> save(String? id, String json, {required String title, required String subject}) async {
    calls.add('save ${id ?? 'new'}');
    _fail();
    if (id != null && _seen[id] != _version[id]) throw const HostError(HostErrorCode.conflict);
    final key = id ?? 'm${_next++}';
    stored[key] = _reorder(json);
    summaries[key] = (title: title, subject: subject);
    _version[key] = _seen[key] = (_version[key] ?? 0) + 1;
    return key;
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove $id');
    _fail();
    stored.remove(id);
    summaries.remove(id);
  }
}
