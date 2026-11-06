// model_types.dart: small values shared by the controller, the renderers
// and the host hooks.

import 'package:flutter/widgets.dart';

/// Whether a [ModelElementRef] names an area (node) or a relationship (edge).
enum ModelElementKind {
  node,
  edge;

  /// The `target` value edit operations use.
  String get target => name;
}

/// Names one node or edge by id.
@immutable
class ModelElementRef {
  const ModelElementRef.node(this.id) : kind = ModelElementKind.node;
  const ModelElementRef.edge(this.id) : kind = ModelElementKind.edge;

  final ModelElementKind kind;
  final String id;

  bool get isNode => kind == ModelElementKind.node;

  @override
  bool operator ==(Object other) => other is ModelElementRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}:$id';
}

/// One overlay value on one area: a [badge] text, a colour and an
/// optional 0..1 [value] (a heat level or coverage).
@immutable
class OverlayMark {
  const OverlayMark({this.badge = '', required this.color, this.value});

  final String badge;
  final Color color;
  final double? value;
}

/// Host data drawn on the model without being stored in it (design §7.5):
/// findings per area, gate verdicts, coverage. [legend] maps a label to
/// its colour.
@immutable
class ModelOverlay {
  const ModelOverlay({required this.id, required this.label, this.legend = const {}, required this.marks});

  final String id;
  final String label;
  final Map<String, Color> legend;

  /// Marks by node id.
  final Map<String, OverlayMark> marks;
}
