// graph_painter.dart: paints the graph renderer's boxes (compound boxes for
// containment, ghosts dashed in the removed colour) and its relationships
// (palette colour, arrowheads when directed, removed ones dashed), only
// where they cross the part of the drawing in view.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../shared/relationship_row.dart';
import '../../theme/model_theme.dart';
import 'graph_layout.dart';

/// Where a relationship between boxes [a] and [b] starts and ends: on
/// their borders along the line between their centres, or from a
/// container's header down to a box inside it.
(Offset, Offset) edgeEnds(Rect a, Rect b) {
  if (a.contains(b.center) && a.overlaps(b) && a.width * a.height > b.width * b.height) {
    return (Offset(b.center.dx, a.top + GraphMetrics.header), b.topCenter);
  }
  if (b.contains(a.center) && b.width * b.height > a.width * a.height) {
    return (a.topCenter, Offset(a.center.dx, b.top + GraphMetrics.header));
  }
  return (_border(a, b.center), _border(b, a.center));
}

Offset _border(Rect r, Offset toward) {
  final d = toward - r.center;
  if (d == Offset.zero) return r.center;
  final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
  final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
  return r.center + d * math.min(1, math.min(sx, sy));
}

/// A box's fill: its depth's area colour, or a removed tint for a ghost.
Color graphBoxFill(ModelTheme t, GraphBox box) =>
    box.node.ghost ? Color.alphaBlend(t.removed.withValues(alpha: 0.08), t.surface) : t.areaAt(box.node.depth);

class GraphPainter extends CustomPainter {
  GraphPainter({
    required this.controller,
    required this.layout,
    required this.theme,
    required this.origin,
    required this.visible,
  }) : super(repaint: controller.hovered);

  final ModelController controller;
  final GraphLayout layout;
  final ModelTheme theme;

  /// The drawing coordinate at the canvas' top-left.
  final Offset origin;

  /// The part of the drawing in view, in drawing coordinates.
  final Rect visible;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    final t = theme, c = controller;
    final view = visible.inflate(GraphMetrics.margin);
    final selected = c.selection;
    for (final box in layout.boxes.values) {
      if (!box.rect.overlaps(view)) continue;
      final r = RRect.fromRectAndRadius(box.rect, Radius.circular(t.radius));
      final isSelected = selected == ModelElementRef.node(box.id);
      final isFocused = c.focused == box.id;
      canvas.drawRRect(r, Paint()..color = graphBoxFill(t, box));
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..color = box.node.ghost ? t.removed : (isSelected ? t.selectedBorder : (isFocused ? t.focus : t.border))
        ..strokeWidth = isSelected || isFocused ? t.selectedBorderWidth : t.borderWidth;
      if (box.node.ghost) {
        _dashed(canvas, Path()..addRRect(r), border);
      } else {
        canvas.drawRRect(r, border);
      }
      final mark = c.overlay?.marks[box.id];
      if (mark != null) {
        canvas.drawRect(
          Rect.fromLTWH(box.rect.left + t.radius, box.rect.bottom - 3, box.rect.width - 2 * t.radius, 3),
          Paint()..color = mark.color,
        );
      }
    }
    final hovered = c.hovered.value;
    for (final id in layout.edges) {
      final e = c.edgeOrGhost(id)!;
      final a = layout.boxes[e.from]!.rect, b = layout.boxes[e.to]!.rect;
      if (e.from == e.to) continue;
      final (start, end) = edgeEnds(a, b);
      if (!Rect.fromPoints(start, end).inflate(t.arrowSize).overlaps(view)) continue;
      final ghost = c.index.edge(id) == null;
      final strong = hovered == id || selected == ModelElementRef.edge(id) || c.isPinned(id);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = relationshipColour(c, t, id).withValues(alpha: ghost ? 0.6 : 1)
        ..strokeWidth = strong ? t.connectorWidth * 2 : t.connectorWidth;
      final line = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      if (ghost) {
        _dashed(canvas, line, paint);
      } else {
        canvas.drawPath(line, paint);
      }
      if (!e.undirected) _arrow(canvas, start, end, paint);
    }
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint stroke) {
    final d = to - from;
    if (d.distance == 0) return;
    final u = d / d.distance, n = Offset(-u.dy, u.dx);
    final s = theme.arrowSize;
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo((to - u * s + n * s / 2).dx, (to - u * s + n * s / 2).dy)
      ..lineTo((to - u * s - n * s / 2).dx, (to - u * s - n * s / 2).dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..style = PaintingStyle.fill
        ..color = stroke.color,
    );
  }

  void _dashed(Canvas canvas, Path path, Paint paint, {double dash = 6, double gap = 4}) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(GraphPainter old) =>
      old.layout != layout ||
      old.visible != visible ||
      old.origin != origin ||
      old.theme != theme ||
      old.controller != controller;
}
