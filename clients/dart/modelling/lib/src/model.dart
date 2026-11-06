// model.dart: the block-model format (design §4), ported from Go model/model.go.
// Containment is Node.parent, never an edge. Every element has a stable id.
// All types are immutable values; JSON field names and omit rules follow the
// Go struct tags exactly.

import 'codec.dart';
import 'index.dart';
import 'json_read.dart';
import 'validate.dart';

/// The value of every document's format field.
const modelFormat = 'craggy.model';

/// The format version [Model.encode] writes. [Model.decode] also reads 1.
const modelVersion = 2;

/// An element's typed values: each a String, a num or a bool. Decoded
/// documents may hold other JSON values here; validation refuses them.
typedef Properties = Map<String, Object?>;

/// A graph-renderer position: x, y.
typedef Position = (double, double);

List<T> _list<T>(List<T> l) => List.unmodifiable(l);
Map<String, V> _map<V>(Map<String, V> m) => Map.unmodifiable(m);

/// One complete model document.
class Model extends JsonValue {
  Model({
    this.format = modelFormat,
    this.version = modelVersion,
    required this.title,
    required this.subject,
    this.notes = '',
    this.profile = '',
    List<String> tags = const [],
    List<Node> nodes = const [],
    List<Edge> edges = const [],
    List<View> views = const [],
  })  : tags = _list(tags),
        nodes = _list(nodes),
        edges = _list(edges),
        views = _list(views);

  /// An empty model with the current format and version.
  factory Model.empty(String title, String subject) => Model(title: title, subject: subject);

  /// Reads a model leniently (unknown fields ignored, no upgrade, no
  /// evidence ids filled). Use [Model.decode] for documents.
  factory Model.fromJson(Object? json, {bool strict = false}) => readModel(json, 'model', strict: strict);

  /// Strictly decodes one document (a JSON String or a decoded Map), as Go
  /// `model.Decode`: unknown fields, trailing content and unsupported
  /// versions are refused; version 1 is upgraded; missing evidence ids are
  /// filled. Throws [ModelFormatException]. Does not validate.
  static Model decode(Object source) => decodeModel(source);

  final String format;
  final int version;
  final String title;
  final String subject;
  final String notes;
  final String profile;
  final List<String> tags;
  final List<Node> nodes;
  final List<Edge> edges;
  final List<View> views;

  /// The canonical JSON at the current format and version (Go `model.Encode`).
  String encode() => encodeModel(this);

  /// Validation issues, in Go's order (Go `Model.Issues`).
  List<Issue> issues([Limits limits = const Limits()]) => modelIssues(this, limits);

  /// Throws [ModelValidationException] listing every issue, if any.
  void validate([Limits limits = const Limits()]) {
    final found = issues(limits);
    if (found.isNotEmpty) throw ModelValidationException(found);
  }

  /// A structural index of this model.
  ModelIndex get index => ModelIndex(this);

  /// The node with [id], if any.
  Node? nodeById(String id) => _first(nodes, (n) => n.id == id);

  /// The edge with [id], if any.
  Edge? edgeById(String id) => _first(edges, (e) => e.id == id);

  /// The distinct evidence refs in citation order: nodes first, then edges.
  List<Ref> get refs {
    final out = <Ref>[];
    final seen = <Ref>{};
    for (final e in [for (final n in nodes) ...n.evidence, for (final e in edges) ...e.evidence]) {
      if (seen.add(e.ref)) out.add(e.ref);
    }
    return out;
  }

  Model copyWith({
    String? format,
    int? version,
    String? title,
    String? subject,
    String? notes,
    String? profile,
    List<String>? tags,
    List<Node>? nodes,
    List<Edge>? edges,
    List<View>? views,
  }) =>
      Model(
        format: format ?? this.format,
        version: version ?? this.version,
        title: title ?? this.title,
        subject: subject ?? this.subject,
        notes: notes ?? this.notes,
        profile: profile ?? this.profile,
        tags: tags ?? this.tags,
        nodes: nodes ?? this.nodes,
        edges: edges ?? this.edges,
        views: views ?? this.views,
      );

  @override
  Map<String, Object?> toJson() => {
        'format': format,
        'version': version,
        'title': title,
        'subject': subject,
        if (notes != '') 'notes': notes,
        if (profile != '') 'profile': profile,
        if (tags.isNotEmpty) 'tags': tags,
        'nodes': [for (final n in nodes) n.toJson()],
        'edges': [for (final e in edges) e.toJson()],
        if (views.isNotEmpty) 'views': [for (final v in views) v.toJson()],
      };

  /// Model equality is canonical-encoding equality (Go `model.Equal`).
  @override
  bool operator ==(Object other) => identical(this, other) || (other is Model && encode() == other.encode());

  @override
  int get hashCode => encode().hashCode;
}

T? _first<T>(List<T> list, bool Function(T) test) {
  for (final x in list) {
    if (test(x)) return x;
  }
  return null;
}

/// One area. [parent] names its containing node; "" is top level.
class Node extends JsonValue {
  Node({
    required this.id,
    required this.label,
    this.parent = '',
    this.kind = '',
    this.notes = '',
    List<String> tags = const [],
    Properties properties = const {},
    List<Evidence> evidence = const [],
    this.link,
  })  : tags = _list(tags),
        properties = _map(properties),
        evidence = _list(evidence);

  factory Node.fromJson(Object? json, {bool strict = false}) => readNode(json, 'node', strict: strict);

  final String id;
  final String label;
  final String parent;
  final String kind;
  final String notes;
  final List<String> tags;
  final Properties properties;
  final List<Evidence> evidence;
  final Link? link;

  /// A copy with the given fields replaced; [clearLink] removes the link.
  Node copyWith({
    String? id,
    String? label,
    String? parent,
    String? kind,
    String? notes,
    List<String>? tags,
    Properties? properties,
    List<Evidence>? evidence,
    Link? link,
    bool clearLink = false,
  }) =>
      Node(
        id: id ?? this.id,
        label: label ?? this.label,
        parent: parent ?? this.parent,
        kind: kind ?? this.kind,
        notes: notes ?? this.notes,
        tags: tags ?? this.tags,
        properties: properties ?? this.properties,
        evidence: evidence ?? this.evidence,
        link: clearLink ? null : (link ?? this.link),
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        if (parent != '') 'parent': parent,
        if (kind != '') 'kind': kind,
        if (notes != '') 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (properties.isNotEmpty) 'properties': properties,
        if (evidence.isNotEmpty) 'evidence': [for (final e in evidence) e.toJson()],
        if (link != null) 'link': link!.toJson(),
      };
}

/// One relationship, directed from [from] to [to] unless [undirected].
class Edge extends JsonValue {
  Edge({
    required this.id,
    required this.from,
    required this.to,
    required this.label,
    this.kind = '',
    this.undirected = false,
    this.notes = '',
    List<String> tags = const [],
    Properties properties = const {},
    List<Evidence> evidence = const [],
  })  : tags = _list(tags),
        properties = _map(properties),
        evidence = _list(evidence);

  factory Edge.fromJson(Object? json, {bool strict = false}) => readEdge(json, 'edge', strict: strict);

  final String id;
  final String from;
  final String to;
  final String label;
  final String kind;
  final bool undirected;
  final String notes;
  final List<String> tags;
  final Properties properties;
  final List<Evidence> evidence;

  Edge copyWith({
    String? id,
    String? from,
    String? to,
    String? label,
    String? kind,
    bool? undirected,
    String? notes,
    List<String>? tags,
    Properties? properties,
    List<Evidence>? evidence,
  }) =>
      Edge(
        id: id ?? this.id,
        from: from ?? this.from,
        to: to ?? this.to,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        undirected: undirected ?? this.undirected,
        notes: notes ?? this.notes,
        tags: tags ?? this.tags,
        properties: properties ?? this.properties,
        evidence: evidence ?? this.evidence,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'label': label,
        if (kind != '') 'kind': kind,
        if (undirected) 'undirected': true,
        if (notes != '') 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (properties.isNotEmpty) 'properties': properties,
        if (evidence.isNotEmpty) 'evidence': [for (final e in evidence) e.toJson()],
      };
}

/// One captioned reference supporting a node or edge. [id] is filled on
/// decode (and by edit operations) when empty.
class Evidence extends JsonValue {
  const Evidence({this.id = '', required this.caption, required this.ref});

  factory Evidence.fromJson(Object? json, {bool strict = false}) => readEvidence(json, 'evidence', strict: strict);

  final String id;
  final String caption;
  final Ref ref;

  Evidence copyWith({String? id, String? caption, Ref? ref}) =>
      Evidence(id: id ?? this.id, caption: caption ?? this.caption, ref: ref ?? this.ref);

  @override
  Map<String, Object?> toJson() => {if (id != '') 'id': id, 'caption': caption, 'ref': ref.toJson()};
}

/// Addresses the thing cited: [scheme] says how a host resolves [id]
/// ("artifact", "url", "file" or host-defined); [selector] narrows to a place
/// inside it and is never resolved by this library.
class Ref extends JsonValue {
  const Ref({required this.scheme, required this.id, this.selector = ''});

  factory Ref.fromJson(Object? json, {bool strict = false}) => readRef(json, 'ref', strict: strict);

  final String scheme;
  final String id;
  final String selector;

  Ref copyWith({String? scheme, String? id, String? selector}) =>
      Ref(scheme: scheme ?? this.scheme, id: id ?? this.id, selector: selector ?? this.selector);

  @override
  bool operator ==(Object other) =>
      other is Ref && other.scheme == scheme && other.id == id && other.selector == selector;

  @override
  int get hashCode => Object.hash(scheme, id, selector);

  @override
  Map<String, Object?> toJson() => {'scheme': scheme, 'id': id, if (selector != '') 'selector': selector};
}

/// Makes a node stand for another model (and optionally one of its nodes).
/// The host resolves [model].
class Link extends JsonValue {
  const Link({required this.model, this.node = ''});

  factory Link.fromJson(Object? json, {bool strict = false}) => readLink(json, 'link', strict: strict);

  final String model;
  final String node;

  Link copyWith({String? model, String? node}) => Link(model: model ?? this.model, node: node ?? this.node);

  @override
  Map<String, Object?> toJson() => {'model': model, if (node != '') 'node': node};
}

/// One saved way of looking at the model. Views never change what the model
/// says; renderers ignore fields they don't use.
class View extends JsonValue {
  View({
    required this.id,
    this.title = '',
    required this.renderer,
    this.root = '',
    List<String> collapsed = const [],
    this.filter,
    Map<String, Position> positions = const {},
    Map<String, NodeSize> sizes = const {},
    Properties options = const {},
  })  : collapsed = _list(collapsed),
        positions = _map(positions),
        sizes = _map(sizes),
        options = _map(options);

  factory View.fromJson(Object? json, {bool strict = false}) => readView(json, 'view', strict: strict);

  final String id;
  final String title;
  final String renderer;
  final String root;
  final List<String> collapsed;
  final Filter? filter;
  final Map<String, Position> positions;

  /// Grid sizes by node id (Go `View.Sizes`).
  final Map<String, NodeSize> sizes;
  final Properties options;

  /// A copy with the given fields replaced; [clearFilter] removes the filter.
  View copyWith({
    String? id,
    String? title,
    String? renderer,
    String? root,
    List<String>? collapsed,
    Filter? filter,
    bool clearFilter = false,
    Map<String, Position>? positions,
    Map<String, NodeSize>? sizes,
    Properties? options,
  }) =>
      View(
        id: id ?? this.id,
        title: title ?? this.title,
        renderer: renderer ?? this.renderer,
        root: root ?? this.root,
        collapsed: collapsed ?? this.collapsed,
        filter: clearFilter ? null : (filter ?? this.filter),
        positions: positions ?? this.positions,
        sizes: sizes ?? this.sizes,
        options: options ?? this.options,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        if (title != '') 'title': title,
        'renderer': renderer,
        if (root != '') 'root': root,
        if (collapsed.isNotEmpty) 'collapsed': collapsed,
        if (filter != null) 'filter': filter!.toJson(),
        if (positions.isNotEmpty)
          'positions': {
            for (final e in positions.entries) e.key: [e.value.$1, e.value.$2]
          },
        if (sizes.isNotEmpty) 'sizes': {for (final e in sizes.entries) e.key: e.value.toJson()},
        if (options.isNotEmpty) 'options': options,
      };
}

/// A node's box in a grid layout (Go `model.Size`): [w] tenths of its
/// parent's content width (1–[maxW]) and [h] fixed row units (1–[maxH]).
/// 0 is auto.
class NodeSize extends JsonValue {
  const NodeSize({this.w = 0, this.h = 0});

  factory NodeSize.fromJson(Object? json, {bool strict = false}) => readNodeSize(json, 'size', strict: strict);

  static const maxW = 10;
  static const maxH = 20;

  final int w;
  final int h;

  /// Whether this sets a width or height and each set value is in range
  /// (Go `model.SizeInBounds`).
  bool get inBounds => (w != 0 || h != 0) && w >= 0 && w <= maxW && h >= 0 && h <= maxH;

  NodeSize copyWith({int? w, int? h}) => NodeSize(w: w ?? this.w, h: h ?? this.h);

  @override
  Map<String, Object?> toJson() => {if (w != 0) 'w': w, if (h != 0) 'h': h};
}

/// Narrows the elements shown or searched. Empty fields match all.
class Filter extends JsonValue {
  Filter({List<String> kinds = const [], List<String> tags = const [], this.text = '', this.changedOnly = false})
      : kinds = _list(kinds),
        tags = _list(tags);

  factory Filter.fromJson(Object? json, {bool strict = false}) => readFilter(json, 'filter', strict: strict);

  final List<String> kinds;
  final List<String> tags;
  final String text;
  final bool changedOnly;

  Filter copyWith({List<String>? kinds, List<String>? tags, String? text, bool? changedOnly}) => Filter(
      kinds: kinds ?? this.kinds,
      tags: tags ?? this.tags,
      text: text ?? this.text,
      changedOnly: changedOnly ?? this.changedOnly);

  @override
  Map<String, Object?> toJson() => {
        if (kinds.isNotEmpty) 'kinds': kinds,
        if (tags.isNotEmpty) 'tags': tags,
        if (text != '') 'text': text,
        if (changedOnly) 'changedOnly': true,
      };
}

/// Whether [v] may be a property value: a String, a num or a bool.
bool isScalarValue(Object? v) => v is String || v is num || v is bool;

/// Gives evidence without an id the first free "evN" among the ids already
/// in [evidence] (Go `model.FillEvidenceIDs`).
List<Evidence> fillEvidenceIds(List<Evidence> evidence) {
  if (evidence.every((e) => e.id != '')) return evidence;
  final used = {for (final e in evidence) e.id};
  var next = 1;
  return [
    for (final e in evidence)
      if (e.id != '')
        e
      else
        () {
          while (used.contains('ev$next')) {
            next++;
          }
          used.add('ev$next');
          return e.copyWith(id: 'ev$next');
        }(),
  ];
}
