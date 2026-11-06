// model_diff.dart: change lookup shared by every renderer and the inspector
// (design §7.2 "Diff" mode): what was added or changed, what was removed
// (drawn as ghosts from the base), and which areas a change involves.

import 'package:modelling/modelling.dart' hide View;

/// A [ChangeSet] between a base and the current model, indexed for
/// renderers. Empty when there is no base.
class ModelDiff {
  ModelDiff._(this.changes, this.base, this._baseIndex, Model model, ModelIndex index) {
    if (changes == null) return;
    for (final c in changes!.nodes) {
      if (c.kind == ChangeKind.removed) {
        final n = base!.nodeById(c.id)!;
        removedNodes[n.id] = n;
      } else {
        involved.add(c.id);
      }
    }
    for (final c in changes!.edges) {
      if (c.kind == ChangeKind.removed) {
        final e = base!.edgeById(c.id)!;
        removedEdges[e.id] = e;
        for (final end in [e.from, e.to]) {
          if (index.node(end) != null) involved.add(end);
        }
      } else {
        final e = model.edgeById(c.id)!;
        involved.addAll([e.from, e.to]);
      }
    }
    for (final n in removedNodes.values) {
      final p = _baseIndex!.parent(n.id);
      if (removedNodes.containsKey(p)) {
        (_ghostChildren[p] ??= []).add(n.id);
      } else {
        // Hangs off a surviving area, or the top level.
        final at = index.node(p) == null ? '' : p;
        (_ghostChildren[at] ??= []).add(n.id);
        if (at != '') involved.add(at);
      }
    }
    for (final e in [...model.edges, ...removedEdges.values]) {
      (_edgesAt[e.from] ??= []).add(e.id);
      if (e.to != e.from) (_edgesAt[e.to] ??= []).add(e.id);
    }
  }

  /// Compares [model] against [base]; no base means no changes.
  factory ModelDiff(Model model, ModelIndex index, Model? base) {
    if (base == null) return ModelDiff._(null, null, null, model, index);
    return ModelDiff._(compare(base, model), base, base.index, model, index);
  }

  /// Null when there is no base.
  final ChangeSet? changes;
  final Model? base;
  final ModelIndex? _baseIndex;

  /// Base nodes and edges no longer in the model, by id.
  final removedNodes = <String, Node>{};
  final removedEdges = <String, Edge>{};

  /// Areas a change touches: added or changed areas, the ends of added,
  /// changed or removed relationships, and the areas removed ones hung off.
  final involved = <String>{};
  final _ghostChildren = <String, List<String>>{};
  final _edgesAt = <String, List<String>>{};

  bool get hasBase => changes != null;

  /// Added, changed and removed nodes and edges.
  int get count => changes?.count ?? 0;

  bool get isEmpty => count == 0;

  /// How [id] differs from the base: added, changed, removed, or null.
  ChangeKind? nodeChange(String id) => changes?.node(id)?.kind;
  ChangeKind? edgeChange(String id) => changes?.edge(id)?.kind;

  /// The field changes for an element (empty when unchanged).
  List<FieldChange> fields(String id, {required bool edge}) =>
      (edge ? changes?.edge(id) : changes?.node(id))?.fields ?? const [];

  /// Removed areas to draw as ghosts inside [parent] ('' is the top level).
  List<String> ghostsIn(String parent) => _ghostChildren[parent] ?? const [];

  /// Ids of current and removed relationships touching [node], in model
  /// order then base order.
  List<String> edgesAt(String node) => _edgesAt[node] ?? const [];

  /// The base parent of a removed node ('' when top level).
  String ghostParent(String id) => _baseIndex?.parent(id) ?? '';

  /// Words for a change marker's tooltip.
  static String describe(ChangeKind? kind) => switch (kind) {
    ChangeKind.added => 'Added: not in the base',
    ChangeKind.changed => 'Changed from the base',
    ChangeKind.removed => 'Removed since the base',
    null => '',
  };
}
