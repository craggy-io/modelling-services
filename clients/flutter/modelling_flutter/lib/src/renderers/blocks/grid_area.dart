// grid_area.dart: one area in the grid blocks layout: a card with a kind
// chip, title, marks and hover actions, its notes, its children on the
// 10-column grid and its relationship dots. In edit mode the whole card
// drags (past a few pixels, so a click still selects): the board's drop
// preview shows where it would land, and this card lights up when a drag
// would land inside it.

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../shared/drag_payloads.dart';
import '../../shared/inline_rename.dart';
import '../../shared/kind_style.dart';
import '../../shared/markers.dart';
import '../../shared/model_diff.dart';
import '../../shared/slop_draggable.dart';
import '../../theme/model_theme.dart';
import 'area_box.dart';
import 'area_parts.dart';
import 'blocks_layout.dart';
import 'grid_children.dart';
import 'grid_drop.dart';

class GridAreaBox extends StatefulWidget {
  const GridAreaBox({super.key, required this.area, required this.board, required this.depth, this.clip = false});

  final BlockArea area;
  final BlocksBoardHandle board;
  final int depth;

  /// Clips the contents to a fixed height (a view size's `h`).
  final bool clip;

  @override
  State<GridAreaBox> createState() => _GridAreaBoxState();
}

class _GridAreaBoxState extends State<GridAreaBox> {
  var _hovered = false;
  GridDragState? _drag;

  String get _id => widget.area.id!;
  ModelController get _c => widget.board.controller;
  bool get _editable => !_c.readOnly && !widget.area.ghost;

  @override
  void didUpdateWidget(GridAreaBox old) {
    super.didUpdateWidget(old);
    if (old.area.id != widget.area.id || old.depth != widget.depth) {
      _drag?.unregister(old.area.id!, context);
      _register();
    }
  }

  /// Lets the board land drags on this card.
  void _register() {
    final drag = GridDragScope.read(context);
    if (drag != _drag) _drag?.unregister(_id, context);
    _drag = drag;
    if (_editable) {
      drag?.register(_id, context, widget.depth);
    } else {
      drag?.unregister(_id, context);
    }
  }

  @override
  void dispose() {
    _drag?.unregister(_id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _register();
    final drag = GridDragScope.of(context);
    final card = _card(context, drag);
    if (!_editable || widget.board.renaming == _id || drag == null) return card;
    final t = ModelTheme.of(context);
    return SlopDraggable(
      data: MoveArea(_id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => drag.begin(_id, context.size ?? Size.zero),
      onDragEnd: (_) => drag.end(),
      feedback: ModelThemeScope(
        theme: t,
        child: Directionality(textDirection: TextDirection.ltr, child: _feedback(t)),
      ),
      child: card,
    );
  }

  Widget _card(BuildContext context, GridDragState? drag) {
    final t = ModelTheme.of(context);
    final c = _c;
    final area = widget.area;
    final selected = c.selection?.isNode == true && c.selection!.id == _id;
    final focused = c.focused == _id;
    final drop = drag?.drop;
    final into = drop != null && drop.target == _id && !drop.beside;
    final lifted = drag?.moving == _id;
    final ring = into && drop.refused ? t.lintError : t.focus;
    final Color border = into || selected || focused ? ring : (_hovered ? t.border : t.divider);
    final duration = t.quickDuration(context);

    final card = AnimatedContainer(
      key: ValueKey('model-area-$_id'),
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: into
            ? Color.alphaBlend(ring.withValues(alpha: 0.08), t.gridAreaAt(widget.depth))
            : t.gridAreaAt(widget.depth),
        border: Border.all(color: area.ghost ? Colors.transparent : border, width: selected || into ? 1.5 : 1),
        borderRadius: BorderRadius.circular(t.radius),
        boxShadow: [
          if (selected || into) BoxShadow(color: ring.withValues(alpha: 0.22), spreadRadius: 3),
          if (widget.depth == 0 && !area.ghost) BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      padding: EdgeInsets.all(widget.depth == 0 ? t.spacing.md : t.spacing.sm),
      child: widget.clip
          ? ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: _content(context, t, c),
              ),
            )
          : _content(context, t, c),
    );
    final drawn = area.ghost
        ? CustomPaint(
            foregroundPainter: DashedBorderPainter(colour: t.removed, width: t.borderWidth, radius: t.radius),
            child: Opacity(opacity: 0.6, child: card),
          )
        : card;
    return Semantics(
      container: true,
      label: [
        'Area ${area.title}',
        if (area.ghost) 'removed since the base',
        if (area.childCount > 0) '${area.childCount} ${area.childCount == 1 ? 'area' : 'areas'}',
        if (area.folded) 'collapsed',
        if (selected) 'selected',
        if (!area.ghost && c.diff.nodeChange(_id) != null) ModelDiff.describe(c.diff.nodeChange(_id)),
      ].join(', '),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.board.inspect(_id),
          // The card being dragged stays in place, faded, until it lands.
          child: AnimatedOpacity(
            opacity: lifted ? 0.4 : 1,
            duration: duration,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.passthrough,
              children: [
                drawn,
                Positioned(top: t.spacing.xs, right: t.spacing.xs, child: _toolbar(context, t, c)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What follows the pointer while the card is dragged.
  Widget _feedback(ModelTheme t) => Transform.translate(
    offset: const Offset(8, 8),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.focus, width: 1.5),
        borderRadius: BorderRadius.circular(t.radius),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KindChip(style: kindStyle(t, _c.profile, _c.nodeOrGhost(_id)?.kind ?? ''), size: 20),
          SizedBox(width: t.spacing.xs),
          Text(widget.area.title, style: t.standard),
        ],
      ),
    ),
  );

  Widget _content(BuildContext context, ModelTheme t, ModelController c) {
    final area = widget.area;
    final mark = c.overlay?.marks[_id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, t, c),
        if (mark?.value != null) ...[
          SizedBox(height: t.spacing.xs),
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
          SizedBox(height: t.spacing.xs),
          Text(area.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.small),
        ],
        if (!area.folded && area.children.isNotEmpty) ...[
          SizedBox(height: t.spacing.sm),
          GridChildren(areas: area.children, board: widget.board, depth: widget.depth + 1),
        ],
        if (dotEdges(c, _id).isNotEmpty) ...[SizedBox(height: t.spacing.xs), AreaDots(board: widget.board, id: _id)],
      ],
    );
  }

  Widget _header(BuildContext context, ModelTheme t, ModelController c) {
    final area = widget.area;
    final b = widget.board;
    final node = c.nodeOrGhost(_id);
    final style = kindStyle(t, c.profile, node?.kind ?? '');
    final editable = !c.readOnly && !area.ghost;
    final count = area.childCount;
    final kindLabel = style.kind.isNotEmpty ? style.label : '';
    final fold = count == 0
        ? null
        : GestureDetector(
            key: ValueKey('fold-$_id'),
            onTap: () => c.toggleFolded(_id, folded: area.folded),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '$count ${count == 1 ? 'area' : 'areas'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.small,
                    ),
                  ),
                  Icon(area.folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 14, color: t.muted),
                ],
              ),
            ),
          );
    final subtitle = kindLabel.isEmpty && fold == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kindLabel.isNotEmpty)
                Flexible(
                  child: Text(kindLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
                ),
              if (kindLabel.isNotEmpty && fold != null) Text(' · ', style: t.small),
              if (fold != null) Flexible(child: fold),
            ],
          );
    final title = b.renaming == _id
        ? InlineRenameField(controller: b.renameText, onCommit: b.commitRename, onCancel: b.cancelRename)
        : GestureDetector(
            onDoubleTap: editable ? () => b.startRename(_id) : null,
            child: Text(
              area.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: area.ghost ? t.heading.copyWith(decoration: TextDecoration.lineThrough) : t.heading,
            ),
          );
    return Row(
      children: [
        Expanded(
          child: Row(
            key: b.anchor(_id),
            mainAxisSize: MainAxisSize.min,
            children: [
              KindChip(style: style),
              SizedBox(width: t.spacing.xs),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [title, ?subtitle],
                ),
              ),
              ...elementMarks(context, c, _id, edge: false),
            ],
          ),
        ),
        // Room for the hover toolbar, so it never covers the title.
        if (editable)
          AnimatedContainer(width: _hovered ? _toolbarExtent * 2 + 2 : 0, duration: t.standardDuration(context)),
      ],
    );
  }

  /// The side of one hover toolbar button.
  static const _toolbarExtent = 32.0;

  /// The hover toolbar over the card's top-right corner: relate and the
  /// edit menu. Shown on hover; always reachable, so tests need none.
  Widget _toolbar(BuildContext context, ModelTheme t, ModelController c) {
    final area = widget.area;
    if (c.readOnly || area.ghost) return const SizedBox.shrink();
    final tools = [
      DragHandle(
        payload: ConnectArea(_id),
        icon: Icons.trip_origin,
        tooltip: 'Drag to relate ${area.title} to another area',
        extent: _toolbarExtent,
        feedback: _feedback(t),
      ),
      AreaMenu(
        board: widget.board,
        id: _id,
        title: area.title,
        extra: [
          if (area.childCount > 0 && widget.depth > 0)
            ModelMenuItem(label: 'Open', icon: Icons.open_in_full_rounded, onSelected: () => c.drillIn(_id)),
          if (c.sizes.containsKey(_id))
            ModelMenuItem(
              label: 'Reset size',
              icon: Icons.fit_screen_outlined,
              onSelected: () => c.setSizes({_id: null}),
            ),
        ],
      ),
    ];
    if (tools.isEmpty) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _hovered ? 1 : 0,
      duration: t.standardDuration(context),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radius - 2),
          border: Border.all(color: t.divider, width: t.borderWidth),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: tools),
      ),
    );
  }
}
