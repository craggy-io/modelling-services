// index.dart: structural questions about one model, ported from Go
// model/index.go.

import 'model.dart';

/// Answers structural questions about one model without rescanning it. The
/// model is immutable, so an index never goes stale.
class ModelIndex {
  /// Indexes [model]. Nodes whose parent is missing count as top level.
  ModelIndex(this.model) {
    for (var i = 0; i < model.nodes.length; i++) {
      _nodes[model.nodes[i].id] = i;
    }
    for (final n in model.nodes) {
      final p = _nodes.containsKey(n.parent) ? n.parent : '';
      (_children[p] ??= []).add(n.id);
    }
    for (var i = 0; i < model.edges.length; i++) {
      final e = model.edges[i];
      _edges[e.id] = i;
      (_touching[e.from] ??= []).add(e.id);
      if (e.to != e.from) (_touching[e.to] ??= []).add(e.id);
    }
  }

  /// The indexed model.
  final Model model;
  final _nodes = <String, int>{};
  final _edges = <String, int>{};
  final _children = <String, List<String>>{};
  final _touching = <String, List<String>>{};

  /// The node with [id], if any.
  Node? node(String id) {
    final i = _nodes[id];
    return i == null ? null : model.nodes[i];
  }

  /// The edge with [id], if any.
  Edge? edge(String id) {
    final i = _edges[id];
    return i == null ? null : model.edges[i];
  }

  /// The node's position in [Model.nodes], or -1.
  int nodeIndex(String id) => _nodes[id] ?? -1;

  /// The edge's position in [Model.edges], or -1.
  int edgeIndex(String id) => _edges[id] ?? -1;

  /// The ids of [parent]'s direct children ("" for top level), in document order.
  List<String> children(String parent) => List.unmodifiable(_children[parent] ?? const []);

  /// The containing node's id, or "" at top level.
  String parent(String id) {
    final p = node(id)?.parent ?? '';
    return _nodes.containsKey(p) ? p : '';
  }

  /// The ids of [id]'s containing nodes, nearest first. Stops at a cycle.
  List<String> ancestors(String id) {
    final out = <String>[];
    final seen = {id};
    for (var p = parent(id); p != '' && !seen.contains(p); p = parent(p)) {
      seen.add(p);
      out.add(p);
    }
    return out;
  }

  /// Every node inside [id], depth first in document order.
  List<String> descendants(String id) {
    final out = <String>[];
    final seen = {id};
    void walk(String p) {
      for (final c in _children[p] ?? const <String>[]) {
        if (seen.add(c)) {
          out.add(c);
          walk(c);
        }
      }
    }

    walk(id);
    return out;
  }

  /// The ids of edges with node [id] at either end, in document order.
  List<String> touching(String id) => List.unmodifiable(_touching[id] ?? const []);

  /// [id]'s containment depth: 1 at top level.
  int depth(String id) => ancestors(id).length + 1;
}
