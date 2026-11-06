// outline.dart: Markdown outlines, ported from Go export/outline.go. Output
// is byte-identical to Go's.
//
// Go's regexps are RE2; RE2's `.` matches anything but \n, so it is spelled
// `[^\n]` here (Dart's `.` also stops at \r, U+2028 and U+2029).

import 'canonical.dart';
import 'export_ids.dart';
import 'index.dart';
import 'json_read.dart';
import 'model.dart';
import 'validate.dart';

/// [m] as Markdown: the title, subject and notes, a nested list of areas,
/// then the relationships. The cheapest form for a reader (or an agent) to
/// take in a large model.
///
///     # Title
///
///     Subject
///
///     - **Label** `id`: notes
///       - **Child** `child`
///
///     ## Relationships
///
///     - `from` -> `to`: label `id`
String toOutline(Model m) {
  final ix = ModelIndex(m);
  final b = StringBuffer('# ${oneLine(m.title)}\n\n${oneLine(m.subject)}\n');
  final notes = oneLine(m.notes);
  if (notes != '') b.write('\n$notes\n');
  if (m.nodes.isNotEmpty) b.write('\n');
  void walk(String parent, int depth) {
    for (final id in ix.children(parent)) {
      final n = ix.node(id)!;
      b.write('${'  ' * depth}- **${oneLine(n.label)}** `${n.id}`');
      final notes = oneLine(n.notes);
      if (notes != '') b.write(': $notes');
      b.write('\n');
      walk(id, depth + 1);
    }
  }

  walk('', 0);
  if (m.edges.isNotEmpty) {
    b.write('\n## Relationships\n\n');
    for (final e in m.edges) {
      b.write('- `${e.from}` ${e.undirected ? '--' : '->'} `${e.to}`: ${oneLine(e.label)} `${e.id}`\n');
    }
  }
  return b.toString();
}

final _item = RegExp(r'^( *)[-*] +(?:\*\*([^\n]+?)\*\*|([^`:]+?))(?: +`([^`]+)`)?(?: *: *([^\n]*))?$');
final _edge = RegExp(r'^[-*] +(?:`([^`]+)`|([^`]+?)) +(->|--) +(?:`([^`]+)`|([^`:]+?)) *: *([^\n]+?)(?: +`([^`]+)`)?$');

/// Reads the Markdown [toOutline] writes, and hand-written outlines like
/// it: "# Title", the first paragraph as the subject and the next as notes,
/// list items as areas (two spaces of indent per level; "**label**" or a
/// plain label, an optional `id`, and ": notes"), and under a
/// "## Relationships" heading, items "`from` -> `to`: label `id`" ("--" for
/// undirected; ends may be ids or labels). Throws [ModelFormatException]
/// naming the line. The result is not validated.
Model parseOutline(String src) {
  var title = 'Untitled model', subject = 'Imported outline', modelNotes = '';
  final ids = ImportIds();
  final paragraphs = <String>[];
  final stack = <String>[]; // ancestor ids by depth
  final nodes = <Node>[];
  var relationships = false;
  final pending = <({int line, String from, String to, String label, String id, bool undirected})>[];
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  Never fail(int line, String message) => throw ModelFormatException('invalid model: outline line $line: $message');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceFirst(RegExp(r'[ \t]+$'), '');
    final trimmed = goTrimSpace(line);
    if (trimmed == '') continue;
    if (trimmed.startsWith('## ')) {
      relationships = goEqualFold(goTrimSpace(trimmed.substring(3)), 'relationships');
      continue;
    }
    if (trimmed.startsWith('# ')) {
      title = goTrimSpace(trimmed.substring(2));
      continue;
    }
    if (relationships) {
      final g = _edge.firstMatch(trimmed) ?? fail(i + 1, 'cannot read relationship ${goQuote(trimmed)}');
      pending.add((
        line: i + 1,
        from: (g[1] ?? '') + (g[2] ?? ''),
        to: (g[4] ?? '') + (g[5] ?? ''),
        label: goTrimSpace(g[6]!),
        id: g[7] ?? '',
        undirected: g[3] == '--',
      ));
      continue;
    }
    final g = _item.firstMatch(line);
    if (g == null) {
      if (nodes.isEmpty) {
        paragraphs.add(trimmed);
        continue;
      }
      fail(i + 1, 'cannot read ${goQuote(trimmed)}');
    }
    final depth = g[1]!.length ~/ 2;
    if (depth > stack.length) fail(i + 1, 'indented more than one level past its parent');
    stack.removeRange(depth, stack.length);
    final label = goTrimSpace((g[2] ?? '') + (g[3] ?? ''));
    var id = g[4] ?? '';
    if (id == '' || !ids.claim(id)) id = ids.fresh(label);
    nodes.add(Node(id: id, label: label, parent: depth > 0 ? stack[depth - 1] : '', notes: goTrimSpace(g[5] ?? '')));
    stack.add(id);
  }
  if (paragraphs.isNotEmpty) subject = paragraphs.first;
  if (paragraphs.length > 1) modelNotes = paragraphs.skip(1).join(' ');
  String resolve(String name) {
    for (final n in nodes) {
      if (n.id == name) return n.id;
    }
    for (final n in nodes) {
      if (goEqualFold(n.label, goTrimSpace(name))) return n.id;
    }
    return '';
  }

  final edges = <Edge>[];
  for (final e in pending) {
    final from = resolve(e.from), to = resolve(e.to);
    if (from == '' || to == '') fail(e.line, 'relationship names an unknown area');
    var id = e.id;
    if (id == '' || !validId(id) || ids.edges.contains(id)) {
      id = ids.edge(from, to);
    } else {
      ids.edges.add(id);
    }
    edges.add(Edge(id: id, from: from, to: to, label: e.label, undirected: e.undirected));
  }
  return Model(title: title, subject: subject, notes: modelNotes, nodes: nodes, edges: edges);
}
