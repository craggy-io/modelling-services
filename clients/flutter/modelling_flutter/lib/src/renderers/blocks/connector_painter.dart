// connector_painter.dart: draws the hovered and pinned relationships on the
// board: both ends' label chips outlined in the relationship's colour, and
// an elbow connector from a dot at the source to an arrowhead at the
// target (a loop for a self-relationship; down the left gutter when the
// ends are stacked). Ported from labs' _RelationshipPainter.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../controller/model_controller.dart';
import '../../theme/model_theme.dart';

/// Finds the drawn label of an area (or its nearest drawn container) in
/// the diagram's coordinates.
typedef DrawnRect = Rect? Function(String id, RenderBox diagram);

class ConnectorPainter extends CustomPainter {
  ConnectorPainter({required this.controller, required this.diagram, required this.drawn, required this.theme})
    : super(repaint: Listenable.merge([controller, controller.hovered]));

  final ModelController controller;
  final GlobalKey diagram;
  final DrawnRect drawn;
  final ModelTheme theme;

  /// Edge ids currently drawn, for tests and semantics.
  List<String> get active {
    final h = controller.hovered.value;
    return [...controller.pinned, if (h != null && !controller.isPinned(h)) h];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = diagram.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    for (final id in active) {
      final e = controller.edgeOrGhost(id);
      if (e == null) continue;
      final from = drawn(e.from, box), to = drawn(e.to, box);
      if (from == null || to == null) continue;
      _connector(canvas, from, to, theme.paletteAt(controller.slotOf(id)), dashed: controller.index.edge(id) == null);
    }
  }

  void _connector(Canvas canvas, Rect from, Rect to, Color colour, {required bool dashed}) {
    final t = theme;
    final paint = Paint()
      ..color = dashed ? colour.withValues(alpha: 0.6) : colour
      ..strokeWidth = t.connectorWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final outset = t.connectorWidth;
    for (final rect in {from, to}) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(outset), Radius.circular(t.radius)), paint);
    }
    final arm = t.arrowSize * 3;
    if (from == to) {
      final start = from.centerRight + Offset(outset, -t.arrowSize / 2);
      final end = from.centerRight + Offset(outset, t.arrowSize / 2);
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx + arm, start.dy - arm / 2, end.dx + arm, end.dy + arm / 2, end.dx, end.dy),
        paint,
      );
      _head(canvas, colour, end, Offset(-arm, -arm / 2));
      return;
    }
    final Offset start, end;
    final List<Offset> bends;
    if (from.right < to.left || to.right < from.left) {
      // Side by side: elbow between the facing edges.
      final rightward = from.right < to.left;
      start = rightward ? from.centerRight : from.centerLeft;
      end = rightward ? to.centerLeft : to.centerRight;
      final middle = (start.dx + end.dx) / 2;
      bends = [Offset(middle, start.dy), Offset(middle, end.dy)];
    } else {
      // Stacked: run down the gutter left of both labels so the connector
      // never crosses another area's text.
      start = from.centerLeft;
      end = to.centerLeft;
      final gutter = math.max(outset, math.min(start.dx, end.dx) - t.arrowSize * 1.4);
      bends = [Offset(gutter, start.dy), Offset(gutter, end.dy)];
    }
    final points = [start, ...bends, end];
    canvas.drawCircle(start, t.arrowSize * 0.3, Paint()..color = colour);
    for (var i = 0; i + 1 < points.length; i++) {
      if (dashed) {
        _dash(canvas, points[i], points[i + 1], paint);
      } else {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
    _head(canvas, colour, end, end - bends.last);
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final step = theme.arrowSize * 0.6;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += step * 2) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + step, length), paint);
    }
  }

  void _head(Canvas canvas, Color colour, Offset tip, Offset direction) {
    if (direction == Offset.zero) return;
    final back = -direction / direction.distance * theme.arrowSize;
    final side = Offset(-back.dy, back.dx) * .5;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + back.dx + side.dx, tip.dy + back.dy + side.dy)
        ..lineTo(tip.dx + back.dx - side.dx, tip.dy + back.dy - side.dy)
        ..close(),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(ConnectorPainter old) => old.controller != controller || old.theme != theme || old.drawn != drawn;
}
