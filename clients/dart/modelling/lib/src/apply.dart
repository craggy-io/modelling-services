// apply.dart: runs operations atomically and returns their inverse, ported
// from Go edit/apply.go and edit/fields.go.

import 'canonical.dart';
import 'codec.dart';
import 'index.dart';
import 'json_read.dart';
import 'model.dart';
import 'op.dart';
import 'validate.dart';

/// Runs [ops] against [model], in order, and validates the result with
/// [limits]. All or nothing: on failure it throws [EditException] and
/// [model] (immutable) is untouched. The returned inverse operations,
/// applied to the result, give back [model] exactly.
(Model, List<Op>) apply(Model model, List<Op> ops, [Limits limits = const Limits()]) {
  final s = _State(model);
  var inverse = <Op>[];
  for (var i = 0; i < ops.length; i++) {
    try {
      inverse = [...s.apply(ops[i]), ...inverse];
    } on OpError catch (e) {
      throw EditException(i, e.code, e.message);
    }
  }
  final result = s.result;
  final issues = result.issues(limits);
  if (issues.isNotEmpty) {
    throw EditException(-1, issues.first.code, ModelValidationException(issues).message, issues);
  }
  return (result, List.unmodifiable(inverse));
}

Never _fail(String code, String message) => throw OpError(code, message);

class _State {
  _State(this.m)
      : nodes = [...m.nodes],
        edges = [...m.edges],
        views = [...m.views];

  Model m; // the model's own fields
  final List<Node> nodes;
  final List<Edge> edges;
  final List<View> views;

  Model get result => m.copyWith(nodes: nodes, edges: edges, views: views);

  int node(String id) => nodes.indexWhere((n) => n.id == id);
  int edge(String id) => edges.indexWhere((e) => e.id == id);

  List<Op> apply(Op op) {
    final q = goQuote;
    switch (op.op) {
      case Ops.nodeAdd:
        final add = op.node ?? _fail('op.field', 'node.add needs a node');
        if (node(add.id) >= 0) _fail('op.exists', 'node ${q(add.id)} already exists');
        final n = add.copyWith(evidence: fillEvidenceIds(add.evidence));
        _insert(nodes, n, op.index);
        return [Op.nodeRemove(n.id)];
      case Ops.nodeRemove:
        return _removeNode(op);
      case Ops.nodeMove:
        final i = node(op.id);
        if (i < 0) _fail('op.missing', 'no node ${q(op.id)}');
        final n = nodes[i];
        final inv = Op.nodeMove(n.id, parent: n.parent, index: i);
        final moved = n.copyWith(parent: op.parent);
        if (op.index == null) {
          nodes[i] = moved;
        } else {
          final rest = [...nodes]..removeAt(i);
          _insert(rest, moved, op.index);
          nodes
            ..clear()
            ..addAll(rest);
        }
        return [inv];
      case Ops.nodeSet:
        final i = node(op.id);
        if (i < 0) _fail('op.missing', 'no node ${q(op.id)}');
        final (n, inv) = _setFields(op, nodes[i], _nodeFields);
        nodes[i] = n;
        return [inv];
      case Ops.edgeAdd:
        final add = op.edge ?? _fail('op.field', 'edge.add needs an edge');
        if (edge(add.id) >= 0) _fail('op.exists', 'edge ${q(add.id)} already exists');
        final e = add.copyWith(evidence: fillEvidenceIds(add.evidence));
        _insert(edges, e, op.index);
        return [Op.edgeRemove(e.id)];
      case Ops.edgeRemove:
        final i = edge(op.id);
        if (i < 0) _fail('op.missing', 'no edge ${q(op.id)}');
        return [Op.edgeAdd(edges.removeAt(i), index: i)];
      case Ops.edgeSet:
        final i = edge(op.id);
        if (i < 0) _fail('op.missing', 'no edge ${q(op.id)}');
        final (e, inv) = _setFields(op, edges[i], _edgeFields);
        edges[i] = e;
        return [inv];
      case Ops.propSet || Ops.propUnset:
        return _prop(op);
      case Ops.evidenceAdd || Ops.evidenceRemove:
        return _evidence(op);
      case Ops.modelSet:
        final (next, inv) = _setFields(op, m, _modelFields);
        m = next;
        return [inv];
      case Ops.viewPut:
        return _putView(op);
      case Ops.viewRemove:
        final i = views.indexWhere((v) => v.id == op.id);
        if (i < 0) _fail('op.missing', 'no view ${q(op.id)}');
        return [Op.viewPut(views.removeAt(i), index: i)];
    }
    _fail('op.unknown', 'unknown operation ${q(op.op)}');
  }

  /// Removes a node, refusing one with children or edges unless cascade is
  /// set. The inverse re-adds every removed node and edge at its old
  /// position, in ascending position order.
  List<Op> _removeNode(Op op) {
    if (node(op.id) < 0) _fail('op.missing', 'no node ${goQuote(op.id)}');
    final ix = ModelIndex(result);
    final gone = {op.id, ...ix.descendants(op.id)};
    bool touches(Edge e) => gone.contains(e.from) || gone.contains(e.to);
    final touching = edges.where(touches).length;
    if (!op.cascade && (gone.length > 1 || touching > 0)) {
      _fail('op.not-empty',
          'node ${goQuote(op.id)} has ${gone.length - 1} nested nodes and $touching edges; remove them first or set cascade');
    }
    final inverse = [
      for (var i = 0; i < nodes.length; i++)
        if (gone.contains(nodes[i].id)) Op.nodeAdd(nodes[i], index: i),
      for (var i = 0; i < edges.length; i++)
        if (touches(edges[i])) Op.edgeAdd(edges[i], index: i),
    ];
    nodes.removeWhere((n) => gone.contains(n.id));
    edges.removeWhere(touches);
    return inverse;
  }

  /// The properties and evidence of the node or edge [op] targets, and a
  /// function that writes them back.
  (Properties, List<Evidence>, void Function({Properties? props, List<Evidence>? evidence})) _element(Op op) {
    final q = goQuote;
    switch (op.target) {
      case Ops.targetNode:
        final i = node(op.id);
        if (i < 0) _fail('op.missing', 'no node ${q(op.id)}');
        return (
          nodes[i].properties,
          nodes[i].evidence,
          ({props, evidence}) => nodes[i] = nodes[i].copyWith(properties: props, evidence: evidence),
        );
      case Ops.targetEdge:
        final i = edge(op.id);
        if (i < 0) _fail('op.missing', 'no edge ${q(op.id)}');
        return (
          edges[i].properties,
          edges[i].evidence,
          ({props, evidence}) => edges[i] = edges[i].copyWith(properties: props, evidence: evidence),
        );
    }
    _fail('op.field', '${op.op} target must be node or edge, got ${q(op.target)}');
  }

  List<Op> _prop(Op op) {
    final (props, _, write) = _element(op);
    if (op.key == '') _fail('op.field', '${op.op} needs a key');
    final had = props.containsKey(op.key);
    final inv = had
        ? Op(op: Ops.propSet, target: op.target, id: op.id, key: op.key, value: props[op.key])
        : Op.propUnset(op.target, op.id, op.key);
    if (op.op == Ops.propUnset) {
      if (!had) return const [];
      write(props: {...props}..remove(op.key));
      return [inv];
    }
    if (!isScalarValue(op.value)) _fail('op.field', 'prop.set value must be a string, number or bool');
    write(props: {...props, op.key: op.value});
    return [inv];
  }

  List<Op> _evidence(Op op) {
    final (_, list, write) = _element(op);
    if (op.op == Ops.evidenceRemove) {
      final i = list.indexWhere((e) => e.id == op.evidenceId);
      if (i < 0) {
        _fail('op.missing', '${op.target} ${goQuote(op.id)} has no evidence ${goQuote(op.evidenceId)}');
      }
      write(evidence: [...list]..removeAt(i));
      return [Op.evidenceAdd(op.target, op.id, list[i], index: i)];
    }
    final e = op.evidence ?? _fail('op.field', 'evidence.add needs evidence');
    for (final have in list) {
      if (have.ref == e.ref) return const []; // already cited
      if (e.id != '' && have.id == e.id) {
        _fail('op.exists', '${op.target} ${goQuote(op.id)} already has evidence ${goQuote(e.id)}');
      }
    }
    final next = fillEvidenceIds(_insert([...list], e, op.index));
    write(evidence: next);
    return [Op.evidenceRemove(op.target, op.id, next.firstWhere((x) => x.ref == e.ref).id)];
  }

  List<Op> _putView(Op op) {
    final v = op.view ?? _fail('op.field', 'view.put needs a view');
    final i = views.indexWhere((x) => x.id == v.id);
    if (i >= 0) {
      final old = views[i];
      views[i] = v;
      return [Op.viewPut(old)];
    }
    _insert(views, v, op.index);
    return [Op.viewRemove(v.id)];
  }
}

/// Puts [v] into [list] at [index] (null appends), refusing an index out of
/// range. Returns [list].
List<T> _insert<T>(List<T> list, T v, int? index) {
  if (index == null) return list..add(v);
  if (index < 0 || index > list.length) _fail('op.index', 'index $index is outside 0..${list.length}');
  return list..insert(index, v);
}

// Settable fields (Go edit/fields.go). Each reads the current value as JSON
// and writes a JSON value; JSON null clears.

typedef _Field<T> = ({Object? Function(T) get, T Function(T, Object?) set});

/// Applies op.fields to [el] and returns the result and the inverse
/// operation, which sets every touched field back to its old value.
(T, Op) _setFields<T>(Op op, T el, Map<String, _Field<T>> fields) {
  if (op.fields.isEmpty) _fail('op.field', '${op.op} needs fields');
  final names = sortedKeys(op.fields);
  for (final name in names) {
    if (!fields.containsKey(name)) _fail('op.field', '${op.op} cannot set ${goQuote(name)}');
  }
  final old = <String, Object?>{};
  for (final name in names) {
    final f = fields[name]!;
    old[name] = f.get(el);
    try {
      el = f.set(el, op.fields[name]);
    } on ModelFormatException {
      _fail('op.field', '${op.op} $name: bad value ${canonicalJson(op.fields[name])}');
    }
  }
  return (el, Op(op: op.op, id: op.id, fields: old));
}

const _bad = ModelFormatException('bad value');

_Field<T> _text<T>(String Function(T) get, T Function(T, String) set) =>
    (get: get, set: (el, raw) => set(el, raw == null ? '' : (raw is String ? raw : throw _bad)));

_Field<T> _tags<T>(List<String> Function(T) get, T Function(T, List<String>) set) => (
      get: (el) => get(el).isEmpty ? null : get(el),
      set: (el, raw) => set(
          el,
          raw == null
              ? const []
              : raw is List
                  ? [for (final t in raw) t == null ? '' : (t is String ? t : throw _bad)]
                  : throw _bad),
    );

_Field<T> _flag<T>(bool Function(T) get, T Function(T, bool) set) =>
    (get: get, set: (el, raw) => set(el, raw == null ? false : (raw is bool ? raw : throw _bad)));

final Map<String, _Field<Node>> _nodeFields = {
  'label': _text((n) => n.label, (n, v) => n.copyWith(label: v)),
  'kind': _text((n) => n.kind, (n, v) => n.copyWith(kind: v)),
  'notes': _text((n) => n.notes, (n, v) => n.copyWith(notes: v)),
  'tags': _tags((n) => n.tags, (n, v) => n.copyWith(tags: v)),
  'link': (
    get: (n) => n.link?.toJson(),
    set: (n, raw) => raw == null
        ? n.copyWith(clearLink: true)
        : n.copyWith(link: raw is Map ? readLink(raw, 'link', strict: false) : throw _bad),
  ),
};

final Map<String, _Field<Edge>> _edgeFields = {
  'label': _text((e) => e.label, (e, v) => e.copyWith(label: v)),
  'from': _text((e) => e.from, (e, v) => e.copyWith(from: v)),
  'to': _text((e) => e.to, (e, v) => e.copyWith(to: v)),
  'kind': _text((e) => e.kind, (e, v) => e.copyWith(kind: v)),
  'undirected': _flag((e) => e.undirected, (e, v) => e.copyWith(undirected: v)),
  'notes': _text((e) => e.notes, (e, v) => e.copyWith(notes: v)),
  'tags': _tags((e) => e.tags, (e, v) => e.copyWith(tags: v)),
};

final Map<String, _Field<Model>> _modelFields = {
  'title': _text((m) => m.title, (m, v) => m.copyWith(title: v)),
  'subject': _text((m) => m.subject, (m, v) => m.copyWith(subject: v)),
  'notes': _text((m) => m.notes, (m, v) => m.copyWith(notes: v)),
  'profile': _text((m) => m.profile, (m, v) => m.copyWith(profile: v)),
  'tags': _tags((m) => m.tags, (m, v) => m.copyWith(tags: v)),
};
