// layers_tree.dart: the editor's compact containment tree. A row per area,
// indented by depth, with the selection synced both ways; drag a row onto
// another to move it inside (middle) or beside it (top or bottom edge), or
// drop a palette kind on a row to add a child there.

import 'package:flutter/material.dart';

import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/drag_payloads.dart';
import '../shared/kind_style.dart';
import '../theme/model_theme.dart';

/// One visible row: an area at a depth.
typedef LayerRow = ({String id, int depth, bool parent});

/// The rows shown with [folded] areas closed, in containment order.
List<LayerRow> layerRows(ModelController c, Set<String> folded) {
  final out = <LayerRow>[];
  void walk(String parent, int depth) {
    for (final id in c.index.children(parent)) {
      final kids = c.index.children(id).isNotEmpty;
      out.add((id: id, depth: depth, parent: kids));
      if (kids && !folded.contains(id)) walk(id, depth + 1);
    }
  }

  walk('', 0);
  return out;
}

class LayersTree extends StatefulWidget {
  const LayersTree({super.key, required this.controller});

  final ModelController controller;

  @override
  State<LayersTree> createState() => _LayersTreeState();
}

class _LayersTreeState extends State<LayersTree> {
  final _folded = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = widget.controller;
    final rows = layerRows(c, _folded);
    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(t.spacing.sm),
        child: Text('Areas you add appear here.', style: t.small),
      );
    }
    return ListView.builder(
      key: const ValueKey('layers'),
      padding: EdgeInsets.symmetric(vertical: t.spacing.xxs),
      itemCount: rows.length,
      itemExtent: 30,
      itemBuilder: (context, i) => _LayerRowView(
        controller: c,
        row: rows[i],
        folded: _folded.contains(rows[i].id),
        onFold: () =>
            setState(() => _folded.contains(rows[i].id) ? _folded.remove(rows[i].id) : _folded.add(rows[i].id)),
      ),
    );
  }
}

class _LayerRowView extends StatefulWidget {
  const _LayerRowView({required this.controller, required this.row, required this.folded, required this.onFold});

  final ModelController controller;
  final LayerRow row;
  final bool folded;
  final VoidCallback onFold;

  @override
  State<_LayerRowView> createState() => _LayerRowViewState();
}

class _LayerRowViewState extends State<_LayerRowView> {
  var _hovered = false;
  DropZone? _zone;

  String get _id => widget.row.id;

  void _track(DragTargetDetails<Object> d) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final zone = zoneAt(box.globalToLocal(d.offset).dy, box.size.height, reorder: d.data is MoveArea, maxEdge: 8);
    if (zone != _zone) setState(() => _zone = zone);
  }

  void _drop(DragTargetDetails<Object> d) {
    final c = widget.controller;
    final zone = _zone ?? DropZone.into;
    setState(() => _zone = null);
    switch (d.data) {
      case MoveArea m when zone == DropZone.into:
        c.reparent(m.id, _id);
      case MoveArea m:
        c.moveBeside(m.id, _id, after: zone == DropZone.after);
      case AddArea a:
        c.addKind(_id, a.kind, label: a.label);
    }
  }

  void _select() {
    final c = widget.controller;
    c.reveal(_id);
    c.select(ModelElementRef.node(_id));
    c.focus(_id);
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = widget.controller;
    final node = c.index.node(_id)!;
    final style = kindStyle(t, c.profile, node.kind);
    final selected = c.selection?.isNode == true && c.selection!.id == _id;
    final editable = !c.readOnly;
    Widget row(Object? dragging) {
      final zone = dragging == null ? null : (_zone ?? DropZone.into);
      final refused = zone != null && dropRefusal(c, dragging, _id, zone) != null;
      final ring = refused ? t.lintError : t.focus;
      final fill = zone == DropZone.into
          ? ring.withValues(alpha: 0.14)
          : selected
          ? t.focus.withValues(alpha: 0.14)
          : (_hovered ? t.hover : null);
      return Container(
        key: ValueKey('layer-$_id'),
        margin: EdgeInsets.symmetric(horizontal: t.spacing.xs),
        padding: EdgeInsets.only(left: t.spacing.xxs + widget.row.depth * 14.0, right: t.spacing.xs),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(t.radius * 0.6),
          border: Border(
            top: BorderSide(color: zone == DropZone.before ? ring : Colors.transparent, width: 2),
            bottom: BorderSide(color: zone == DropZone.after ? ring : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: widget.row.parent
                  ? GestureDetector(
                      onTap: widget.onFold,
                      child: Icon(
                        widget.folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                        size: 16,
                        color: t.muted,
                      ),
                    )
                  : null,
            ),
            Icon(style.icon, size: 15, color: style.kind.isEmpty ? t.muted : style.colour),
            SizedBox(width: t.spacing.xs),
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: t.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
          ],
        ),
      );
    }

    final view = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _select, child: row(null)),
    );
    if (!editable) return Semantics(button: true, selected: selected, label: node.label, child: view);
    return Semantics(
      button: true,
      selected: selected,
      label: node.label,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (d) => switch (d.data) {
          MoveArea m => m.id != _id,
          AddArea _ => true,
          _ => false,
        },
        onMove: _track,
        onLeave: (_) => setState(() => _zone = null),
        onAcceptWithDetails: _drop,
        builder: (context, candidates, _) => Draggable<Object>(
          data: MoveArea(_id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: ModelThemeScope(
            theme: t,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xxs + 2),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.radius),
                  border: Border.all(color: t.focus),
                  boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Text(node.label, style: t.small.copyWith(color: t.text)),
              ),
            ),
          ),
          child: candidates.isEmpty
              ? view
              : GestureDetector(behavior: HitTestBehavior.opaque, onTap: _select, child: row(candidates.first)),
        ),
      ),
    );
  }
}
