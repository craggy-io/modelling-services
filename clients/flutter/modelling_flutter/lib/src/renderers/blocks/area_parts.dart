// area_parts.dart: the pieces of an area box: its label chip (with inline
// rename), its relationship dots, its edit menu and the dashed outline of a
// removed (ghost) area.

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../shared/drag_payloads.dart';
import '../../shared/inline_rename.dart';
import '../../theme/model_theme.dart';
import 'area_box.dart';
import 'blocks_layout.dart';

/// The area's label chip: opens the inspector, anchors connectors, and in
/// edit mode renames on double-click (or F2 from the board).
class AreaLabel extends StatefulWidget {
  const AreaLabel({super.key, required this.area, required this.board, required this.border});

  final BlockArea area;
  final BlocksBoardHandle board;
  final Color border;

  @override
  State<AreaLabel> createState() => _AreaLabelState();
}

class _AreaLabelState extends State<AreaLabel> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final b = widget.board;
    final id = widget.area.id!;
    if (b.renaming == id) {
      return SizedBox(
        key: b.anchor(id),
        width: 240,
        child: InlineRenameField(controller: b.renameText, onCommit: b.commitRename, onCancel: b.cancelRename),
      );
    }
    final editable = !b.controller.readOnly && !widget.area.ghost;
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.xs),
      decoration: BoxDecoration(
        color: _hovered ? t.raised : t.labelBackground,
        border: Border.all(color: widget.border, width: t.borderWidth),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Text(
        widget.area.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: widget.area.ghost ? t.heading.copyWith(decoration: TextDecoration.lineThrough) : t.heading,
      ),
    );
    return MouseRegion(
      key: b.anchor(id),
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: 'Inspect ${widget.area.title}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => b.inspect(id),
          onDoubleTap: editable ? () => b.startRename(id) : null,
          child: ModelChrome.of(context).tooltip(message: 'Inspect ${widget.area.title}', child: chip),
        ),
      ),
    );
  }
}

/// Edge ids to draw as dots on area [id]: current and removed ones, only
/// changed ones under "Changed only".
List<String> dotEdges(ModelController c, String id) {
  final ids = c.diff.hasBase ? c.diff.edgesAt(id) : c.index.touching(id);
  if (!c.changedOnly) return ids;
  return [
    for (final e in ids)
      if (c.diff.edgeChange(e) != null) e,
  ];
}

/// The area's relationship circles (up to maxDots) and its count link.
/// Hover a circle to preview its connector; click to pin it.
class AreaDots extends StatelessWidget {
  const AreaDots({super.key, required this.board, required this.id});

  final BlocksBoardHandle board;
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = board.controller;
    final edges = dotEdges(c, id);
    if (edges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: t.spacing.xs,
      children: [
        for (final eid in edges.take(t.maxDots))
          Builder(
            builder: (context) {
              final e = c.edgeOrGhost(eid)!;
              final pinned = c.isPinned(eid);
              final ghost = c.index.edge(eid) == null;
              return MouseRegion(
                key: ValueKey('dot-$id-$eid'),
                onEnter: (_) => c.hover(eid),
                onExit: (_) {
                  if (c.hovered.value == eid) c.hover(null);
                },
                child: Opacity(
                  opacity: ghost ? 0.5 : 1,
                  child: chrome.iconButton(
                    icon: pinned ? Icons.circle : Icons.circle_outlined,
                    color: t.paletteAt(c.slotOf(eid)),
                    tooltip: '${c.labelOf(e.from)} → ${e.label} → ${c.labelOf(e.to)}${ghost ? ' (removed)' : ''}',
                    onPressed: () => c.togglePin(eid),
                  ),
                ),
              );
            },
          ),
        chrome.button(
          label: '${edges.length} relationship${edges.length == 1 ? '' : 's'}',
          variant: ModelButtonVariant.link,
          size: ModelButtonSize.sm,
          onPressed: () => board.inspect(id),
        ),
      ],
    );
  }
}

/// The area's edit menu: add child or sibling, rename, delete.
class AreaMenu extends StatelessWidget {
  const AreaMenu({super.key, required this.board, required this.id, required this.title, this.extra = const []});

  final BlocksBoardHandle board;
  final String id;
  final String title;

  /// Entries before Delete (the grid layout's open and size items).
  final List<ModelMenuItem> extra;

  @override
  Widget build(BuildContext context) {
    final c = board.controller;
    return ModelChrome.of(context).menuButton(
      icon: Icons.more_vert,
      tooltip: 'Edit $title',
      items: [
        ModelMenuItem(
          label: 'Add area inside',
          icon: Icons.subdirectory_arrow_right,
          onSelected: () {
            final added = c.addChild(id);
            if (added != null) board.startRename(added);
          },
        ),
        ModelMenuItem(
          label: 'Add area beside',
          icon: Icons.add,
          onSelected: () {
            final added = c.addSibling(id);
            if (added != null) board.startRename(added);
          },
        ),
        ModelMenuItem(label: 'Rename', icon: Icons.edit_outlined, onSelected: () => board.startRename(id)),
        ...extra,
        ModelMenuItem(label: 'Delete', icon: Icons.delete_outline, onSelected: () => board.delete(id)),
      ],
    );
  }
}

/// A small icon an area is dragged by: [payload] is a MoveArea or a
/// ConnectArea; [feedback] follows the pointer.
class DragHandle extends StatelessWidget {
  const DragHandle({
    super.key,
    required this.payload,
    required this.icon,
    required this.tooltip,
    required this.feedback,
    this.extent = 28,
  });

  final Object payload;
  final IconData icon;
  final String tooltip;
  final Widget feedback;

  /// The square it takes, its icon centred.
  final double extent;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Draggable<Object>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: ModelThemeScope(
        theme: t,
        child: Directionality(textDirection: TextDirection.ltr, child: feedback),
      ),
      child: MouseRegion(
        cursor: payload is MoveArea ? SystemMouseCursors.grab : SystemMouseCursors.precise,
        child: ModelChrome.of(context).tooltip(
          message: tooltip,
          child: Semantics(
            label: tooltip,
            child: SizedBox.square(
              dimension: extent,
              child: Center(child: Icon(icon, size: 16, color: t.muted)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline, for removed (ghost) areas.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.colour, required this.width, required this.radius});

  final Color colour;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) => old.colour != colour || old.width != width || old.radius != radius;
}
