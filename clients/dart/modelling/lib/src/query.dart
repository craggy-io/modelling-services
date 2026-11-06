// query.dart: search, neighbours, paths and impact, ported from Go
// query/query.go. Every function returns ids in a deterministic order, so Go
// and Dart agree.

import 'canonical.dart';
import 'index.dart';
import 'model.dart';

/// Which way [neighbours] follows edges. Undirected edges are followed both
/// ways whatever the direction.
enum Direction {
  outgoing('out'),
  incoming('in'),
  both('both');

  const Direction(this.wire);

  /// The JSON name: "out", "in" or "both".
  final String wire;

  /// The direction named [wire]; anything else is [both], as in Go.
  static Direction parse(String wire) => values.firstWhere((d) => d.wire == wire, orElse: () => both);
}

/// The ids of nodes matching [filter], in document order. Text matches
/// case-insensitively against id, label, notes, tags and property values;
/// kinds and tags match any listed value. changedOnly is ignored here (it
/// needs a base; callers filter with a diff).
List<String> search(ModelIndex ix, Filter filter) {
  final text = goTrimSpace(filter.text).toLowerCase();
  return [
    for (final n in ix.model.nodes)
      if ((filter.kinds.isEmpty || filter.kinds.contains(n.kind)) &&
          (filter.tags.isEmpty || filter.tags.any(n.tags.contains)) &&
          (text == '' || haystack(n).contains(text)))
        n.id,
  ];
}

/// The lower-cased text [search] matches a node against.
String haystack(Node n) => [
      n.id,
      n.label,
      n.notes,
      ...n.tags,
      for (final k in sortedKeys(n.properties)) goSprint(n.properties[k])
    ].join('\n').toLowerCase();

/// The nodes within [depth] edges of [id] (depth < 1 means 1), breadth
/// first, each level in edge document order. [id] itself is excluded.
List<String> neighbours(ModelIndex ix, String id, Direction dir, int depth) {
  if (depth < 1) depth = 1;
  final seen = {id};
  final out = <String>[];
  var frontier = [id];
  for (var level = 0; level < depth && frontier.isNotEmpty; level++) {
    final next = <String>[];
    for (final n in frontier) {
      for (final other in _step(ix, n, dir)) {
        if (seen.add(other)) {
          out.add(other);
          next.add(other);
        }
      }
    }
    frontier = next;
  }
  return out;
}

/// The nodes one edge away from [id], in edge document order.
List<String> _step(ModelIndex ix, String id, Direction dir) {
  final out = <String>[];
  for (final eid in ix.touching(id)) {
    final e = ix.edge(eid)!;
    if (e.from == id && (dir != Direction.incoming || e.undirected)) out.add(e.to);
    if (e.to == id && e.from != id && (dir != Direction.outgoing || e.undirected)) out.add(e.from);
  }
  return out;
}

/// The simple paths from [from] to [to], each as the edge ids it follows,
/// following edges forward (undirected edges either way), at most [maxLen]
/// edges long and at most [maxPaths] of them, depth first in edge document
/// order.
List<List<String>> paths(ModelIndex ix, String from, String to, int maxLen, int maxPaths) {
  final out = <List<String>>[];
  final visited = {from};
  final path = <String>[];
  void walk(String at) {
    for (final eid in ix.touching(at)) {
      if (out.length >= maxPaths) return;
      final e = ix.edge(eid)!;
      final String next;
      if (e.from == at) {
        next = e.to;
      } else if (e.undirected && e.to == at) {
        next = e.from;
      } else {
        continue;
      }
      if (next == to) {
        out.add([...path, eid]);
        continue;
      }
      if (visited.contains(next) || path.length + 1 >= maxLen) continue;
      visited.add(next);
      path.add(eid);
      walk(next);
      path.removeLast();
      visited.remove(next);
    }
  }

  if (maxLen > 0 && maxPaths > 0) walk(from);
  return out;
}

/// Every node reachable forward from [id] or anything inside it, in
/// document order, excluding [id] and its descendants: what a change here
/// could affect.
List<String> impact(ModelIndex ix, String id) {
  final inside = {id, ...ix.descendants(id)};
  final reached = <String>{};
  var frontier = inside.toList();
  while (frontier.isNotEmpty) {
    final next = <String>[];
    for (final n in frontier) {
      for (final other in _step(ix, n, Direction.outgoing)) {
        if (!inside.contains(other) && reached.add(other)) next.add(other);
      }
    }
    frontier = next;
  }
  return [
    for (final n in ix.model.nodes)
      if (reached.contains(n.id)) n.id,
  ];
}
