// codec.dart: decoding and canonical encoding, ported from Go model/codec.go.

import 'dart:convert';

import 'canonical.dart';
import 'json_read.dart';
import 'model.dart';

/// Go `model.Decode`; see [Model.decode].
Model decodeModel(Object source) {
  Object? json = source;
  if (source is String) {
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw ModelFormatException('invalid model: ${e.message}');
    }
  } else if (source is! Map) {
    throw ModelFormatException('invalid model: cannot decode a ${source.runtimeType}');
  }
  final version = JsonObject(json, 'model', strict: false, fields: const {}).integer('version');
  final Model m;
  switch (version) {
    case 1:
      m = _upgrade(json);
    case modelVersion:
      m = readModel(json, 'model', strict: true);
    default:
      throw ModelFormatException('invalid model: unsupported model version $version (want 1 or $modelVersion)');
  }
  return m.copyWith(
    nodes: [for (final n in m.nodes) n.copyWith(evidence: fillEvidenceIds(n.evidence))],
    edges: [for (final e in m.edges) e.copyWith(evidence: fillEvidenceIds(e.evidence))],
  );
}

/// Go `model.Encode`: canonical JSON at the current format and version.
String encodeModel(Model m) => canonicalJson(m.copyWith(format: modelFormat, version: modelVersion).toJson());

const _modelFields = {'format', 'version', 'title', 'subject', 'notes', 'profile', 'tags', 'nodes', 'edges', 'views'};
const _nodeFields = {'id', 'label', 'parent', 'kind', 'notes', 'tags', 'properties', 'evidence', 'link'};
const _edgeFields = {'id', 'from', 'to', 'label', 'kind', 'undirected', 'notes', 'tags', 'properties', 'evidence'};
const _viewFields = {'id', 'title', 'renderer', 'root', 'collapsed', 'filter', 'positions', 'options'};

Model readModel(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: _modelFields);
  return Model(
    format: o.str('format'),
    version: o.integer('version'),
    title: o.str('title'),
    subject: o.str('subject'),
    notes: o.str('notes'),
    profile: o.str('profile'),
    tags: o.strings('tags'),
    nodes: o.list('nodes', (v, p) => readNode(v, p, strict: strict)),
    edges: o.list('edges', (v, p) => readEdge(v, p, strict: strict)),
    views: o.list('views', (v, p) => readView(v, p, strict: strict)),
  );
}

Node readNode(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: _nodeFields);
  return Node(
    id: o.str('id'),
    label: o.str('label'),
    parent: o.str('parent'),
    kind: o.str('kind'),
    notes: o.str('notes'),
    tags: o.strings('tags'),
    properties: _properties(o),
    evidence: o.list('evidence', (v, p) => readEvidence(v, p, strict: strict)),
    link: o.optional('link', (v, p) => readLink(v, p, strict: strict)),
  );
}

Edge readEdge(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: _edgeFields);
  return Edge(
    id: o.str('id'),
    from: o.str('from'),
    to: o.str('to'),
    label: o.str('label'),
    kind: o.str('kind'),
    undirected: o.flag('undirected'),
    notes: o.str('notes'),
    tags: o.strings('tags'),
    properties: _properties(o),
    evidence: o.list('evidence', (v, p) => readEvidence(v, p, strict: strict)),
  );
}

Evidence readEvidence(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: const {'id', 'caption', 'ref'});
  return Evidence(id: o.str('id'), caption: o.str('caption'), ref: readRef(o.raw('ref'), '$path.ref', strict: strict));
}

Ref readRef(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: const {'scheme', 'id', 'selector'});
  return Ref(scheme: o.str('scheme'), id: o.str('id'), selector: o.str('selector'));
}

Link readLink(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: const {'model', 'node'});
  return Link(model: o.str('model'), node: o.str('node'));
}

View readView(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: _viewFields);
  return View(
    id: o.str('id'),
    title: o.str('title'),
    renderer: o.str('renderer'),
    root: o.str('root'),
    collapsed: o.strings('collapsed'),
    filter: o.optional('filter', (v, p) => readFilter(v, p, strict: strict)),
    positions: o.map('positions', _position),
    options: _properties(o, 'options'),
  );
}

Filter readFilter(Object? json, String path, {required bool strict}) {
  final o = JsonObject(json, path, strict: strict, fields: const {'kinds', 'tags', 'text', 'changedOnly'});
  return Filter(
      kinds: o.strings('kinds'), tags: o.strings('tags'), text: o.str('text'), changedOnly: o.flag('changedOnly'));
}

/// A Go [2]float64: extra elements are dropped, missing ones are 0.
Position _position(Object? v, String path) {
  if (v == null) return (0, 0);
  if (v is! List) throw ModelFormatException('$path: want an array');
  final xy = [for (var i = 0; i < v.length; i++) readNumber(v[i], '$path[$i]')];
  return (xy.isNotEmpty ? xy[0] : 0, xy.length > 1 ? xy[1] : 0);
}

Properties _properties(JsonObject o, [String key = 'properties']) => o.map(key, (v, p) {
      if (v is double && !v.isFinite) throw ModelFormatException('$p: number out of range');
      return v;
    });

// Version 1, the craggy-labs intel graph: read strictly, only to upgrade.

Model _upgrade(Object? json) {
  final g =
      JsonObject(json, 'model', strict: true, fields: const {'version', 'title', 'subject', 'notes', 'nodes', 'edges'});
  List<Evidence> evidence(JsonObject o) => o.list('evidence', (v, p) {
        final e = JsonObject(v, p, strict: true, fields: const {'citation', 'caption'});
        final c = JsonObject(e.raw('citation'), '$p.citation', strict: true, fields: const {'artifactId', 'selector'});
        return Evidence(
            caption: e.str('caption'),
            ref: Ref(scheme: 'artifact', id: c.str('artifactId'), selector: c.str('selector')));
      });
  return Model(
    title: g.str('title'),
    subject: g.str('subject'),
    notes: g.str('notes'),
    nodes: g.list('nodes', (v, p) {
      final n = JsonObject(v, p, strict: true, fields: const {'id', 'label', 'parent', 'notes', 'evidence'});
      return Node(
          id: n.str('id'),
          label: n.str('label'),
          parent: n.str('parent'),
          notes: n.str('notes'),
          evidence: evidence(n));
    }),
    edges: g.list('edges', (v, p) {
      final e = JsonObject(v, p, strict: true, fields: const {'id', 'from', 'to', 'label', 'notes', 'evidence'});
      return Edge(
          id: e.str('id'),
          from: e.str('from'),
          to: e.str('to'),
          label: e.str('label'),
          notes: e.str('notes'),
          evidence: evidence(e));
    }),
  );
}
