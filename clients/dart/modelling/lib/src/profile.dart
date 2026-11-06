// profile.dart: the optional metamodel (design §4.3), ported from Go
// model/profile.go. Profile violations are lint findings (query), not
// decode errors.

import 'dart:convert';

import 'canonical.dart';
import 'json_read.dart';
import 'validate.dart';

/// The node and edge kinds a model may use, which kinds may nest in which,
/// where edges may run, and typed properties.
class Profile extends JsonValue {
  Profile({
    required this.id,
    required this.version,
    this.title = '',
    this.requireKinds = false,
    Map<String, NodeKind> nodeKinds = const {},
    Map<String, EdgeKind> edgeKinds = const {},
  })  : nodeKinds = Map.unmodifiable(nodeKinds),
        edgeKinds = Map.unmodifiable(edgeKinds);

  factory Profile.fromJson(Object? json, {bool strict = false}) => _readProfile(json, 'profile', strict);

  /// Strictly decodes one profile (a JSON String or decoded Map) and checks
  /// it (Go `model.DecodeProfile`). Throws [ModelFormatException].
  static Profile decode(Object source) {
    Object? json = source;
    if (source is String) {
      try {
        json = jsonDecode(source);
      } on FormatException catch (e) {
        throw ModelFormatException('invalid model: profile: ${e.message}');
      }
    }
    final p = _readProfile(json, 'profile', true);
    p.check();
    return p;
  }

  final String id;
  final int version;
  final String title;
  final bool requireKinds;
  final Map<String, NodeKind> nodeKinds;
  final Map<String, EdgeKind> edgeKinds;

  /// The name a model uses for this profile: `<id>@<version>`.
  String get ref => '$id@$version';

  /// Throws [ModelFormatException] when the profile names unknown kinds or
  /// property types (Go `Profile.Check`).
  void check() {
    Never fail(String message) => throw ModelFormatException('invalid model: profile $id: $message');
    if (id == '' || version < 1) {
      throw const ModelFormatException('invalid model: profile needs an id and a version >= 1');
    }
    void known(List<String> kinds, String where) {
      for (final k in kinds) {
        if (!nodeKinds.containsKey(k)) fail('$where names unknown node kind ${goQuote(k)}');
      }
    }

    void props(Map<String, PropertySpec> specs, String where) {
      for (final k in sortedKeys(specs)) {
        final t = specs[k]!.type;
        if (t != 'string' && t != 'number' && t != 'bool') {
          fail('$where property ${goQuote(k)} has type ${goQuote(t)} (want string, number or bool)');
        }
      }
    }

    for (final name in sortedKeys(nodeKinds)) {
      if (!validId(name)) fail('invalid node kind ${goQuote(name)}');
      final k = nodeKinds[name]!;
      known(k.children, 'node kind $name children');
      props(k.properties, 'node kind $name');
    }
    for (final name in sortedKeys(edgeKinds)) {
      if (!validId(name)) fail('invalid edge kind ${goQuote(name)}');
      final k = edgeKinds[name]!;
      known(k.from, 'edge kind $name from');
      known(k.to, 'edge kind $name to');
      props(k.properties, 'edge kind $name');
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        if (title != '') 'title': title,
        if (requireKinds) 'requireKinds': true,
        if (nodeKinds.isNotEmpty) 'nodeKinds': {for (final e in nodeKinds.entries) e.key: e.value.toJson()},
        if (edgeKinds.isNotEmpty) 'edgeKinds': {for (final e in edgeKinds.entries) e.key: e.value.toJson()},
      };
}

/// One kind of area. [children] lists the kinds that may nest directly
/// inside it; empty allows any.
class NodeKind extends JsonValue {
  NodeKind({required this.label, List<String> children = const [], Map<String, PropertySpec> properties = const {}})
      : children = List.unmodifiable(children),
        properties = Map.unmodifiable(properties);

  final String label;
  final List<String> children;
  final Map<String, PropertySpec> properties;

  @override
  Map<String, Object?> toJson() => {
        'label': label,
        if (children.isNotEmpty) 'children': children,
        if (properties.isNotEmpty) 'properties': _specsJson(properties),
      };
}

/// One kind of relationship. [from] and [to] list the node kinds it may join;
/// empty allows any.
class EdgeKind extends JsonValue {
  EdgeKind({
    required this.label,
    List<String> from = const [],
    List<String> to = const [],
    this.undirected = false,
    Map<String, PropertySpec> properties = const {},
  })  : from = List.unmodifiable(from),
        to = List.unmodifiable(to),
        properties = Map.unmodifiable(properties);

  final String label;
  final List<String> from;
  final List<String> to;
  final bool undirected;
  final Map<String, PropertySpec> properties;

  @override
  Map<String, Object?> toJson() => {
        'label': label,
        if (from.isNotEmpty) 'from': from,
        if (to.isNotEmpty) 'to': to,
        if (undirected) 'undirected': true,
        if (properties.isNotEmpty) 'properties': _specsJson(properties),
      };
}

/// Types one property. [type] is "string", "number" or "bool".
class PropertySpec extends JsonValue {
  PropertySpec({required this.type, this.label = '', List<Object?> enumValues = const [], this.required = false})
      : enumValues = List.unmodifiable(enumValues);

  final String type;
  final String label;

  /// The allowed values (JSON `enum`); empty allows any.
  final List<Object?> enumValues;
  final bool required;

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        if (label != '') 'label': label,
        if (enumValues.isNotEmpty) 'enum': enumValues,
        if (required) 'required': true,
      };
}

Map<String, Object?> _specsJson(Map<String, PropertySpec> specs) =>
    {for (final e in specs.entries) e.key: e.value.toJson()};

Profile _readProfile(Object? json, String path, bool strict) {
  final o = JsonObject(json, path,
      strict: strict, fields: const {'id', 'version', 'title', 'requireKinds', 'nodeKinds', 'edgeKinds'});
  return Profile(
    id: o.str('id'),
    version: o.integer('version'),
    title: o.str('title'),
    requireKinds: o.flag('requireKinds'),
    nodeKinds: o.map('nodeKinds', (v, p) {
      final k = JsonObject(v, p, strict: strict, fields: const {'label', 'children', 'properties'});
      return NodeKind(label: k.str('label'), children: k.strings('children'), properties: _specs(k, strict));
    }),
    edgeKinds: o.map('edgeKinds', (v, p) {
      final k = JsonObject(v, p, strict: strict, fields: const {'label', 'from', 'to', 'undirected', 'properties'});
      return EdgeKind(
          label: k.str('label'),
          from: k.strings('from'),
          to: k.strings('to'),
          undirected: k.flag('undirected'),
          properties: _specs(k, strict));
    }),
  );
}

Map<String, PropertySpec> _specs(JsonObject kind, bool strict) => kind.map('properties', (v, p) {
      final s = JsonObject(v, p, strict: strict, fields: const {'type', 'label', 'enum', 'required'});
      return PropertySpec(
          type: s.str('type'),
          label: s.str('label'),
          enumValues: s.list('enum', (v, _) => v),
          required: s.flag('required'));
    });
