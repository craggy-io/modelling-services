// grid_drop.dart: where a drag over the grid blocks board would land, and
// the preview of it. The board's one drag target asks GridDragState which
// card is under the pointer (the deepest one, never the dragged card or
// what it holds) and in which zone: an edge places the dragged or new card
// beside it, the middle puts it inside. Each card's grid inserts a
// translucent placeholder at the landing spot, sized like the card it
// stands for, and its siblings reflow around it (GridFlow animates them).
// Dropping applies the drop as one undoable edit.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' show NodeSize;

import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../shared/drag_payloads.dart';
import '../../theme/model_theme.dart';

/// A drop beside or inside the card [target].
@immutable
class GridDrop {
  const GridDrop(this.target, this.zone, {this.refused = false});

  final String target;
  final DropZone zone;

  /// The profile or the tree forbids it; it shows in the error colour and
  /// dropping explains why.
  final bool refused;

  /// Lands beside [target] (rather than inside it).
  bool get beside => zone != DropZone.into;

  @override
  bool operator ==(Object other) =>
      other is GridDrop && other.target == target && other.zone == zone && other.refused == refused;

  @override
  int get hashCode => Object.hash(target, zone, refused);

  @override
  String toString() => 'GridDrop($target, ${zone.name}${refused ? ', refused' : ''})';
}

/// The zone of a pointer at [at] in a card of [size]: its left and top
/// edges place before it, its right and bottom edges after it, the rest
/// inside it.
DropZone gridZoneAt(Offset at, Size size) {
  final across = zoneAt(at.dx, size.width, reorder: true);
  return across != DropZone.into ? across : zoneAt(at.dy, size.height, reorder: true, maxEdge: 24);
}

/// The drag in progress over one grid board: what is dragged, where it
/// would land, and the cards it can land on.
class GridDragState extends ChangeNotifier {
  final _cards = <String, (BuildContext, int)>{};
  BuildContext? _preview;
  Object? _payload;
  GridDrop? _drop;

  /// The rect [_drop]'s card had when it was chosen, before the
  /// placeholder reflowed the grid. Zones are read against it while the
  /// pointer stays inside, so the reflow can't flip the zone under it.
  Rect? _dropRect;
  String? _moving;
  Size? _movingSize;

  /// Where the drag would land, or null (the canvas: the top level).
  GridDrop? get drop => _drop;

  /// The card being dragged, if a card is.
  String? get moving => _moving;

  /// The dragged card's size when the drag began (unzoomed).
  Size? get movingSize => _movingSize;

  /// A card [depth] levels deep can be landed on while it is mounted.
  void register(String id, BuildContext card, int depth) => _cards[id] = (card, depth);

  void unregister(String id, BuildContext card) {
    if (_cards[id]?.$1 == card) _cards.remove(id);
  }

  /// The placeholder, while one is shown: the pointer resting on it keeps
  /// the drop where it is.
  void showPreview(BuildContext context) => _preview = context;

  void hidePreview(BuildContext context) {
    if (_preview == context) _preview = null;
  }

  /// A card drag began.
  void begin(String id, Size size) {
    _moving = id;
    _movingSize = size;
    notifyListeners();
  }

  /// The drag ended, wherever it was dropped.
  void end() {
    if (_moving == null && _payload == null && _drop == null) return;
    _moving = null;
    _movingSize = null;
    _payload = null;
    _drop = null;
    _dropRect = null;
    notifyListeners();
  }

  /// The drag left the board.
  void leave() {
    if (_payload == null && _drop == null) return;
    _payload = null;
    _drop = null;
    _dropRect = null;
    notifyListeners();
  }

  /// [payload] moved to the global point [at].
  void hover(ModelController c, Object payload, Offset at) {
    final next = _target(c, payload, at);
    if (identical(payload, _payload) && next == _drop) return;
    _payload = payload;
    _drop = next;
    if (next == null) _dropRect = null;
    notifyListeners();
  }

  static Rect? _rectOf(BuildContext? context) {
    final box = context != null && context.mounted ? context.findRenderObject() : null;
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  }

  GridDrop? _target(ModelController c, Object payload, Offset at) {
    final drop = _drop, held = _dropRect;
    if (drop != null && (_rectOf(_preview)?.contains(at) ?? false)) return drop;
    final moving = payload is MoveArea ? payload.id : null;
    String? best;
    Rect? bestRect;
    var deepest = -1;
    for (final MapEntry(key: id, value: (card, depth)) in _cards.entries) {
      if (depth <= deepest) continue;
      if (moving != null && (id == moving || c.index.ancestors(id).contains(moving))) continue;
      final rect = _rectOf(card);
      if (rect == null || !rect.contains(at)) continue;
      best = id;
      bestRect = rect;
      deepest = depth;
    }
    // Still over the held card's old rect, and over nothing deeper than
    // it: keep the held card, read against its old rect.
    if (drop != null &&
        held != null &&
        held.contains(at) &&
        (best == null || best == drop.target || c.index.ancestors(drop.target).contains(best))) {
      return _dropAt(c, payload, drop.target, held, at);
    }
    if (best == null) return null;
    _dropRect = bestRect;
    return _dropAt(c, payload, best, bestRect!, at);
  }

  static GridDrop _dropAt(ModelController c, Object payload, String target, Rect rect, Offset at) {
    final zone = payload is ConnectArea ? DropZone.into : gridZoneAt(at - rect.topLeft, rect.size);
    return GridDrop(target, zone, refused: dropRefusal(c, payload, target, zone) != null);
  }

  /// Applies the drop of [payload] (over the canvas of [parent] when no
  /// card is under it) as one undoable edit; [connect] draws a
  /// relationship.
  void apply(ModelController c, Object payload, String parent, void Function(String from, String to) connect) {
    final d = _drop;
    end();
    switch ((payload, d)) {
      case (MoveArea m, null):
        c.reparent(m.id, parent);
      case (AddArea a, null):
        c.addKind(parent, a.kind, label: a.label);
      case (MoveArea m, GridDrop d) when !d.beside:
        c.reparent(m.id, d.target);
      case (MoveArea m, GridDrop d):
        c.moveBeside(m.id, d.target, after: d.zone == DropZone.after);
      case (AddArea a, GridDrop d) when !d.beside:
        c.addKind(d.target, a.kind, label: a.label);
      case (AddArea a, GridDrop d):
        c.addKindBeside(d.target, a.kind, label: a.label, after: d.zone == DropZone.after);
      case (ConnectArea a, GridDrop d):
        connect(a.from, d.target);
      case _:
    }
  }
}

/// Provides the board's [GridDragState] to its cards and grids.
class GridDragScope extends InheritedNotifier<GridDragState> {
  const GridDragScope({super.key, required GridDragState state, required super.child}) : super(notifier: state);

  /// The board's drag state, rebuilding [context] as it changes; null off
  /// a grid board.
  static GridDragState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GridDragScope>()?.notifier;

  /// The board's drag state without depending on it.
  static GridDragState? read(BuildContext context) => context.getInheritedWidgetOfExactType<GridDragScope>()?.notifier;
}

/// The size a placeholder takes in the grid: the dragged card's width in
/// columns (auto for a new card) and its height.
({NodeSize size, double height, bool wide}) previewSize(ModelController c, GridDragState drag, ModelTheme t) {
  final id = drag.moving;
  final size = id == null ? const NodeSize() : c.sizes[id] ?? const NodeSize();
  final height = size.h != 0 ? t.gridHeight(size.h) : drag.movingSize?.height ?? t.gridCardMin;
  return (size: size, height: height, wide: id != null && c.index.children(id).isNotEmpty);
}

/// The translucent stand-in for the dragged card where it would land; it
/// fades and settles in.
class DropPlaceholder extends StatefulWidget {
  const DropPlaceholder({super.key, required this.refused, required this.height});

  final bool refused;

  /// Its least height: the dragged card's.
  final double height;

  @override
  State<DropPlaceholder> createState() => _DropPlaceholderState();
}

class _DropPlaceholderState extends State<DropPlaceholder> {
  GridDragState? _drag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drag = GridDragScope.read(context)?..showPreview(context);
  }

  @override
  void dispose() {
    _drag?.hidePreview(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final colour = widget.refused ? t.lintError : t.focus;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: t.quickDuration(context),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
      ),
      child: Container(
        key: const ValueKey('drop-preview'),
        constraints: BoxConstraints(minHeight: widget.height),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: colour.withValues(alpha: 0.55), width: 1.5),
        ),
      ),
    );
  }
}
