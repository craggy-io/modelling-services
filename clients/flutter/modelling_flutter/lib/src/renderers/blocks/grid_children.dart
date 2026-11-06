// grid_children.dart: an area's children on the 10-column grid, sized from
// the active view's `sizes`. In edit mode each child has resize handles on
// its right edge, bottom edge and corner: they snap to tenths and rows,
// show the size while dragging, and write one undoable `view.put` on
// release; double-clicking a handle returns the child to auto. While a
// drag would land beside one of the children, a placeholder of the
// dragged card's size takes its place in the grid and the children
// reflow around it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' show NodeSize;

import '../../controller/model_controller.dart';
import '../../theme/model_theme.dart';
import 'area_box.dart';
import 'blocks_layout.dart';
import '../../shared/drag_payloads.dart';
import 'grid_area.dart';
import 'grid_drop.dart';
import 'grid_layout.dart';

/// Which edge of a child a resize handle drags.
enum ResizeEdge { right, bottom, corner }

/// The size readout while resizing: "40% · 3 rows" ("auto" when unset).
String sizeReadout(NodeSize s) =>
    [s.w == 0 ? 'auto' : '${s.w * 10}%', s.h == 0 ? 'auto' : '${s.h} ${s.h == 1 ? 'row' : 'rows'}'].join(' · ');

/// How many auto children may share a row [width] wide: the theme's
/// [ModelTheme.gridAutoColumns], fewer when they would be narrower than
/// [ModelTheme.gridMinWidth].
int autoColumnsFor(double width, ModelTheme t) =>
    ((width + t.gap) / (t.gridMinWidth + t.gap)).floor().clamp(1, t.gridAutoColumns);

class GridChildren extends StatefulWidget {
  const GridChildren({super.key, required this.areas, required this.board, required this.depth});

  final List<BlockArea> areas;
  final BlocksBoardHandle board;
  final int depth;

  @override
  State<GridChildren> createState() => _GridChildrenState();
}

class _GridChildrenState extends State<GridChildren> with TickerProviderStateMixin {
  String? _resizing;
  NodeSize _preview = const NodeSize();
  late Size _start;
  late NodeSize _startSize;
  var _delta = Offset.zero;

  ModelController get _c => widget.board.controller;

  NodeSize _sizeOf(String? id) =>
      id == null ? const NodeSize() : (id == _resizing ? _preview : _c.sizes[id] ?? const NodeSize());

  void _begin(String id, BuildContext cell) {
    final box = cell.findRenderObject() as RenderBox;
    setState(() {
      _resizing = id;
      _start = box.size;
      _startSize = _c.sizes[id] ?? const NodeSize();
      _preview = _startSize;
      _delta = Offset.zero;
    });
  }

  void _drag(ResizeEdge edge, Offset by, double width, ModelTheme t) {
    _delta += by;
    final w = spanFor(_start.width + _delta.dx, width, t.gap);
    final h = ((_start.height + _delta.dy + t.gap) / (t.gridRow + t.gap)).round().clamp(t.gridMinRows, NodeSize.maxH);
    setState(
      () => _preview = NodeSize(
        w: edge == ResizeEdge.bottom ? _startSize.w : w,
        h: edge == ResizeEdge.right ? _startSize.h : h,
      ),
    );
  }

  void _end() {
    final id = _resizing;
    if (id == null) return;
    final next = _preview;
    setState(() => _resizing = null);
    if (next != _startSize) _c.setSizes({id: next});
  }

  void _reset(String id) {
    if (_c.sizes.containsKey(id)) _c.setSizes({id: null});
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final drag = GridDragScope.of(context);
    final drop = drag?.drop;
    final ids = {for (final a in widget.areas) a.id};
    // The drop preview, when the drag would land beside one of these.
    final at = drop == null || !drop.beside || !ids.contains(drop.target)
        ? -1
        : widget.areas.indexWhere((a) => a.id == drop.target) + (drop.zone == DropZone.after ? 1 : 0);
    final preview = at < 0 ? null : previewSize(_c, drag!, t);
    final sizes = [for (final a in widget.areas) _sizeOf(a.id)];
    final widths = [for (final s in sizes) s.w == 0 ? null : s.w];
    final heights = [for (final s in sizes) s.h == 0 ? null : t.gridHeight(s.h)];
    final wide = [for (final a in widget.areas) a.childCount > 0];
    if (preview != null) {
      widths.insert(at, preview.size.w == 0 ? null : preview.size.w);
      // As tall as the dragged card at least, and as its row: no gap
      // under it for the pointer to fall through.
      heights.insert(at, preview.size.h == 0 ? null : preview.height);
      wide.insert(at, preview.wide);
    }
    return LayoutBuilder(
      builder: (context, bounds) => CustomPaint(
        painter: _resizing == null ? null : _ColumnGuides(colour: t.focus.withValues(alpha: 0.06), gap: t.gap),
        child: GridFlow(
          slots: packGrid(widths, autoColumns: autoColumnsFor(bounds.maxWidth, t), wide: wide),
          heights: heights,
          gap: t.gap,
          vsync: this,
          duration: t.quickDuration(context),
          children: [
            for (var i = 0; i < widget.areas.length; i++) ...[
              if (i == at)
                DropPlaceholder(key: const ValueKey('drop-cell'), refused: drop!.refused, height: preview!.height),
              KeyedSubtree(
                key: ValueKey('cell-${widget.areas[i].id}'),
                child: _cell(context, t, widget.areas[i], sizes[i].h != 0, bounds.maxWidth),
              ),
            ],
            if (at == widget.areas.length)
              DropPlaceholder(key: const ValueKey('drop-cell'), refused: drop!.refused, height: preview!.height),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ModelTheme t, BlockArea area, bool fixed, double width) {
    final id = area.id!;
    final box = GridAreaBox(area: area, board: widget.board, depth: widget.depth, clip: fixed);
    if (_c.readOnly || area.ghost) return box;
    return Builder(
      builder: (cell) => Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          box,
          for (final edge in ResizeEdge.values) _handle(cell, t, id, edge, width),
          if (_resizing == id)
            Positioned(
              right: t.spacing.xs,
              bottom: t.spacing.xs,
              child: IgnorePointer(child: _Readout(text: sizeReadout(_preview))),
            ),
        ],
      ),
    );
  }

  Widget _handle(BuildContext cell, ModelTheme t, String id, ResizeEdge edge, double width) {
    const thick = 8.0, corner = 14.0;
    final cursor = switch (edge) {
      ResizeEdge.right => SystemMouseCursors.resizeLeftRight,
      ResizeEdge.bottom => SystemMouseCursors.resizeUpDown,
      ResizeEdge.corner => SystemMouseCursors.resizeDownRight,
    };
    return Positioned(
      key: ValueKey('resize-${edge.name}-$id'),
      right: edge == ResizeEdge.bottom ? corner : 0,
      bottom: edge == ResizeEdge.right ? corner : 0,
      top: edge == ResizeEdge.right ? 0 : null,
      left: edge == ResizeEdge.bottom ? 0 : null,
      width: edge == ResizeEdge.bottom ? null : (edge == ResizeEdge.corner ? corner : thick),
      height: edge == ResizeEdge.right ? null : (edge == ResizeEdge.corner ? corner : thick),
      child: Semantics(
        label: 'Resize ${edge.name}',
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => _begin(id, cell),
            onPanUpdate: (d) => _drag(edge, d.delta, width, t),
            onPanEnd: (_) => _end(),
            onPanCancel: () => setState(() => _resizing = null),
            onDoubleTap: () => _reset(id),
            child: _resizing == id && edge == ResizeEdge.corner ? _Grip(colour: t.focus) : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// A small corner mark on the child being resized.
class _Grip extends StatelessWidget {
  const _Grip({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

/// The live size pill shown while resizing.
class _Readout extends StatelessWidget {
  const _Readout({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Container(
      key: const ValueKey('resize-readout'),
      padding: EdgeInsets.symmetric(horizontal: t.spacing.xs, vertical: t.spacing.xxs / 2),
      decoration: BoxDecoration(
        color: t.focus,
        borderRadius: BorderRadius.circular(t.radius),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Text(
        text,
        style: t.small.copyWith(color: t.surface, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Faint column bands behind the grid while a child is being resized.
class _ColumnGuides extends CustomPainter {
  const _ColumnGuides({required this.colour, required this.gap});

  final Color colour;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final column = spanWidth(1, size.width, gap);
    for (var i = 0; i < gridColumns; i++) {
      final x = i * (column + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, column, size.height), const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnGuides old) => old.colour != colour || old.gap != gap;
}
