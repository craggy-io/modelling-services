// graph_renderer.dart: a node-link canvas (design §7.2): compound boxes for
// containment, relationships as lines, pan and zoom, a deterministic
// layered auto layout, and positions saved in the view by dragging.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../inspector/inspector.dart';
import '../../shared/markers.dart';
import '../../shared/model_canvas.dart';
import '../../shared/shown_elements.dart';
import '../../theme/model_theme.dart';
import '../model_renderer.dart';
import 'graph_layout.dart';
import 'graph_painter.dart';
import '../../shared/no_areas.dart';

/// The graph renderer.
class GraphRenderer extends ModelRenderer {
  const GraphRenderer();

  @override
  String get id => 'graph';

  @override
  String get label => 'Graph';

  @override
  IconData get icon => Icons.hub_outlined;

  @override
  Widget build(BuildContext context, ModelController controller) => GraphView(controller: controller);

  @override
  int shownAreas(ModelController controller, ModelTheme theme) => shownNodes(controller).where((n) => !n.ghost).length;
}

/// The graph for [controller]. Tap an area or relationship label to
/// select it, double-tap to inspect; unless read-only, drag an area to
/// place it (saved in the active view's `positions`).
class GraphView extends StatefulWidget {
  const GraphView({super.key, required this.controller});

  final ModelController controller;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  String? _dragging;
  Offset _dragFrom = Offset.zero;
  Offset _dragBy = Offset.zero;

  ModelController get _c => widget.controller;

  void _select(ModelElementRef ref) {
    _c.select(ref);
    if (ref.isNode) _c.focus(ref.id);
  }

  void _startDrag(GraphBox box) => setState(() {
    _dragging = box.id;
    _dragFrom = box.place;
    _dragBy = Offset.zero;
  });

  void _endDrag() {
    final id = _dragging, to = _dragFrom + _dragBy;
    setState(() => _dragging = null);
    if (id == null || _dragBy == Offset.zero) return;
    _c.setPositions({id: (to.dx.roundToDouble(), to.dy.roundToDouble())});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _c, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = _c;
    final drag = _dragging;
    final layout = layoutGraph(
      c,
      t,
      positions: drag == null ? null : {...c.positions, drag: ((_dragFrom + _dragBy).dx, (_dragFrom + _dragBy).dy)},
    );
    if (layout.boxes.isEmpty) return NoAreas(controller: c);
    final origin = layout.bounds.topLeft;
    return ModelCanvas(
      size: layout.bounds.size,
      origin: origin,
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
      trailing: [
        if (!c.readOnly && c.positions.isNotEmpty)
          chrome.button(
            label: 'Auto layout',
            icon: Icons.auto_fix_high,
            variant: ModelButtonVariant.ghost,
            size: ModelButtonSize.sm,
            tooltip: 'Forget the saved positions',
            onPressed: () => c.setPositions(const {}, replace: true),
          ),
      ],
      builder: (context, visible) {
        final view = visible.inflate(GraphMetrics.margin);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: GraphPainter(controller: c, layout: layout, theme: t, origin: origin, visible: visible),
              ),
            ),
            // Area labels go over relationship labels, so a crossing line
            // never hides an area's name.
            for (final id in layout.edges) ?_edgeLabel(context, layout, id, origin, view),
            for (final box in layout.boxes.values)
              if (box.labelRect.overlaps(view))
                Positioned.fromRect(
                  key: ValueKey('graph-at-${box.id}'),
                  rect: box.labelRect.shift(-origin),
                  child: _node(context, box),
                ),
          ],
        );
      },
    );
  }

  Widget _node(BuildContext context, GraphBox box) {
    final t = ModelTheme.of(context);
    final c = _c;
    final n = c.nodeOrGhost(box.id)!;
    final ghost = box.node.ghost;
    final movable = !c.readOnly && !ghost;
    final kind = n.kind.isEmpty ? '' : (c.profile?.nodeKinds[n.kind]?.label ?? n.kind);
    return Semantics(
      label: ['Area ${n.label}', if (kind.isNotEmpty) kind, if (ghost) 'removed since the base'].join(', '),
      selected: c.selection == ModelElementRef.node(box.id),
      button: true,
      child: MouseRegion(
        cursor: movable ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('graph-node-${box.id}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => _select(ModelElementRef.node(box.id)),
          onDoubleTap: () => inspectElement(context, c, ModelElementRef.node(box.id)),
          onPanStart: movable ? (_) => _startDrag(box) : null,
          onPanUpdate: movable ? (d) => setState(() => _dragBy += d.delta) : null,
          onPanEnd: movable ? (_) => _endDrag() : null,
          onPanCancel: movable ? () => setState(() => _dragging = null) : null,
          // Filled inside the painted border, so lines and relationship
          // labels pass behind the area.
          child: Container(
            margin: EdgeInsets.all(t.selectedBorderWidth),
            padding: EdgeInsets.symmetric(horizontal: t.spacing.sm - t.selectedBorderWidth),
            decoration: BoxDecoration(
              color: graphBoxFill(t, box),
              borderRadius: BorderRadius.circular(t.radius - t.selectedBorderWidth),
            ),
            child: Opacity(
              opacity: ghost ? 0.6 : 1,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      n.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.standard.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: ghost ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  ...elementMarks(context, c, box.id, edge: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _edgeLabel(BuildContext context, GraphLayout layout, String id, Offset origin, Rect view) {
    final c = _c;
    final e = c.edgeOrGhost(id)!;
    if (e.label.isEmpty || e.from == e.to) return null;
    final (start, end) = edgeEnds(layout.boxes[e.from]!.rect, layout.boxes[e.to]!.rect);
    final mid = Offset.lerp(start, end, 0.5)!;
    if (!view.contains(mid)) return null;
    const w = 150.0, h = 24.0;
    return Positioned(
      key: ValueKey('graph-label-$id'),
      left: mid.dx - origin.dx - w / 2,
      top: mid.dy - origin.dy - h / 2,
      width: w,
      height: h,
      child: Center(
        child: _EdgeLabel(controller: c, edge: e, onSelect: _select),
      ),
    );
  }
}

class _EdgeLabel extends StatelessWidget {
  const _EdgeLabel({required this.controller, required this.edge, required this.onSelect});

  final ModelController controller;
  final Edge edge;
  final ValueChanged<ModelElementRef> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = controller;
    final ref = ModelElementRef.edge(edge.id);
    final ghost = c.index.edge(edge.id) == null;
    final selected = c.selection == ref;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Relationship ${edge.label}${ghost ? ', removed' : ''}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => c.hover(edge.id),
        onExit: (_) {
          if (c.hovered.value == edge.id) c.hover(null);
        },
        child: GestureDetector(
          key: ValueKey('graph-edge-${edge.id}'),
          onTap: () => onSelect(ref),
          onDoubleTap: () => inspectElement(context, c, ref),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.spacing.xxs),
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(t.radius),
              border: selected ? Border.all(color: t.selectedBorder, width: t.borderWidth) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    edge.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(decoration: ghost ? TextDecoration.lineThrough : null),
                  ),
                ),
                ...elementMarks(context, c, edge.id, edge: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
