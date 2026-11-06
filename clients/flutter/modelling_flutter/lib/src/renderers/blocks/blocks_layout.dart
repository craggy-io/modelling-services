// blocks_layout.dart: which areas the blocks board draws, nested and paged,
// from the controller's view state. Pure (no widgets), so the workspace can
// count what is shown and tests can check the rules directly.

import '../../controller/model_controller.dart';
import '../../theme/model_theme.dart';

/// One laid-out area: a model node, a removed one from the base (a ghost),
/// or the root (no id).
class BlockArea {
  const BlockArea({
    this.id,
    required this.title,
    this.description = '',
    this.children = const [],
    this.childCount = 0,
    this.folded = false,
    this.ghost = false,
  });

  final String? id;
  final String title;
  final String description;
  final List<BlockArea> children;

  /// Child areas it has, drawn or folded.
  final int childCount;
  final bool folded;
  final bool ghost;
}

/// The laid-out board.
class BlocksLayout {
  const BlocksLayout(this.root, this.shown, this.included, this.order);

  final BlockArea root;

  /// Model areas drawn (ghosts are not counted).
  final int shown;

  /// Model areas the search and filter include.
  final int included;

  /// Drawn area ids in reading order, for keyboard navigation.
  final List<String> order;

  /// Whether paging stopped before every included area was drawn.
  bool more(int limit) => shown >= limit && shown < included;
}

/// Lays out the board for [c] with [t]'s page size and open depth.
BlocksLayout layoutBlocks(ModelController c, ModelTheme t) {
  final ix = c.index, diff = c.diff, vis = c.visibility;
  final limit = c.limit ?? t.pageSize;
  final query = vis.queryActive;
  final order = <String>[];
  var shown = 0;

  List<String> ghostsIn(String parent) => [
    for (final g in diff.ghostsIn(parent))
      if (vis.ghostMatches(diff.removedNodes[g]!)) g,
  ];

  BlockArea ghost(String id) {
    order.add(id);
    final n = diff.removedNodes[id]!;
    final kids = diff.ghostsIn(id);
    return BlockArea(
      id: id,
      title: n.label,
      description: n.notes,
      ghost: true,
      childCount: kids.length,
      children: [for (final k in kids) ghost(k)],
    );
  }

  BlockArea? area(String id, int depth) {
    if (!vis.included.contains(id) || shown >= limit) return null;
    shown++;
    order.add(id);
    final node = ix.node(id)!;
    final children = [
      for (final k in ix.children(id))
        if (vis.included.contains(k)) k,
    ];
    final ghosts = ghostsIn(id);
    final count = children.length + ghosts.length;
    final folded = count > 0 && c.isFolded(id, depth, t.openDepth);
    final parent = ix.node(node.parent);
    return BlockArea(
      id: id,
      title: node.label,
      description: [
        if (query && parent != null) 'In ${parent.label}',
        if (node.notes.isNotEmpty) node.notes,
      ].join(' · '),
      childCount: count,
      folded: folded,
      children: folded ? const [] : [for (final k in children) ?area(k, depth + 1), for (final g in ghosts) ghost(g)],
    );
  }

  final region = c.region;
  final local = region == null ? null : area(region, 0);
  if (local != null) return BlocksLayout(local, shown, vis.included.length, order);

  final m = c.model;
  final ghosts = ghostsIn('');
  final folded = c.isFolded(null, 0, t.openDepth) && !query;
  final root = BlockArea(
    title: m.title,
    description: [query ? 'Search results across ${m.subject}' : m.subject, if (m.notes.isNotEmpty) m.notes].join('\n'),
    childCount: vis.roots.length + ghosts.length,
    folded: folded,
    children: folded ? const [] : [for (final id in vis.roots) ?area(id, 0), for (final g in ghosts) ghost(g)],
  );
  return BlocksLayout(root, shown, vis.included.length, order);
}
