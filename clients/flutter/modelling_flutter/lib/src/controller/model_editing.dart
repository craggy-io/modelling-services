// model_editing.dart: the editing intents every renderer and the inspector
// share (design §7.3). Each builds operations and runs them through the
// controller, so every gesture is one undoable step.

import 'package:modelling/modelling.dart';

import 'model_controller.dart';
import 'model_types.dart';

/// Editing gestures as operations on a [ModelController].
extension ModelEditing on ModelController {
  /// A node id not used by the model or its base.
  String newNodeId([String stem = 'area']) => _fresh(stem, (id) => nodeOrGhost(id) != null);

  /// An edge id not used by the model or its base.
  String newEdgeId([String stem = 'e']) => _fresh(stem, (id) => edgeOrGhost(id) != null);

  String _fresh(String stem, bool Function(String) used) {
    final base = slug(stem).isEmpty ? 'x' : slug(stem);
    var n = 1;
    while (used('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  /// Adds an area inside [parent] ('' is the top level), unfolds the
  /// parent, selects the new area and returns its id (null if refused).
  String? addChild(String parent, {String label = 'New area'}) {
    final id = newNodeId();
    if (!tryApply([Op.nodeAdd(Node(id: id, label: label, parent: parent))])) return null;
    if (parent != '') reveal(parent);
    select(ModelElementRef.node(id));
    focus(id);
    return id;
  }

  /// Adds an area beside [sibling], right after it in document order.
  String? addSibling(String sibling, {String label = 'New area'}) {
    final at = index.nodeIndex(sibling);
    if (at < 0) return null;
    final id = newNodeId();
    final parent = index.parent(sibling);
    final add = Op.nodeAdd(
      Node(id: id, label: label, parent: parent),
      index: at + 1,
    );
    if (!tryApply([add])) return null;
    select(ModelElementRef.node(id));
    focus(id);
    return id;
  }

  /// Renames an area or relationship; a blank label is refused.
  bool rename(ModelElementRef ref, String label) {
    final l = label.trim();
    if (l.isEmpty) {
      notice.value = 'A label cannot be blank.';
      return false;
    }
    return tryApply([
      ref.isNode ? Op.nodeSet(ref.id, {'label': l}) : Op.edgeSet(ref.id, {'label': l}),
    ]);
  }

  /// What removing [id] takes with it: nested areas and relationships.
  (int areas, int relationships) removalOf(String id) {
    final gone = {id, ...index.descendants(id)};
    final edges = model.edges.where((e) => gone.contains(e.from) || gone.contains(e.to)).length;
    return (gone.length - 1, edges);
  }

  /// Removes an area with everything inside it and its relationships.
  bool deleteNode(String id) => tryApply([Op.nodeRemove(id, cascade: true)]);

  /// Removes a relationship.
  bool deleteEdge(String id) => tryApply([Op.edgeRemove(id)]);

  /// Why [id] cannot move into [parent] ('' is the top level), or null
  /// when it can: no cycles, and the profile's `children` rule holds.
  String? reparentRefusal(String id, String parent) {
    final node = index.node(id);
    if (node == null) return 'That area no longer exists.';
    if (parent == '') return null;
    final target = index.node(parent);
    if (target == null) return 'That area no longer exists.';
    if (parent == id) return 'An area cannot contain itself.';
    if (index.ancestors(parent).contains(id)) {
      return '${target.label} is inside ${node.label}, so ${node.label} cannot move into it.';
    }
    final p = profile;
    final allowed = p?.nodeKinds[target.kind]?.children ?? const [];
    if (allowed.isNotEmpty && node.kind.isNotEmpty && !allowed.contains(node.kind)) {
      final pk = p!.nodeKinds[target.kind]!.label, nk = p.nodeKinds[node.kind]?.label ?? node.kind;
      return '${_article(pk, capital: true)} $pk cannot contain ${_article(nk)} $nk.';
    }
    return null;
  }

  /// Moves [id] into [parent], refusing (with [notice]) when
  /// [reparentRefusal] gives a reason.
  bool reparent(String id, String parent, {int? index}) {
    if (this.index.parent(id) == parent && index == null) return false;
    final why = reparentRefusal(id, parent);
    if (why != null) {
      notice.value = why;
      return false;
    }
    final ok = tryApply([Op.nodeMove(id, parent: parent, index: index)]);
    if (ok && parent != '') reveal(parent);
    return ok;
  }

  /// The `nodes` position that puts [id] right before [other] (after it
  /// when [after]), counted once [id] is taken out.
  int positionBy(String id, String other, {bool after = false}) {
    final rest = [
      for (final n in model.nodes)
        if (n.id != id) n.id,
    ];
    return rest.indexOf(other) + (after ? 1 : 0);
  }

  List<String> _siblings(String id) => index.children(index.parent(id));

  /// Moves [id] into its previous sibling, as its last area (outline Tab).
  bool indent(String id) {
    final sibs = _siblings(id);
    final at = sibs.indexOf(id);
    if (at <= 0) return false;
    return reparent(id, sibs[at - 1]);
  }

  /// Moves [id] out of its parent, right after it (outline Shift-Tab).
  bool outdent(String id) {
    final parent = index.parent(id);
    if (parent == '') return false;
    return reparent(id, index.parent(parent), index: positionBy(id, parent, after: true));
  }

  /// Swaps [id] with its previous ([up]) or next sibling.
  bool reorder(String id, {required bool up}) {
    final sibs = _siblings(id);
    final at = sibs.indexOf(id);
    final other = up ? at - 1 : at + 1;
    if (at < 0 || other < 0 || other >= sibs.length) return false;
    return tryApply([
      Op.nodeMove(
        id,
        parent: index.parent(id),
        index: positionBy(id, sibs[other], after: !up),
      ),
    ]);
  }

  /// Profile edge kinds allowed from [from] to [to] (all when the ends
  /// have no kinds the profile names). Empty without a profile.
  Map<String, EdgeKind> edgeKindsFor(String from, String to) {
    final p = profile;
    if (p == null) return const {};
    final fk = index.node(from)?.kind ?? '', tk = index.node(to)?.kind ?? '';
    return {
      for (final e in p.edgeKinds.entries)
        if ((e.value.from.isEmpty || e.value.from.contains(fk)) && (e.value.to.isEmpty || e.value.to.contains(tk)))
          e.key: e.value,
    };
  }

  /// Adds a relationship and returns its id (null if refused).
  String? addRelationship(String from, String to, {required String label, String kind = '', bool undirected = false}) {
    final id = newEdgeId();
    final edge = Edge(id: id, from: from, to: to, label: label.trim(), kind: kind, undirected: undirected);
    if (!tryApply([Op.edgeAdd(edge)])) return null;
    select(ModelElementRef.edge(id));
    return id;
  }

  /// Sets node or edge fields (`label`, `kind`, `notes`, `tags`, `link`, …).
  bool setFields(ModelElementRef ref, Map<String, Object?> fields) =>
      tryApply([ref.isNode ? Op.nodeSet(ref.id, fields) : Op.edgeSet(ref.id, fields)]);

  /// Sets a property (null unsets it).
  bool setProperty(ModelElementRef ref, String key, Object? value) => tryApply([
    value == null ? Op.propUnset(ref.kind.target, ref.id, key) : Op.propSet(ref.kind.target, ref.id, key, value),
  ]);

  /// Uses [p] for lint and typed editors and names it in the model's
  /// `profile` field (an undoable `model.set`); null clears both.
  bool useProfile(Profile? p) {
    final ref = p?.ref ?? '';
    final set = Op.modelSet({'profile': ref});
    if (model.profile != ref && !tryApply([set])) return false;
    profile = p;
    return true;
  }

  /// Cites [evidence] on an element (refs it already cites are skipped).
  bool attachEvidence(ModelElementRef ref, List<Evidence> evidence) =>
      evidence.isEmpty || tryApply([for (final e in evidence) Op.evidenceAdd(ref.kind.target, ref.id, e)]);

  /// Removes one citation.
  bool removeEvidence(ModelElementRef ref, String evidenceId) =>
      tryApply([Op.evidenceRemove(ref.kind.target, ref.id, evidenceId)]);
}

String _article(String word, {bool capital = false}) {
  final an = word.isNotEmpty && 'aeiouAEIOU'.contains(word[0]);
  return capital ? (an ? 'An' : 'A') : (an ? 'an' : 'a');
}
