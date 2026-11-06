// drag_payloads.dart: what the board, the layers tree and the palette drag
// between each other, and where a drop lands.

import '../controller/model_controller.dart';
import '../controller/model_editing.dart';

/// Dragged to reparent or reorder an area.
class MoveArea {
  const MoveArea(this.id);
  final String id;
}

/// Dragged from an area's connection handle to draw a relationship.
class ConnectArea {
  const ConnectArea(this.from);
  final String from;
}

/// Dragged from the palette to add an area of [kind] ('' for none).
class AddArea {
  const AddArea(this.kind, this.label);
  final String kind;
  final String label;
}

/// Where a drag over an area would land.
enum DropZone { before, into, after }

/// The zone of a drag at [at] along an area [length] long: its outer
/// fifths (at most [maxEdge]) reorder, only for a moved area; the rest
/// moves inside.
DropZone zoneAt(double at, double length, {required bool reorder, double maxEdge = 64}) {
  if (!reorder) return DropZone.into;
  final edge = (length * 0.2).clamp(4.0, maxEdge);
  return at < edge ? DropZone.before : (at > length - edge ? DropZone.after : DropZone.into);
}

/// Why [payload] dropped in [zone] of area [id] would be refused, or null.
String? dropRefusal(ModelController c, Object? payload, String id, DropZone zone) => switch (payload) {
  MoveArea m when zone == DropZone.into => c.reparentRefusal(m.id, id),
  MoveArea m => c.reparentRefusal(m.id, c.index.parent(id)),
  AddArea a when zone == DropZone.into => c.childRefusal(id, a.kind),
  AddArea a => c.childRefusal(c.index.parent(id), a.kind),
  _ => null,
};
