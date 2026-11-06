// matrix_layout.dart: the matrix (DSM) renderer's grid: one row and one
// column per shown area in containment order, the relationships in each
// cell (row → column; undirected ones both ways), and the blocks each
// containing area spans on the diagonal.

import 'package:flutter/painting.dart';

import '../../controller/model_controller.dart';
import '../../shared/shown_elements.dart';

/// Sizes the matrix draws with.
class MatrixMetrics {
  const MatrixMetrics._();

  static const header = 260.0;
  static const top = 32.0;
  static const cell = 32.0;
}

/// One cell: the relationships from [row] to [column].
typedef MatrixCell = ({int row, int column});

class MatrixLayout {
  MatrixLayout._(this.nodes, this.cells, this.spans);

  /// Rows (and columns), in containment order.
  final List<ShownNode> nodes;

  /// Relationship ids by cell, for cells that have any.
  final Map<MatrixCell, List<String>> cells;

  /// For each area with shown contents: its row and its last
  /// descendant's row.
  final List<(int, int)> spans;

  Size get size => Size(
    MatrixMetrics.header + nodes.length * MatrixMetrics.cell,
    MatrixMetrics.top + nodes.length * MatrixMetrics.cell,
  );

  /// Row [i]'s header, in drawing coordinates.
  Rect rowHeader(int i) =>
      Rect.fromLTWH(0, MatrixMetrics.top + i * MatrixMetrics.cell, MatrixMetrics.header, MatrixMetrics.cell);

  /// A cell's rect, in drawing coordinates.
  Rect cellRect(int row, int column) => Rect.fromLTWH(
    MatrixMetrics.header + column * MatrixMetrics.cell,
    MatrixMetrics.top + row * MatrixMetrics.cell,
    MatrixMetrics.cell,
    MatrixMetrics.cell,
  );

  /// The rows and columns of [r] (clamped to the grid), for culling.
  (int, int, int, int) range(Rect r) {
    final n = nodes.length;
    int at(double v, double from) => ((v - from) / MatrixMetrics.cell).floor().clamp(0, n == 0 ? 0 : n - 1);
    return (
      at(r.top, MatrixMetrics.top),
      at(r.bottom, MatrixMetrics.top),
      at(r.left, MatrixMetrics.header),
      at(r.right, MatrixMetrics.header),
    );
  }
}

MatrixLayout layoutMatrix(ModelController c) {
  final nodes = shownNodes(c);
  final row = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
  final cells = <MatrixCell, List<String>>{};
  for (final id in shownEdges(c, row.keys.toSet())) {
    final e = c.edgeOrGhost(id)!;
    final a = row[e.from]!, b = row[e.to]!;
    (cells[(row: a, column: b)] ??= []).add(id);
    if (e.undirected && a != b) (cells[(row: b, column: a)] ??= []).add(id);
  }
  final spans = <(int, int)>[];
  for (var i = 0; i < nodes.length; i++) {
    var j = i;
    while (j + 1 < nodes.length && nodes[j + 1].depth > nodes[i].depth) {
      j++;
    }
    if (j > i) spans.add((i, j));
  }
  return MatrixLayout._(nodes, cells, spans);
}
