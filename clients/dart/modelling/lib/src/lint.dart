// lint.dart: likely mistakes and profile violations, ported from Go
// query/lint.go. Rules, their order and severities are shared with Go.

import 'canonical.dart';
import 'index.dart';
import 'model.dart';
import 'profile.dart';

/// How serious a lint finding is.
enum Severity {
  error,
  warning,
  info;

  /// The JSON name.
  String get wire => name;
}

/// One lint result. [rule] is stable and shared with Go.
class Finding {
  const Finding(this.rule, this.element, this.severity, this.message);

  final String rule;
  final String element;
  final Severity severity;
  final String message;

  Map<String, Object?> toJson() => {'rule': rule, 'element': element, 'severity': severity.wire, 'message': message};

  @override
  bool operator ==(Object other) =>
      other is Finding &&
      other.rule == rule &&
      other.element == element &&
      other.severity == severity &&
      other.message == message;

  @override
  int get hashCode => Object.hash(rule, element, severity, message);

  @override
  String toString() => 'Finding($rule, $element, ${severity.wire}: $message)';
}

typedef _Add = void Function(String rule, String element, Severity severity, String message);

/// Checks a valid model for likely mistakes, and against [profile] when
/// given. Findings come in document order (nodes, then edges, then views)
/// and per element in a fixed rule order. Never throws; an invalid model
/// gives whatever findings still make sense.
List<Finding> lint(ModelIndex ix, [Profile? profile]) {
  final m = ix.model;
  final out = <Finding>[];
  void add(String rule, String element, Severity severity, String message) =>
      out.add(Finding(rule, element, severity, message));
  final q = goQuote;

  final siblings = <String, Set<String>>{};
  for (final n in m.nodes) {
    final label = goTrimSpace(n.label).toLowerCase();
    if (!(siblings[ix.parent(n.id)] ??= {}).add(label)) {
      add('label.duplicate-sibling', n.id, Severity.warning,
          '${q(n.id)} has the same label as a sibling (${q(n.label)})');
    }
    if (n.evidence.isEmpty) add('evidence.missing', n.id, Severity.info, '${q(n.id)} cites no evidence');
    if (profile != null) _lintNode(ix, n, profile, add);
  }

  final seen = <String>{};
  for (final e in m.edges) {
    final key = '${e.from}\x00${e.to}\x00${goTrimSpace(e.label).toLowerCase()}\x00${e.kind}';
    if (!seen.add(key)) {
      add('edge.duplicate', e.id, Severity.warning,
          '${q(e.id)} repeats an earlier relationship from ${q(e.from)} to ${q(e.to)}');
    }
    if (e.from != e.to && (ix.ancestors(e.from).contains(e.to) || ix.ancestors(e.to).contains(e.from))) {
      add('edge.ancestor', e.id, Severity.warning,
          '${q(e.id)} joins an area to one that contains it; containment is already the parent field');
    }
    if (e.evidence.isEmpty) add('evidence.missing', e.id, Severity.info, '${q(e.id)} cites no evidence');
    if (profile != null) _lintEdge(ix, e, profile, add);
  }

  for (final v in m.views) {
    final stale = <String>[];
    for (final id in [v.root, ...v.collapsed, ...sortedKeys(v.positions)]) {
      if (ix.node(id) == null && id != '' && !stale.contains(id)) stale.add(id);
    }
    if (stale.isNotEmpty) {
      add('view.stale', v.id, Severity.info, 'view ${q(v.id)} names nodes that no longer exist: ${stale.join(', ')}');
    }
  }
  return out;
}

void _lintNode(ModelIndex ix, Node n, Profile p, _Add add) {
  final q = goQuote;
  final kind = p.nodeKinds[n.kind];
  if (n.kind == '') {
    if (p.requireKinds) {
      add('profile.kind-required', n.id, Severity.error, '${q(n.id)} has no kind; profile ${p.id} requires one');
    }
    return;
  }
  if (kind == null) {
    add('profile.kind-unknown', n.id, Severity.error,
        '${q(n.id)} has kind ${q(n.kind)}, which profile ${p.id} does not declare');
    return;
  }
  final parent = ix.node(ix.parent(n.id));
  if (parent != null) {
    final pk = p.nodeKinds[parent.kind];
    if (pk != null && pk.children.isNotEmpty && !pk.children.contains(n.kind)) {
      add('profile.child', n.id, Severity.error,
          'a ${parent.kind} cannot contain a ${n.kind} (${q(n.id)} in ${q(parent.id)})');
    }
  }
  _lintProperties(n.id, n.properties, kind.properties, add);
}

void _lintEdge(ModelIndex ix, Edge e, Profile p, _Add add) {
  final q = goQuote;
  final kind = p.edgeKinds[e.kind];
  if (e.kind == '') {
    if (p.requireKinds) {
      add('profile.kind-required', e.id, Severity.error, '${q(e.id)} has no kind; profile ${p.id} requires one');
    }
    return;
  }
  if (kind == null) {
    add('profile.kind-unknown', e.id, Severity.error,
        '${q(e.id)} has kind ${q(e.kind)}, which profile ${p.id} does not declare');
    return;
  }
  final from = ix.node(e.from)?.kind ?? '', to = ix.node(e.to)?.kind ?? '';
  if ((kind.from.isNotEmpty && !kind.from.contains(from)) || (kind.to.isNotEmpty && !kind.to.contains(to))) {
    add('profile.edge-ends', e.id, Severity.error,
        'a ${e.kind} relationship cannot run from a ${q(from)} to a ${q(to)}');
  }
  _lintProperties(e.id, e.properties, kind.properties, add);
}

void _lintProperties(String id, Properties have, Map<String, PropertySpec> specs, _Add add) {
  final q = goQuote;
  for (final k in sortedKeys(specs)) {
    if (!have.containsKey(k) && specs[k]!.required) {
      add('profile.property-required', id, Severity.error, '${q(id)} needs property ${q(k)}');
    }
  }
  for (final k in sortedKeys(have)) {
    final spec = specs[k];
    if (spec == null) {
      add('profile.property-unknown', id, Severity.warning,
          '${q(id)} has property ${q(k)}, which its kind does not declare');
      continue;
    }
    final v = have[k];
    if (!_typeMatches(spec.type, v)) {
      add('profile.property-type', id, Severity.error, '${q(id)} property ${q(k)} must be a ${spec.type}');
      continue;
    }
    if (spec.enumValues.isNotEmpty && !spec.enumValues.any((e) => goSprint(e) == goSprint(v))) {
      add('profile.property-enum', id, Severity.error, '${q(id)} property ${q(k)} is not one of the allowed values');
    }
  }
}

bool _typeMatches(String t, Object? v) => switch (v) {
      String _ => t == 'string',
      bool _ => t == 'bool',
      _ => t == 'number' && isScalarValue(v),
    };
