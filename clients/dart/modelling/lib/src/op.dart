// op.dart: id-addressed edit operations, ported from Go edit/op.go. The JSON
// form matches Go's edit.Op field for field.

import 'codec.dart';
import 'json_read.dart';
import 'model.dart';
import 'validate.dart';

/// Operation names and prop/evidence targets.
abstract final class Ops {
  static const nodeAdd = 'node.add';
  static const nodeRemove = 'node.remove';
  static const nodeMove = 'node.move';
  static const nodeSet = 'node.set';
  static const edgeAdd = 'edge.add';
  static const edgeRemove = 'edge.remove';
  static const edgeSet = 'edge.set';
  static const propSet = 'prop.set';
  static const propUnset = 'prop.unset';
  static const evidenceAdd = 'evidence.add';
  static const evidenceRemove = 'evidence.remove';
  static const modelSet = 'model.set';
  static const viewPut = 'view.put';
  static const viewRemove = 'view.remove';

  static const targetNode = 'node';
  static const targetEdge = 'edge';
}

/// One operation. Which fields it uses depends on [op]:
///
///     node.add        node, index?            index: position in nodes; absent appends
///     node.remove     id, cascade?            cascade removes descendants and touching edges
///     node.move       id, parent, index?      parent "" is top level; absent index keeps the position
///     node.set        id, fields              label, kind, notes, tags, link (null clears)
///     edge.add        edge, index?
///     edge.remove     id
///     edge.set        id, fields              label, from, to, kind, undirected, notes, tags
///     prop.set        target, id, key, value
///     prop.unset      target, id, key
///     evidence.add    target, id, evidence, index?   an already-cited ref is skipped
///     evidence.remove target, id, evidenceId
///     model.set       fields                  title, subject, notes, profile, tags
///     view.put        view, index?            replaces the view with the same id, else inserts
///     view.remove     id
class Op extends JsonValue {
  Op({
    required this.op,
    this.id = '',
    this.target = '',
    this.node,
    this.edge,
    this.view,
    this.evidence,
    this.evidenceId = '',
    this.parent = '',
    this.index,
    this.cascade = false,
    this.key = '',
    this.value,
    Map<String, Object?> fields = const {},
  }) : fields = Map.unmodifiable({for (final e in fields.entries) e.key: _jsonValue(e.value)});

  factory Op.nodeAdd(Node node, {int? index}) => Op(op: Ops.nodeAdd, node: node, index: index);
  factory Op.nodeRemove(String id, {bool cascade = false}) => Op(op: Ops.nodeRemove, id: id, cascade: cascade);
  factory Op.nodeMove(String id, {String parent = '', int? index}) =>
      Op(op: Ops.nodeMove, id: id, parent: parent, index: index);

  /// A node.set: field name to new value (null clears; a [Link] or list is
  /// converted to JSON).
  factory Op.nodeSet(String id, Map<String, Object?> fields) => Op(op: Ops.nodeSet, id: id, fields: fields);
  factory Op.edgeAdd(Edge edge, {int? index}) => Op(op: Ops.edgeAdd, edge: edge, index: index);
  factory Op.edgeRemove(String id) => Op(op: Ops.edgeRemove, id: id);
  factory Op.edgeSet(String id, Map<String, Object?> fields) => Op(op: Ops.edgeSet, id: id, fields: fields);
  factory Op.propSet(String target, String id, String key, Object value) =>
      Op(op: Ops.propSet, target: target, id: id, key: key, value: value);
  factory Op.propUnset(String target, String id, String key) => Op(op: Ops.propUnset, target: target, id: id, key: key);
  factory Op.evidenceAdd(String target, String id, Evidence evidence, {int? index}) =>
      Op(op: Ops.evidenceAdd, target: target, id: id, evidence: evidence, index: index);
  factory Op.evidenceRemove(String target, String id, String evidenceId) =>
      Op(op: Ops.evidenceRemove, target: target, id: id, evidenceId: evidenceId);
  factory Op.modelSet(Map<String, Object?> fields) => Op(op: Ops.modelSet, fields: fields);
  factory Op.viewPut(View view, {int? index}) => Op(op: Ops.viewPut, view: view, index: index);
  factory Op.viewRemove(String id) => Op(op: Ops.viewRemove, id: id);

  /// Reads an operation as Go's json.Unmarshal does: unknown fields are
  /// ignored, type mismatches throw [ModelFormatException].
  factory Op.fromJson(Object? json) {
    final o = JsonObject(json, 'op', strict: false, fields: const {});
    final index = o.raw('index');
    if (index != null && index is! int) throw const ModelFormatException('op.index: want an integer');
    final fields = o.raw('fields');
    if (fields != null && fields is! Map<Object?, Object?>) {
      throw const ModelFormatException('op.fields: want an object');
    }
    return Op(
      op: o.str('op'),
      id: o.str('id'),
      target: o.str('target'),
      node: o.optional('node', (v, p) => readNode(v, p, strict: false)),
      edge: o.optional('edge', (v, p) => readEdge(v, p, strict: false)),
      view: o.optional('view', (v, p) => readView(v, p, strict: false)),
      evidence: o.optional('evidence', (v, p) => readEvidence(v, p, strict: false)),
      evidenceId: o.str('evidenceId'),
      parent: o.str('parent'),
      index: index as int?,
      cascade: o.flag('cascade'),
      key: o.str('key'),
      value: o.raw('value'),
      fields: fields is Map<Object?, Object?> ? {for (final e in fields.entries) '${e.key}': e.value} : const {},
    );
  }

  final String op;
  final String id;
  final String target;
  final Node? node;
  final Edge? edge;
  final View? view;
  final Evidence? evidence;
  final String evidenceId;
  final String parent;

  /// The position to insert at; null appends (or, for node.move, keeps it).
  final int? index;
  final bool cascade;
  final String key;

  /// The prop.set value: a String, num or bool.
  final Object? value;

  /// For *.set: field name to new JSON value; null clears.
  final Map<String, Object?> fields;

  @override
  Map<String, Object?> toJson() => {
        'op': op,
        if (id != '') 'id': id,
        if (target != '') 'target': target,
        if (node != null) 'node': node!.toJson(),
        if (edge != null) 'edge': edge!.toJson(),
        if (view != null) 'view': view!.toJson(),
        if (evidence != null) 'evidence': evidence!.toJson(),
        if (evidenceId != '') 'evidenceId': evidenceId,
        if (parent != '') 'parent': parent,
        if (index != null) 'index': index,
        if (cascade) 'cascade': true,
        if (key != '') 'key': key,
        if (value != null) 'value': value,
        if (fields.isNotEmpty) 'fields': fields,
      };
}

Object? _jsonValue(Object? v) => switch (v) {
      JsonValue j => j.toJson(),
      List<Object?> l => [for (final x in l) _jsonValue(x)],
      _ => v,
    };

/// A refused [apply]. [index] is the failing operation, or -1 when the
/// operations ran but the result is not a valid model ([issues] say why).
class EditException implements Exception {
  EditException(this.index, this.code, this.message, [List<Issue> issues = const []])
      : issues = List.unmodifiable(issues);

  final int index;
  final String code;
  final String message;
  final List<Issue> issues;

  Map<String, Object?> toJson() => {
        'index': index,
        'code': code,
        'message': message,
        if (issues.isNotEmpty) 'issues': [for (final i in issues) i.toJson()],
      };

  @override
  String toString() => index < 0 ? 'edit: result is not a valid model: $message' : 'edit: operation $index: $message';
}

/// An operation's failure before its index is known (internal to apply).
class OpError implements Exception {
  OpError(this.code, this.message);

  final String code;
  final String message;
}
