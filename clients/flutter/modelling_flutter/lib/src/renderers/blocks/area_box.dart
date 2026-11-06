// area_box.dart: one nested area block (theme.md §5.17): label chip (the
// inspector and connector anchor), collapse and drill-in, children in up
// to maxColumns columns, relationship dots, marks, and in edit mode the
// area menu, move and connect handles and drop targets.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../shared/markers.dart';
import '../../shared/model_diff.dart';
import '../../theme/model_theme.dart';
import 'area_parts.dart';
import 'blocks_layout.dart';

/// What an area box asks of the board it sits on.
abstract class BlocksBoardHandle {
  ModelController get controller;
  GlobalKey anchor(String id);
  String? get renaming;
  TextEditingController get renameText;
  void inspect(String id);
  void inspectEdge(String id);
  void press(String id);
  void startRename(String id);
  void commitRename();
  void cancelRename();
  void delete(String id);
  void connect(String from, String to);
}

/// Dragged to reparent an area.
class MoveArea {
  const MoveArea(this.id);
  final String id;
}

/// Dragged from an area's connection handle to draw a relationship.
class ConnectArea {
  const ConnectArea(this.from);
  final String from;
}

class AreaBox extends StatelessWidget {
  const AreaBox({super.key, required this.area, required this.board, this.depth = 0});

  final BlockArea area;
  final BlocksBoardHandle board;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = board.controller;
    final id = area.id;
    final editable = !c.readOnly && !area.ghost;
    final box = _box(context, t, c, null);
    if (!editable) return box;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        MoveArea m => m.id != id,
        ConnectArea _ => id != null,
        _ => false,
      },
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case MoveArea m:
            c.reparent(m.id, id ?? (c.region ?? ''));
          case ConnectArea a:
            board.connect(a.from, id!);
        }
      },
      builder: (context, candidates, _) {
        if (candidates.isEmpty) return box;
        final m = candidates.first;
        final refused = m is MoveArea && c.reparentRefusal(m.id, id ?? (c.region ?? '')) != null;
        return _box(context, t, c, refused ? t.lintError : t.focus);
      },
    );
  }

  Widget _box(BuildContext context, ModelTheme t, ModelController c, Color? dropColour) {
    final chrome = ModelChrome.of(context);
    final id = area.id;
    final selected = id != null && c.selection?.isNode == true && c.selection!.id == id;
    final focused = id != null && c.focused == id;
    final border = dropColour ?? (selected ? t.selectedBorder : (focused ? t.focus : t.border));
    final width = dropColour != null || selected || focused ? t.selectedBorderWidth : t.borderWidth;
    final editable = !c.readOnly && !area.ghost;
    final mark = id == null ? null : c.overlay?.marks[id];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: id == null
                    ? Text(area.title, style: t.heading)
                    : Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AreaLabel(area: area, board: board, border: border),
                          ...elementMarks(context, c, id, edge: false),
                        ],
                      ),
              ),
            ),
            if (area.childCount > 0) ...[
              chrome.iconButton(
                icon: area.folded ? Icons.add : Icons.remove,
                tooltip: '${area.folded ? 'Expand' : 'Collapse'} ${area.title}',
                onPressed: () => c.toggleFolded(id, folded: area.folded),
              ),
              if (id != null && depth > 0 && !area.ghost)
                chrome.iconButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Open ${area.title}',
                  onPressed: () => c.drillIn(id),
                ),
            ],
            if (editable && id != null) ...[
              _handle(context, t, ConnectArea(id), Icons.trip_origin, 'Drag to relate ${area.title} to another area'),
              _handle(context, t, MoveArea(id), Icons.drag_indicator, 'Drag to move ${area.title} into another area'),
              AreaMenu(board: board, id: id, title: area.title),
            ],
            if (editable && id == null)
              chrome.iconButton(
                icon: Icons.add_box_outlined,
                tooltip: 'Add area',
                onPressed: () {
                  final added = c.addChild(c.region ?? '');
                  if (added != null) board.startRename(added);
                },
              ),
          ],
        ),
        if (mark?.value != null) ...[
          SizedBox(height: t.spacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: mark!.value!.clamp(0, 1).toDouble(),
                child: ColoredBox(color: mark.color),
              ),
            ),
          ),
        ],
        if (area.description.isNotEmpty) ...[
          SizedBox(height: t.gap),
          Text(area.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.small),
        ],
        if (area.folded) ...[
          SizedBox(height: t.gap),
          Text('${area.childCount} ${area.childCount == 1 ? 'area' : 'areas'} collapsed', style: t.small),
        ],
        if (!area.folded && area.children.isNotEmpty) ...[
          SizedBox(height: t.gap),
          LayoutBuilder(
            builder: (context, bounds) {
              final gap = t.gap;
              final columns = math.max(
                1,
                math.min(
                  math.min(t.maxColumns, area.children.length),
                  ((bounds.maxWidth + gap) / (t.minAreaWidth + gap)).floor(),
                ),
              );
              final w = math.max(0.0, (bounds.maxWidth - (columns - 1) * gap) / columns);
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final child in area.children)
                    SizedBox(
                      width: w,
                      child: AreaBox(area: child, board: board, depth: depth + 1),
                    ),
                ],
              );
            },
          ),
        ],
        if (id != null) ...[SizedBox(height: t.gap), AreaDots(board: board, id: id)],
      ],
    );

    final decorated = Container(
      key: ValueKey('model-area-${id ?? 'root'}'),
      padding: EdgeInsets.all(depth == 0 ? t.rootPadding : t.padding),
      decoration: BoxDecoration(
        color: area.ghost ? t.areaAt(depth).withValues(alpha: 0.35) : t.areaAt(depth),
        border: area.ghost ? null : Border.all(color: border, width: width),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: content,
    );
    final drawn = area.ghost
        ? CustomPaint(
            foregroundPainter: DashedBorderPainter(colour: t.removed, width: t.borderWidth, radius: t.radius),
            child: Opacity(opacity: 0.7, child: decorated),
          )
        : decorated;
    return Semantics(
      container: true,
      label: id == null
          ? 'Model ${area.title}'
          : [
              'Area ${area.title}',
              if (area.ghost) 'removed since the base',
              if (area.childCount > 0) '${area.childCount} ${area.childCount == 1 ? 'area' : 'areas'}',
              if (area.folded) 'collapsed',
              if (selected) 'selected',
              if (focused) 'focused',
              if (!area.ghost && c.diff.nodeChange(id) != null) ModelDiff.describe(c.diff.nodeChange(id)),
            ].join(', '),
      child: drawn,
    );
  }

  Widget _handle(BuildContext context, ModelTheme t, Object payload, IconData icon, String tooltip) {
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xxs),
      decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(t.radius)),
      child: Text(area.title, style: t.standard),
    );
    return Draggable<Object>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: ModelThemeScope(
        theme: t,
        child: Directionality(textDirection: TextDirection.ltr, child: chip),
      ),
      child: MouseRegion(
        cursor: payload is MoveArea ? SystemMouseCursors.grab : SystemMouseCursors.precise,
        child: ModelChrome.of(context).tooltip(
          message: tooltip,
          child: Semantics(
            label: tooltip,
            child: Padding(
              padding: EdgeInsets.all(t.spacing.xxs + 2),
              child: Icon(icon, size: 16, color: t.muted),
            ),
          ),
        ),
      ),
    );
  }
}
