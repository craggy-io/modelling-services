// matrix_renderer.dart: a dependency structure matrix (design §7.2): one row
// and column per area, grouped by containment; each cell counts the
// relationships from its row's area to its column's. Click a cell to list
// them; each can be inspected.

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../inspector/inspector.dart';
import '../../shared/markers.dart';
import '../../shared/model_canvas.dart';
import '../../shared/relationship_row.dart';
import '../../shared/shown_elements.dart';
import '../../theme/model_theme.dart';
import '../model_renderer.dart';
import 'matrix_layout.dart';
import 'matrix_painter.dart';

/// The matrix (DSM) renderer.
class MatrixRenderer extends ModelRenderer {
  const MatrixRenderer();

  @override
  String get id => 'matrix';

  @override
  String get label => 'Matrix';

  @override
  IconData get icon => Icons.grid_on;

  @override
  Widget build(BuildContext context, ModelController controller) => MatrixView(controller: controller);

  @override
  int shownAreas(ModelController controller, ModelTheme theme) => shownNodes(controller).where((n) => !n.ghost).length;
}

/// The matrix for [controller]. Tap a row to select its area, double-tap
/// to inspect it; tap a cell to list its relationships.
class MatrixView extends StatefulWidget {
  const MatrixView({super.key, required this.controller});

  final ModelController controller;

  @override
  State<MatrixView> createState() => _MatrixViewState();
}

class _MatrixViewState extends State<MatrixView> {
  /// The picked cell, by its row and column areas' ids.
  (String, String)? _picked;

  ModelController get _c => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _c, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = _c;
    final layout = layoutMatrix(c);
    if (layout.nodes.isEmpty) return Center(child: Text('No matching areas.', style: t.small));
    final rowOf = {for (var i = 0; i < layout.nodes.length; i++) layout.nodes[i].id: i};
    final p = _picked;
    final picked = p == null || rowOf[p.$1] == null || rowOf[p.$2] == null
        ? null
        : (row: rowOf[p.$1]!, column: rowOf[p.$2]!);
    final listed = picked == null ? const <String>[] : layout.cells[picked] ?? const <String>[];

    final canvas = ModelCanvas(
      size: layout.size,
      leading: [
        if (c.trail.isNotEmpty)
          chrome.button(
            label: 'Back to parent area',
            icon: Icons.arrow_back,
            variant: ModelButtonVariant.ghost,
            size: ModelButtonSize.sm,
            onPressed: c.back,
          ),
      ],
      builder: (context, visible) {
        final (r0, r1, c0, c1) = layout.range(visible);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: MatrixPainter(controller: c, layout: layout, theme: t, visible: visible, picked: picked),
              ),
            ),
            for (var i = r0; i <= r1; i++)
              Positioned.fromRect(
                key: ValueKey('matrix-at-$i'),
                rect: layout.rowHeader(i),
                child: _header(context, layout.nodes[i], i),
              ),
            for (final e in layout.cells.entries)
              if (e.key.row >= r0 && e.key.row <= r1 && e.key.column >= c0 && e.key.column <= c1)
                Positioned.fromRect(
                  key: ValueKey('matrix-at-${e.key.row}-${e.key.column}'),
                  rect: layout.cellRect(e.key.row, e.key.column),
                  child: _cell(context, layout, e.key, e.value.length),
                ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: canvas),
        if (picked != null) ...[
          SizedBox(height: t.spacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _list(context, layout, picked, listed),
          ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, ShownNode node, int i) {
    final t = ModelTheme.of(context);
    final c = _c;
    final n = c.nodeOrGhost(node.id)!;
    final ref = ModelElementRef.node(node.id);
    return Semantics(
      button: true,
      selected: c.selection == ref,
      label: 'Row ${i + 1}, area ${n.label}${node.ghost ? ', removed since the base' : ''}',
      child: GestureDetector(
        key: ValueKey('matrix-row-${node.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          c.select(ref);
          c.focus(node.id);
        },
        onDoubleTap: () => inspectElement(context, c, ref),
        child: Opacity(
          opacity: node.ghost ? 0.55 : 1,
          child: Padding(
            padding: EdgeInsets.only(left: t.spacing.xxs, right: t.spacing.xs),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${i + 1}', style: t.small)),
                SizedBox(width: node.depth * t.indent / 2),
                Flexible(
                  child: Text(
                    n.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.standard.copyWith(decoration: node.ghost ? TextDecoration.lineThrough : null),
                  ),
                ),
                ...elementMarks(context, c, node.id, edge: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, MatrixLayout layout, MatrixCell cell, int count) {
    final t = ModelTheme.of(context);
    final c = _c;
    final from = layout.nodes[cell.row].id, to = layout.nodes[cell.column].id;
    final words = '$count relationship${count == 1 ? '' : 's'} from ${c.labelOf(from)} to ${c.labelOf(to)}';
    return Semantics(
      button: true,
      label: words,
      child: ModelChrome.of(context).tooltip(
        message: words,
        child: GestureDetector(
          key: ValueKey('matrix-cell-$from-$to'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _picked = (from, to)),
          child: Center(
            child: Text(
              '$count',
              style: t.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, MatrixLayout layout, MatrixCell cell, List<String> ids) {
    final t = ModelTheme.of(context);
    final c = _c;
    final from = layout.nodes[cell.row].id, to = layout.nodes[cell.column].id;
    return Container(
      key: const ValueKey('matrix-cell-list'),
      padding: EdgeInsets.all(t.spacing.xs),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: t.borderWidth),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c.labelOf(from)} → ${c.labelOf(to)} · ${ids.length} relationship${ids.length == 1 ? '' : 's'}',
                  style: t.heading,
                ),
              ),
              ModelChrome.of(
                context,
              ).iconButton(icon: Icons.close, tooltip: 'Close', onPressed: () => setState(() => _picked = null)),
            ],
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final id in ids)
                  RelationshipRow(
                    controller: c,
                    edgeId: id,
                    dense: true,
                    onPressed: () => inspectElement(context, c, ModelElementRef.edge(id)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
