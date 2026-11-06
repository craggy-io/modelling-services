// grid_canvas.dart: the board of the grid blocks layout. The board is the
// model: its top-level areas sit straight on a dotted canvas (no root card
// repeating the title), zoomed by the controller's `zoom`. It is the one
// drop target for drags over the board (see grid_drop.dart): over a card
// a drag previews landing beside or inside it; on the bare canvas it puts
// the area at the top level (or in the drilled-in area).

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../shared/drag_payloads.dart';
import '../../shared/scaled_box.dart';
import '../../theme/model_theme.dart';
import '../../workspace/model_hooks.dart';
import 'area_box.dart';
import 'blocks_layout.dart';
import 'connector_painter.dart';
import 'grid_drop.dart';
import 'grid_children.dart';
import 'relationships_list.dart';

class GridCanvas extends StatefulWidget {
  const GridCanvas({
    super.key,
    required this.board,
    required this.layout,
    required this.diagram,
    required this.drawn,
    required this.onInspectEdge,
  });

  final BlocksBoardHandle board;
  final BlocksLayout layout;
  final GlobalKey diagram;
  final DrawnRect drawn;
  final ValueChanged<String> onInspectEdge;

  @override
  State<GridCanvas> createState() => _GridCanvasState();
}

class _GridCanvasState extends State<GridCanvas> {
  final _drag = GridDragState();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GridDragScope(
    state: _drag,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final t = ModelTheme.of(context);
    final board = widget.board;
    final c = board.controller;
    final parent = c.region ?? '';
    final areas = widget.layout.root.children;
    final limit = c.limit ?? t.pageSize;
    final listed = listedEdges(c);
    // The board's one drop target: the drag state works out which card is
    // under the pointer and where on it, and every grid previews that.
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => !c.readOnly && (d.data is MoveArea || d.data is AddArea || d.data is ConnectArea),
      onMove: (d) => _drag.hover(c, d.data, d.offset),
      onLeave: (_) => _drag.leave(),
      onAcceptWithDetails: (d) => _drag.apply(c, d.data, parent, board.connect),
      builder: (context, candidates, _) => DecoratedBox(
        key: const ValueKey('grid-canvas'),
        decoration: BoxDecoration(
          color: t.canvas,
          // Only a drop on the canvas itself (the top level) lights it.
          border: candidates.isEmpty || _drag.drop != null || candidates.first is ConnectArea
              ? null
              : Border.all(color: t.focus, width: 1.5),
        ),
        child: CustomPaint(
          painter: DotGridPainter(colour: t.canvasDot, spacing: t.spacing.lg),
          child: areas.isEmpty
              ? EmptyBoard(controller: c)
              : ValueListenableBuilder<double>(
                  valueListenable: c.zoom,
                  builder: (context, zoom, _) => SingleChildScrollView(
                    padding: EdgeInsets.all(t.spacing.xl),
                    child: ScaledBox(
                      scale: zoom,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RepaintBoundary(
                            key: ModelHooks.of(context).captureKey,
                            child: CustomPaint(
                              key: widget.diagram,
                              foregroundPainter: ConnectorPainter(
                                controller: c,
                                diagram: widget.diagram,
                                drawn: widget.drawn,
                                theme: t,
                              ),
                              child: GridChildren(areas: areas, board: board, depth: 0),
                            ),
                          ),
                          if (widget.layout.more(limit)) ...[
                            SizedBox(height: t.spacing.md),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ModelChrome.of(context).button(
                                label: 'Show more areas',
                                icon: Icons.expand_more_rounded,
                                variant: ModelButtonVariant.ghost,
                                onPressed: () => c.showMore(t.pageSize),
                              ),
                            ),
                          ],
                          if (listed.isNotEmpty && parent.isEmpty) ...[
                            SizedBox(height: t.spacing.lg),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.surface,
                                borderRadius: BorderRadius.circular(t.radius),
                                border: Border.all(color: t.divider, width: t.borderWidth),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(t.spacing.xs),
                                child: RelationshipsList(controller: c, onInspect: widget.onInspectEdge),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A dot every [spacing] pixels: the canvas backdrop.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({required this.colour, required this.spacing});

  final Color colour;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter old) => old.colour != colour || old.spacing != spacing;
}

/// The board with nothing on it: how to start, or that nothing matches.
class EmptyBoard extends StatelessWidget {
  const EmptyBoard({super.key, required this.controller});

  final ModelController controller;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final matching = c.model.nodes.isNotEmpty;
    final (icon, title, body) = matching
        ? (Icons.search_off_rounded, 'No matching areas', 'Nothing matches the search or filters.')
        : c.readOnly
        ? (Icons.dashboard_outlined, 'This model has no areas', 'There is nothing to show yet.')
        : (
            Icons.dashboard_customize_outlined,
            'Start your model',
            'Drag a component from the palette onto the board, or add a first area.',
          );
    return Center(
      key: const ValueKey('empty-board'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.surface,
                shape: BoxShape.circle,
                border: Border.all(color: t.divider),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Icon(icon, size: 26, color: t.focus),
            ),
            SizedBox(height: t.spacing.md),
            Text(title, style: t.heading.copyWith(fontSize: (t.heading.fontSize ?? 15) + 2)),
            SizedBox(height: t.spacing.xs),
            Text(body, textAlign: TextAlign.center, style: t.small),
            SizedBox(height: t.spacing.lg),
            if (matching)
              chrome.button(
                label: 'Clear search',
                icon: Icons.close_rounded,
                onPressed: () => c.filter = c.filter.copyWith(text: '', kinds: const [], tags: const []),
              )
            else if (!c.readOnly)
              chrome.button(
                key: const ValueKey('empty-add-area'),
                label: 'Add area',
                icon: Icons.add_rounded,
                variant: ModelButtonVariant.primary,
                onPressed: c.addArea,
              ),
          ],
        ),
      ),
    );
  }
}
