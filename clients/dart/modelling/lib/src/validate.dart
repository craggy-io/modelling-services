// validate.dart: structure and bounds checks, ported from Go model/validate.go.
// Issue codes and their order are shared with Go.

import 'canonical.dart';
import 'model.dart';

/// Bounds on one model. Hosts may tighten them; zero (or negative) fields
/// take the default.
class Limits {
  const Limits({
    this.maxBytes = 0,
    this.maxNodes = 0,
    this.maxEdges = 0,
    this.maxRefs = 0,
    this.maxDepth = 0,
    this.maxProperties = 0,
    this.maxValueBytes = 0,
    this.maxViews = 0,
  });

  /// The bounds craggy-labs has always applied to models.
  static const defaults = Limits(
      maxBytes: 512 << 10,
      maxNodes: 1000,
      maxEdges: 2000,
      maxRefs: 128,
      maxDepth: 32,
      maxProperties: 32,
      maxValueBytes: 1024,
      maxViews: 32);

  /// Encoded document size in bytes.
  final int maxBytes;
  final int maxNodes;
  final int maxEdges;

  /// Distinct evidence refs.
  final int maxRefs;

  /// Containment depth; top-level nodes are depth 1.
  final int maxDepth;

  /// Properties per element.
  final int maxProperties;

  /// Bytes per string property value.
  final int maxValueBytes;
  final int maxViews;

  /// These limits with every unset field taken from [defaults].
  Limits withDefaults() {
    int pick(int v, int d) => v > 0 ? v : d;
    const d = defaults;
    return Limits(
      maxBytes: pick(maxBytes, d.maxBytes),
      maxNodes: pick(maxNodes, d.maxNodes),
      maxEdges: pick(maxEdges, d.maxEdges),
      maxRefs: pick(maxRefs, d.maxRefs),
      maxDepth: pick(maxDepth, d.maxDepth),
      maxProperties: pick(maxProperties, d.maxProperties),
      maxValueBytes: pick(maxValueBytes, d.maxValueBytes),
      maxViews: pick(maxViews, d.maxViews),
    );
  }
}

/// One validation failure. [code] is stable and shared with Go; [element] is
/// the node, edge or view id concerned ("" for the model itself).
class Issue {
  const Issue(this.code, this.element, this.message);

  final String code;
  final String element;
  final String message;

  Map<String, Object?> toJson() => {'code': code, if (element != '') 'element': element, 'message': message};

  @override
  bool operator ==(Object other) =>
      other is Issue && other.code == code && other.element == element && other.message == message;

  @override
  int get hashCode => Object.hash(code, element, message);

  @override
  String toString() => 'Issue($code, $element: $message)';
}

/// A model that failed validation: every issue, in document order.
class ModelValidationException implements Exception {
  ModelValidationException(List<Issue> issues) : issues = List.unmodifiable(issues);

  final List<Issue> issues;

  /// Go's ValidationError text.
  String get message => 'invalid model: ${issues.map((i) => i.message).join('; ')}';

  @override
  String toString() => 'ModelValidationException: $message';
}

final _identifier = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$');
final _propertyKey = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$');
final _scheme = RegExp(r'^[a-z][a-z0-9+.-]{0,31}$');
final _renderer = RegExp(r'^[a-z][a-z0-9-]{0,31}$');

/// Whether [s] is a valid node, edge, evidence, view or kind id.
bool validId(String s) => _identifier.hasMatch(s);

typedef _Add = void Function(String code, String element, String message);

/// Go `Model.Issues`; see [Model.issues].
List<Issue> modelIssues(Model m, Limits limits) {
  final l = limits.withDefaults();
  final out = <Issue>[];
  void add(String code, String element, String message) => out.add(Issue(code, element, message));
  final q = goQuote;

  if (m.format != modelFormat) add('format', '', 'format must be ${q(modelFormat)}, got ${q(m.format)}');
  if (m.version != modelVersion) add('version', '', 'version must be $modelVersion, got ${m.version}');
  if (goTrimSpace(m.title) == '') add('title', '', 'title is required');
  if (goTrimSpace(m.subject) == '') add('subject', '', 'subject is required');
  final size = utf8Length(canonicalJson(m.toJson()));
  if (size > l.maxBytes) add('size', '', 'model is $size bytes (max ${l.maxBytes})');
  if (m.nodes.length > l.maxNodes) add('bounds.nodes', '', '${m.nodes.length} nodes (max ${l.maxNodes})');
  if (m.edges.length > l.maxEdges) add('bounds.edges', '', '${m.edges.length} edges (max ${l.maxEdges})');
  _checkTags(m.tags, '', add);

  final nodes = <String>{};
  for (final n in m.nodes) {
    if (!validId(n.id)) {
      add('id.invalid', n.id, 'node id ${q(n.id)} is not a valid id');
    } else if (nodes.contains(n.id)) {
      add('id.duplicate', n.id, 'node id ${q(n.id)} is used twice');
    }
    nodes.add(n.id);
    if (goTrimSpace(n.label) == '') add('label.empty', n.id, 'node ${q(n.id)} has no label');
    _checkElement(n.id, n.kind, n.tags, n.properties, n.evidence, l, add);
    if (n.link != null && goTrimSpace(n.link!.model) == '') {
      add('link.model', n.id, 'node ${q(n.id)} links to no model');
    }
  }
  final parents = <String, String>{};
  for (final n in m.nodes) {
    if (n.parent == '') {
    } else if (n.parent == n.id) {
      add('parent.self', n.id, 'node ${q(n.id)} contains itself');
    } else if (!nodes.contains(n.parent)) {
      add('parent.missing', n.id, "node ${q(n.id)}'s parent ${q(n.parent)} is not a node");
    } else {
      parents[n.id] = n.parent;
    }
  }
  for (final n in m.nodes) {
    var depth = 1, cyclic = false, loops = false;
    final seen = {n.id};
    for (var p = parents[n.id] ?? ''; p != ''; p = parents[p] ?? '') {
      if (seen.contains(p)) {
        cyclic = p == n.id;
        loops = true;
        break;
      }
      seen.add(p);
      depth++;
    }
    if (loops && !cyclic) continue; // an ancestor's cycle, reported on its members
    if (cyclic) {
      add('parent.cycle', n.id, 'node ${q(n.id)} is inside its own containment cycle');
    } else if (depth > l.maxDepth) {
      add('bounds.depth', n.id, 'node ${q(n.id)} is nested $depth deep (max ${l.maxDepth})');
    }
  }

  final edges = <String>{};
  for (final e in m.edges) {
    if (!validId(e.id)) {
      add('id.invalid', e.id, 'edge id ${q(e.id)} is not a valid id');
    } else if (edges.contains(e.id)) {
      add('id.duplicate', e.id, 'edge id ${q(e.id)} is used twice');
    }
    edges.add(e.id);
    if (!nodes.contains(e.from) || !nodes.contains(e.to)) {
      add('edge.endpoint', e.id, 'edge ${q(e.id)} must join two nodes (from ${q(e.from)}, to ${q(e.to)})');
    }
    if (goTrimSpace(e.label) == '') add('label.empty', e.id, 'edge ${q(e.id)} has no label');
    _checkElement(e.id, e.kind, e.tags, e.properties, e.evidence, l, add);
  }
  final refs = m.refs.length;
  if (refs > l.maxRefs) add('bounds.refs', '', '$refs distinct evidence refs (max ${l.maxRefs})');

  if (m.views.length > l.maxViews) add('bounds.views', '', '${m.views.length} views (max ${l.maxViews})');
  final views = <String>{};
  for (final v in m.views) {
    if (!validId(v.id) || views.contains(v.id)) add('view.id', v.id, 'view id ${q(v.id)} is invalid or used twice');
    views.add(v.id);
    if (!_renderer.hasMatch(v.renderer)) {
      add('view.renderer', v.id, 'view ${q(v.id)} has an invalid renderer ${q(v.renderer)}');
    }
    for (final id in sortedKeys(v.sizes)) {
      final sz = v.sizes[id]!;
      if (!validId(id) || !sz.inBounds) {
        add('view.size', v.id,
            'view ${q(v.id)} has an invalid size for ${q(id)} (w ${sz.w} of 1–${NodeSize.maxW}, h ${sz.h} of 1–${NodeSize.maxH})');
      }
    }
    _checkProperties(v.id, v.options, l, add);
  }
  return out;
}

void _checkElement(
    String id, String kind, List<String> tags, Properties props, List<Evidence> evidence, Limits l, _Add add) {
  final q = goQuote;
  if (kind != '' && !validId(kind)) add('kind.invalid', id, '${q(id)} has an invalid kind ${q(kind)}');
  _checkTags(tags, id, add);
  _checkProperties(id, props, l, add);
  final seen = <String>{};
  for (final e in evidence) {
    if (!validId(e.id) || seen.contains(e.id)) {
      add('evidence.id', id, '${q(id)} has evidence with an invalid or repeated id ${q(e.id)}');
    }
    seen.add(e.id);
    if (goTrimSpace(e.caption) == '') add('evidence.caption', id, '${q(id)} has evidence ${q(e.id)} with no caption');
    if (!_scheme.hasMatch(e.ref.scheme) || goTrimSpace(e.ref.id) == '') {
      add('evidence.ref', id,
          '${q(id)} has evidence ${q(e.id)} without a valid ref (scheme ${q(e.ref.scheme)}, id ${q(e.ref.id)})');
    }
  }
}

void _checkTags(List<String> tags, String id, _Add add) {
  final seen = <String>{};
  for (final t in tags) {
    if (goTrimSpace(t) == '' || seen.contains(t)) {
      add('tag.invalid', id, '${goQuote(id)} has an empty or repeated tag ${goQuote(t)}');
    }
    seen.add(t);
  }
}

void _checkProperties(String id, Properties props, Limits l, _Add add) {
  final q = goQuote;
  if (props.length > l.maxProperties) {
    add('bounds.properties', id, '${q(id)} has ${props.length} properties (max ${l.maxProperties})');
  }
  for (final k in sortedKeys(props)) {
    final v = props[k];
    if (!_propertyKey.hasMatch(k)) add('property.key', id, '${q(id)} has an invalid property key ${q(k)}');
    if (!isScalarValue(v)) {
      add('property.value', id, '${q(id)} property ${q(k)} must be a string, number or bool');
    } else if (v is String && utf8Length(v) > l.maxValueBytes) {
      add('property.value', id, '${q(id)} property ${q(k)} is ${utf8Length(v)} bytes (max ${l.maxValueBytes})');
    }
  }
}
