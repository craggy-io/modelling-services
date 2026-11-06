// diff.dart: compares two revisions of a model, ported from Go diff/diff.go.
// Element order and, unless asked for, views are not changes.

import 'canonical.dart';
import 'json_read.dart';
import 'model.dart';

/// How an element differs between base and revision.
enum ChangeKind {
  added,
  removed,
  changed;

  /// The JSON name.
  String get wire => name;
}

/// One field's old and new value, as JSON values. [from] is null for a value
/// that was not set, [to] for one that was cleared. Fields are named as in
/// the document; one property is `properties.<key>`.
class FieldChange {
  const FieldChange(this.field, this.from, this.to);

  final String field;
  final Object? from;
  final Object? to;

  Map<String, Object?> toJson() => {'field': field, if (from != null) 'from': from, if (to != null) 'to': to};

  @override
  bool operator ==(Object other) => other is FieldChange && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}

/// One element that differs. [fields] are set only for [ChangeKind.changed].
class Change {
  Change(this.id, this.kind, [List<FieldChange> fields = const []]) : fields = List.unmodifiable(fields);

  final String id;
  final ChangeKind kind;
  final List<FieldChange> fields;

  Map<String, Object?> toJson() => {
        'id': id,
        'change': kind.wire,
        if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toJson()],
      };

  @override
  bool operator ==(Object other) => other is Change && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}

/// Everything that differs, elements sorted by id.
class ChangeSet {
  ChangeSet({List<FieldChange> model = const [], List<Change> nodes = const [], List<Change> edges = const []})
      : model = List.unmodifiable(model),
        nodes = List.unmodifiable(nodes),
        edges = List.unmodifiable(edges);

  /// Changes to the model's own fields.
  final List<FieldChange> model;
  final List<Change> nodes;
  final List<Change> edges;

  /// Whether nothing differs.
  bool get isEmpty => model.isEmpty && nodes.isEmpty && edges.isEmpty;

  /// The change to node [id], if it differs.
  Change? node(String id) => _find(nodes, id);

  /// The change to edge [id], if it differs.
  Change? edge(String id) => _find(edges, id);

  /// The number of changed elements (nodes and edges).
  int get count => nodes.length + edges.length;

  Map<String, Object?> toJson() => {
        if (model.isNotEmpty) 'model': [for (final f in model) f.toJson()],
        if (nodes.isNotEmpty) 'nodes': [for (final c in nodes) c.toJson()],
        if (edges.isNotEmpty) 'edges': [for (final c in edges) c.toJson()],
      };

  @override
  bool operator ==(Object other) => other is ChangeSet && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}

Change? _find(List<Change> changes, String id) {
  for (final c in changes) {
    if (c.id == id) return c;
  }
  return null;
}

/// The change set from [base] to [revision]. [views] counts changes to saved
/// views as a model change ("views").
ChangeSet compare(Model base, Model revision, {bool views = false}) {
  final f = _Fields()
    ..add('title', base.title, revision.title)
    ..add('subject', base.subject, revision.subject)
    ..add('notes', base.notes, revision.notes)
    ..add('profile', base.profile, revision.profile)
    ..add('tags', base.tags, revision.tags);
  if (views) f.add('views', _json(base.views), _json(revision.views));

  final nodes = _elements(base.nodes, revision.nodes, (n) => n.id, _nodeFields);
  final edges = _elements(base.edges, revision.edges, (e) => e.id, _edgeFields);
  return ChangeSet(model: f.out, nodes: nodes, edges: edges);
}

List<Change> _elements<T>(
    List<T> base, List<T> rev, String Function(T) id, List<FieldChange> Function(T a, T b) fields) {
  final out = <Change>[];
  final baseById = {for (final x in base) id(x): x};
  final revIds = <String>{};
  for (final x in rev) {
    revIds.add(id(x));
    final b = baseById[id(x)];
    if (b == null) {
      out.add(Change(id(x), ChangeKind.added));
    } else {
      final fs = fields(b, x);
      if (fs.isNotEmpty) out.add(Change(id(x), ChangeKind.changed, fs));
    }
  }
  for (final x in base) {
    if (!revIds.contains(id(x))) out.add(Change(id(x), ChangeKind.removed));
  }
  out.sort((a, b) => compareUtf8(a.id, b.id));
  return out;
}

List<FieldChange> _nodeFields(Node a, Node b) => (_Fields()
      ..add('label', a.label, b.label)
      ..add('parent', a.parent, b.parent)
      ..add('kind', a.kind, b.kind)
      ..add('notes', a.notes, b.notes)
      ..add('tags', a.tags, b.tags)
      ..add('link', a.link?.toJson(), b.link?.toJson())
      ..properties(a.properties, b.properties)
      ..add('evidence', _json(a.evidence), _json(b.evidence)))
    .out;

List<FieldChange> _edgeFields(Edge a, Edge b) => (_Fields()
      ..add('label', a.label, b.label)
      ..add('from', a.from, b.from)
      ..add('to', a.to, b.to)
      ..add('kind', a.kind, b.kind)
      ..add('undirected', a.undirected, b.undirected)
      ..add('notes', a.notes, b.notes)
      ..add('tags', a.tags, b.tags)
      ..properties(a.properties, b.properties)
      ..add('evidence', _json(a.evidence), _json(b.evidence)))
    .out;

List<Map<String, Object?>> _json(List<JsonValue> values) => [for (final v in values) v.toJson()];

class _Fields {
  final out = <FieldChange>[];

  /// Records [name] when [from] and [to] encode differently.
  void add(String name, Object? from, Object? to) {
    if (!jsonEquals(from, to)) out.add(FieldChange(name, from, to));
  }

  void properties(Properties a, Properties b) {
    for (final k in sortedKeys({...a, ...b})) {
      add('properties.$k', a[k], b[k]);
    }
  }
}
