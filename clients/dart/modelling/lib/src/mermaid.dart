// mermaid.dart: Mermaid flowcharts, ported from Go export/mermaid.go. Output
// is byte-identical to Go's.
//
// Go's regexps are RE2; these are translated so they match identically:
// RE2's `\s` is ASCII-only, so it is spelled `[\t\n\f\r ]`.

import 'canonical.dart';
import 'export_ids.dart';
import 'index.dart';
import 'json_read.dart';
import 'model.dart';

/// [m] as a Mermaid flowchart: one subgraph per node with children, one node
/// per leaf, then every edge. Ids are prefixed "n_" so no id collides with a
/// Mermaid keyword.
String toMermaid(Model m) {
  final ix = ModelIndex(m);
  final b = StringBuffer('---\ntitle: ${oneLine(m.title)}\n---\nflowchart LR\n');
  void walk(String parent, int depth) {
    final pad = '  ' * depth;
    for (final id in ix.children(parent)) {
      final n = ix.node(id)!;
      if (ix.children(id).isNotEmpty) {
        b.write('${pad}subgraph n_$id["${_text(n.label)}"]\n');
        walk(id, depth + 1);
        b.write('${pad}end\n');
      } else {
        b.write('${pad}n_$id["${_text(n.label)}"]\n');
      }
    }
  }

  walk('', 1);
  for (final e in m.edges) {
    b.write('  n_${e.from} ${e.undirected ? '---' : '-->'}|"${_text(e.label)}"| n_${e.to}\n');
  }
  return b.toString();
}

String _text(String s) => oneLine(s).replaceAll('"', '#quot;');

const _s = r'[\t\n\f\r ]';
const _node = '([A-Za-z0-9_-]+)(?:$_s*(?:\\[\\[|\\[\\(|\\[|\\(\\(|\\(|\\{)$_s*("[^"]*"|[^\\]\\)\\}]*?)$_s*'
    '(?:\\]\\]|\\)\\]|\\]|\\)\\)|\\)|\\}))?';
final _subgraph = RegExp('^subgraph$_s+$_node$_s*\$');
final _edge = RegExp('^$_node$_s*(-->|---|-\\.->|==>|--$_s*[^-|>][^>]*?$_s*-->)$_s*'
    '(?:\\|$_s*("[^"]*"|[^|]*?)$_s*\\|)?$_s*$_node$_s*;?\$');
final _lone = RegExp('^$_node$_s*;?\$');

const _ignored = ['classDef ', 'class ', 'style ', 'click ', 'linkStyle ', 'direction '];

/// Reads a Mermaid flowchart: front-matter title, subgraphs (nested areas),
/// node declarations and single edges (-->, ---, -.->, ==>, "-- label -->",
/// with an optional |label|). Styling, class and click lines are ignored;
/// anything else throws [ModelFormatException] naming the line. The result
/// is not validated.
Model parseMermaid(String src) {
  var title = 'Untitled model';
  final ids = ImportIds();
  final labels = <String, String>{};
  final parents = <String, String>{};
  final order = <String>[];
  final edges = <Edge>[];
  String declare(String raw, String label, String parent, bool explicit) {
    final id = ids.node(raw);
    if (!labels.containsKey(id)) {
      order.add(id);
      labels[id] = id;
      parents[id] = parent;
    }
    if (explicit) labels[id] = label;
    return id;
  }

  final stack = <String>[];
  String parent() => stack.isEmpty ? '' : stack.last;
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  var inFront = false;
  for (var i = 0; i < lines.length; i++) {
    final line = goTrimSpace(lines[i]);
    if (line == '---' && (i == 0 || inFront)) {
      inFront = !inFront;
      continue;
    }
    if (inFront) {
      if (line.startsWith('title:')) title = goTrimSpace(line.substring(6));
      continue;
    }
    if (line == '' ||
        line.startsWith('%%') ||
        line.startsWith('flowchart') ||
        line.startsWith('graph') ||
        _ignored.any(line.startsWith)) {
      continue;
    }
    if (line == 'end') {
      if (stack.isEmpty) throw ModelFormatException('invalid model: mermaid line ${i + 1}: end without subgraph');
      stack.removeLast();
      continue;
    }
    var g = _subgraph.firstMatch(line);
    if (g != null) {
      final id = declare(g[1]!, _unquote(g[2]), parent(), (g[2] ?? '') != '');
      parents[id] = parent();
      stack.add(id);
      continue;
    }
    g = _edge.firstMatch(line);
    if (g != null) {
      final from = declare(g[1]!, _unquote(g[2]), parent(), (g[2] ?? '') != '');
      final to = declare(g[5]!, _unquote(g[6]), parent(), (g[6] ?? '') != '');
      final arrow = g[3]!;
      var label = _unquote(g[4]);
      if (label == '' && arrow.startsWith('--')) {
        final l = arrow.substring(2);
        if (l.endsWith('-->')) label = goTrimSpace(l.substring(0, l.length - 3));
      }
      if (label == '') label = 'relates to';
      edges.add(Edge(id: ids.edge(from, to), from: from, to: to, label: label, undirected: arrow == '---'));
      continue;
    }
    g = _lone.firstMatch(line);
    if (g != null) {
      // Listing a node inside a subgraph moves it there, as in Mermaid.
      final id = declare(g[1]!, _unquote(g[2]), parent(), (g[2] ?? '') != '');
      final p = parent();
      if (p != '' && p != id) parents[id] = p;
      continue;
    }
    throw ModelFormatException('invalid model: mermaid line ${i + 1}: cannot read ${goQuote(line)}');
  }
  if (stack.isNotEmpty) {
    throw ModelFormatException('invalid model: mermaid: subgraph ${goQuote(stack.last)} is not closed');
  }
  return Model(
    title: title,
    subject: 'Imported from Mermaid',
    nodes: [for (final id in order) Node(id: id, label: labels[id]!, parent: parents[id]!)],
    edges: edges,
  );
}

String _unquote(String? s) {
  var t = goTrimSpace(s ?? '');
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) t = t.substring(1, t.length - 1);
  return goTrimSpace(t.replaceAll('#quot;', '"'));
}
