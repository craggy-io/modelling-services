// export_ids.dart: unique, valid ids for names read from text, ported from
// Go export/ids.go.

import 'validate.dart';

/// Turns names read from text into unique, valid model ids.
class ImportIds {
  final _nodes = <String, String>{}; // raw name -> id
  final _used = <String>{};

  /// Edge ids already taken.
  final edges = <String>{};

  /// The id for a raw node name: the name without an "n_" prefix when that
  /// is a valid id, else its slug; the same raw name always maps to the same
  /// id.
  String node(String raw) {
    final known = _nodes[raw];
    if (known != null) return known;
    var id = raw.startsWith('n_') ? raw.substring(2) : raw;
    if (!validId(id)) id = slug(id);
    id = _unique(id, _used);
    _nodes[raw] = id;
    return id;
  }

  /// A new unique node id slugged from [label].
  String fresh(String label) => _unique(slug(label), _used);

  /// Reserves an explicit node id; false if it is taken or invalid.
  bool claim(String id) {
    if (!validId(id) || !_used.add(id)) return false;
    _nodes[id] = id;
    return true;
  }

  /// A new unique edge id `<from>--<to>`.
  String edge(String from, String to) => _unique(_cut('$from--$to'), edges);
}

String _unique(String id, Set<String> used) {
  var out = id;
  for (var n = 2; used.contains(out); n++) {
    final suffix = '-$n';
    final keep = id.length < 64 - suffix.length ? id.length : 64 - suffix.length;
    out = _cut(id.substring(0, keep)) + suffix;
  }
  used.add(out);
  return out;
}

/// [s] lower-cased, with every run of characters other than a-z and 0-9
/// turned into "-", trimmed of "-" and cut to 64 characters; "node" when
/// nothing is left.
String slug(String s) {
  final b = StringBuffer();
  var dash = false;
  for (final r in s.toLowerCase().runes) {
    if ((r >= 0x61 && r <= 0x7a) || (r >= 0x30 && r <= 0x39)) {
      b.writeCharCode(r);
      dash = false;
    } else if (!dash && b.isNotEmpty) {
      b.write('-');
      dash = true;
    }
  }
  final out = _cut(b.toString().replaceFirst(RegExp(r'-+$'), ''));
  return out == '' ? 'node' : out;
}

String _cut(String s) => (s.length > 64 ? s.substring(0, 64) : s).replaceFirst(RegExp(r'[-_]+$'), '');
