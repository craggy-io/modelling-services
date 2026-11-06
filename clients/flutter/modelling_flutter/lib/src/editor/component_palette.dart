// component_palette.dart: the editor's palette of components to add: the
// profile's node kinds (else a few generic ones) as tiles with their icon
// and colour. Drag a tile onto the board or onto an area to add a child of
// that kind; click it to add inside the selected area.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../shared/drag_payloads.dart';
import '../shared/kind_style.dart';
import '../theme/model_theme.dart';

/// Where a palette click adds: inside the selected area, else in the
/// drilled-in area, else at the top level.
String paletteTarget(ModelController c) {
  final sel = c.selection;
  return sel != null && sel.isNode && c.index.node(sel.id) != null ? sel.id : c.region ?? '';
}

class ComponentPalette extends StatelessWidget {
  const ComponentPalette({super.key, required this.controller});

  final ModelController controller;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = controller;
    final kinds = paletteKinds(c.profile);
    final target = paletteTarget(c);
    return LayoutBuilder(
      builder: (context, bounds) {
        final columns = bounds.maxWidth >= 300 ? 3 : 2;
        final width = (bounds.maxWidth - (columns - 1) * t.spacing.xs) / columns;
        return Wrap(
          spacing: t.spacing.xs,
          runSpacing: t.spacing.xs,
          children: [
            for (final (kind, label) in kinds)
              SizedBox(
                width: width,
                child: _Tile(
                  style: kindStyle(t, c.profile, kind),
                  label: label,
                  refusal: c.childRefusal(target, kind),
                  onAdd: () => c.addKind(target, kind, label: label),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.style, required this.label, required this.refusal, required this.onAdd});

  final KindStyle style;
  final String label;
  final String? refusal;
  final VoidCallback onAdd;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  var _hovered = false;

  Widget _body(ModelTheme t, {bool lifted = false}) => AnimatedContainer(
    duration: t.standardDuration(context),
    height: 64,
    padding: EdgeInsets.all(t.spacing.xs),
    decoration: BoxDecoration(
      color: _hovered || lifted ? t.hover : t.raised,
      borderRadius: BorderRadius.circular(t.radius),
      border: Border.all(color: _hovered || lifted ? widget.style.colour.withValues(alpha: 0.6) : t.divider),
      boxShadow: lifted ? [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, 6))] : null,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        KindChip(style: widget.style, size: 24),
        SizedBox(height: t.spacing.xxs),
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.small.copyWith(color: t.text),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final s = widget.style;
    final tip =
        widget.refusal ?? 'Drag onto the board, or click to add ${indefiniteArticle(widget.label)} ${widget.label}';
    return Semantics(
      button: true,
      label: 'Add ${widget.label}',
      child: Draggable<Object>(
        data: AddArea(s.kind, widget.label),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ModelThemeScope(
          theme: t,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(width: 96, child: _body(t, lifted: true)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.5, child: _body(t)),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ModelChrome.of(context).tooltip(
            message: tip,
            child: GestureDetector(
              key: ValueKey('palette-${s.kind.isEmpty ? 'area' : s.kind}'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onAdd,
              child: _body(t),
            ),
          ),
        ),
      ),
    );
  }
}
