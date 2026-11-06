// outline_rows.dart: the outline as a flat list of rows: each area, the
// relationships it starts listed under it, then its contents. Pure, so it
// can be built lazily and tested directly.

import '../../controller/model_controller.dart';

/// One outline row: an area (current or removed), or a relationship
/// listed under the area it starts from.
class OutlineRow {
  const OutlineRow.area(this.id, this.depth, {this.ghost = false, this.folded = false, this.childCount = 0})
    : edgeId = null;
  const OutlineRow.edge(this.id, this.edgeId, this.depth, {this.ghost = false}) : folded = false, childCount = 0;

  /// The area's id (for a relationship row, the area it is listed under).
  final String id;
  final String? edgeId;
  final int depth;
  final bool ghost;
  final bool folded;
  final int childCount;

  bool get isArea => edgeId == null;
}

/// Rows for [c]'s visible areas (from the drill-in region when set),
/// honouring search, filter, "Changed only", folding and diff ghosts.
List<OutlineRow> outlineRows(ModelController c, int openDepth) {
  final ix = c.index, diff = c.diff, vis = c.visibility;
  final rows = <OutlineRow>[];

  bool listed(String edgeId) => !c.changedOnly || diff.edgeChange(edgeId) != null;

  void edges(String id, int depth) {
    for (final e in c.model.edges) {
      if (e.from == id && listed(e.id)) rows.add(OutlineRow.edge(id, e.id, depth + 1));
    }
    for (final e in diff.removedEdges.values) {
      if (e.from == id) rows.add(OutlineRow.edge(id, e.id, depth + 1, ghost: true));
    }
  }

  void ghost(String id, int depth) {
    rows.add(OutlineRow.area(id, depth, ghost: true, childCount: diff.ghostsIn(id).length));
    edges(id, depth);
    for (final k in diff.ghostsIn(id)) {
      ghost(k, depth + 1);
    }
  }

  List<String> ghostsIn(String parent) => [
    for (final g in diff.ghostsIn(parent))
      if (vis.ghostMatches(diff.removedNodes[g]!)) g,
  ];

  void area(String id, int depth) {
    final kids = [
      for (final k in ix.children(id))
        if (vis.included.contains(k)) k,
    ];
    final ghosts = ghostsIn(id);
    final count = kids.length + ghosts.length;
    final folded = count > 0 && c.isFolded(id, depth, openDepth);
    rows.add(OutlineRow.area(id, depth, folded: folded, childCount: count));
    edges(id, depth);
    if (folded) return;
    for (final k in kids) {
      area(k, depth + 1);
    }
    for (final g in ghosts) {
      ghost(g, depth + 1);
    }
  }

  final region = c.region;
  if (region != null && vis.included.contains(region)) {
    area(region, 0);
  } else {
    for (final id in vis.roots) {
      area(id, 0);
    }
    for (final g in ghostsIn('')) {
      ghost(g, 0);
    }
  }
  return rows;
}
