// shown_elements.dart: the areas and relationships a flat renderer (graph,
// matrix, table) draws, in containment order: the visible areas within the
// drill-in region, removed ghosts from the base where they hung, and the
// relationships between them. Shared so those renderers agree on what is
// shown with each other and with blocks and outline.

import '../controller/model_controller.dart';

/// One shown area: current or removed ([ghost]), its [depth] below the
/// drawn root and its drawn [parent] (null at the top).
class ShownNode {
  const ShownNode(this.id, this.depth, this.parent, {this.ghost = false});

  final String id;
  final int depth;
  final String? parent;
  final bool ghost;
}

/// The areas [c]'s search, filter, "Changed only" and drill-in region
/// show, parents before their contents, siblings in document order, with
/// matching removed areas after their surviving siblings.
List<ShownNode> shownNodes(ModelController c) {
  final ix = c.index, diff = c.diff, vis = c.visibility;
  final out = <ShownNode>[];

  void ghost(String id, int depth, String? parent) {
    out.add(ShownNode(id, depth, parent, ghost: true));
    for (final k in diff.ghostsIn(id)) {
      ghost(k, depth + 1, id);
    }
  }

  void ghostsIn(String at, int depth, String? parent) {
    for (final g in diff.ghostsIn(at)) {
      if (vis.ghostMatches(diff.removedNodes[g]!)) ghost(g, depth, parent);
    }
  }

  void area(String id, int depth, String? parent) {
    out.add(ShownNode(id, depth, parent));
    for (final k in ix.children(id)) {
      if (vis.included.contains(k)) area(k, depth + 1, id);
    }
    ghostsIn(id, depth + 1, id);
  }

  final region = c.region;
  if (region != null && vis.included.contains(region)) {
    area(region, 0, null);
  } else {
    for (final id in vis.roots) {
      area(id, 0, null);
    }
    ghostsIn('', 0, null);
  }
  return out;
}

/// Ids of current then removed relationships whose ends are both in
/// [shown]; with "Changed only", just the changed ones.
List<String> shownEdges(ModelController c, Set<String> shown) => [
  for (final e in [...c.model.edges, ...c.diff.removedEdges.values])
    if (shown.contains(e.from) && shown.contains(e.to) && (!c.changedOnly || c.diff.edgeChange(e.id) != null)) e.id,
];
