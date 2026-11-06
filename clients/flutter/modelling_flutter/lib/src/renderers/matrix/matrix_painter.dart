// matrix_painter.dart: paints the matrix grid in view: column numbers, the
// diagonal, containment blocks, the selected area's row and column, cell
// fills (split by relationship kind when the profile declares kinds) and a
// change corner on cells whose relationships differ from the base.

import 'package:flutter/rendering.dart';
import 'package:modelling/modelling.dart' hide View;

import '../../controller/model_controller.dart';
import '../../shared/markers.dart';
import '../../shared/relationship_row.dart';
import '../../theme/model_theme.dart';
import 'matrix_layout.dart';

class MatrixPainter extends CustomPainter {
  MatrixPainter({
    required this.controller,
    required this.layout,
    required this.theme,
    required this.visible,
    required this.picked,
  });

  final ModelController controller;
  final MatrixLayout layout;
  final ModelTheme theme;
  final Rect visible;

  /// The cell whose relationships are listed, if any.
  final MatrixCell? picked;

  @override
  void paint(Canvas canvas, Size size) {
    final t = theme, c = controller, n = layout.nodes.length;
    if (n == 0) return;
    final (r0, r1, c0, c1) = layout.range(visible);
    final grid = Rect.fromLTRB(
      MatrixMetrics.header,
      MatrixMetrics.top,
      MatrixMetrics.header + n * MatrixMetrics.cell,
      MatrixMetrics.top + n * MatrixMetrics.cell,
    );
    canvas.drawRect(grid, Paint()..color = t.surface);

    // The selected area's row and column.
    final sel = c.selection;
    final at = sel != null && sel.isNode ? layout.nodes.indexWhere((x) => x.id == sel.id) : -1;
    if (at >= 0) {
      final band = Paint()..color = t.hover;
      canvas.drawRect(Rect.fromLTRB(0, layout.rowHeader(at).top, grid.right, layout.rowHeader(at).bottom), band);
      final col = layout.cellRect(0, at);
      canvas.drawRect(Rect.fromLTRB(col.left, 0, col.right, grid.bottom), band);
    }

    for (var i = r0; i <= r1 && i < n; i++) {
      if (i >= c0 && i <= c1) canvas.drawRect(layout.cellRect(i, i), Paint()..color = t.raised);
    }

    final line = Paint()
      ..color = t.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = r0; i <= r1 + 1 && i <= n; i++) {
      final y = MatrixMetrics.top + i * MatrixMetrics.cell;
      canvas.drawLine(Offset(0, y), Offset(grid.right, y), line);
    }
    for (var j = c0; j <= c1 + 1 && j <= n; j++) {
      final x = MatrixMetrics.header + j * MatrixMetrics.cell;
      canvas.drawLine(Offset(x, 0), Offset(x, grid.bottom), line);
    }

    // Column numbers.
    final text = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    for (var j = c0; j <= c1 && j < n; j++) {
      text.text = TextSpan(text: '${j + 1}', style: t.small);
      text.layout(minWidth: MatrixMetrics.cell, maxWidth: MatrixMetrics.cell);
      final x = MatrixMetrics.header + j * MatrixMetrics.cell;
      text.paint(canvas, Offset(x, (MatrixMetrics.top - text.height) / 2));
    }
    text.dispose();

    // Cells.
    final byKind = c.profile != null && c.profile!.edgeKinds.isNotEmpty;
    for (final entry in layout.cells.entries) {
      final cell = entry.key;
      if (cell.row < r0 || cell.row > r1 || cell.column < c0 || cell.column > c1) continue;
      final r = layout.cellRect(cell.row, cell.column).deflate(2);
      final ids = entry.value;
      if (byKind) {
        final colours = <Color>[for (final id in ids) relationshipColour(c, t, id)];
        final w = r.width / colours.length;
        for (var k = 0; k < colours.length; k++) {
          canvas.drawRect(
            Rect.fromLTWH(r.left + k * w, r.top, w, r.height),
            Paint()..color = colours[k].withValues(alpha: 0.45),
          );
        }
      } else {
        final strength = (0.25 + 0.15 * ids.length).clamp(0, 0.8).toDouble();
        canvas.drawRect(r, Paint()..color = t.focus.withValues(alpha: strength));
      }
      final change = _change(ids);
      if (change != null) {
        final corner = Path()
          ..moveTo(r.right - 10, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.top + 10)
          ..close();
        canvas.drawPath(corner, Paint()..color = changeColour(t, change));
      }
    }

    // Containment blocks on the diagonal.
    final block = Paint()
      ..style = PaintingStyle.stroke
      ..color = t.border
      ..strokeWidth = t.borderWidth;
    for (final (i, j) in layout.spans) {
      if (j < r0 || i > r1 || j < c0 || i > c1) continue;
      canvas.drawRect(layout.cellRect(i, i).expandToInclude(layout.cellRect(j, j)), block);
    }

    final p = picked;
    if (p != null) {
      canvas.drawRect(
        layout.cellRect(p.row, p.column),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = t.selectedBorder
          ..strokeWidth = t.selectedBorderWidth,
      );
    }
  }

  /// The change shown on a cell: removed, then added, then changed.
  ChangeKind? _change(List<String> ids) {
    final kinds = {for (final id in ids) ?controller.diff.edgeChange(id)};
    for (final k in const [ChangeKind.removed, ChangeKind.added, ChangeKind.changed]) {
      if (kinds.contains(k)) return k;
    }
    return null;
  }

  @override
  bool shouldRepaint(MatrixPainter old) =>
      old.layout != layout || old.visible != visible || old.picked != picked || old.theme != theme;
}
