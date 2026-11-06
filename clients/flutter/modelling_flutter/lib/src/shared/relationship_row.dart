// relationship_row.dart: one relationship as a list row (theme.md §5.8):
// its palette circle, label and ends, with change and lint marks. Used by
// the blocks relationships list, the inspector and the outline.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../controller/model_controller.dart';
import '../theme/model_theme.dart';
import 'markers.dart';

/// "From → To" (or "From — To" when undirected).
String relationshipEnds(ModelController c, Edge e) =>
    '${c.labelOf(e.from)} ${e.undirected ? '—' : '→'} ${c.labelOf(e.to)}';

/// The relationship's palette colour.
Color relationshipColour(ModelController c, ModelTheme t, String edgeId) => t.paletteAt(c.slotOf(edgeId));

/// A pressable row for relationship [edgeId] (current or removed).
class RelationshipRow extends StatefulWidget {
  const RelationshipRow({
    super.key,
    required this.controller,
    required this.edgeId,
    required this.onPressed,
    this.dense = false,
  });

  final ModelController controller;
  final String edgeId;
  final VoidCallback onPressed;
  final bool dense;

  @override
  State<RelationshipRow> createState() => _RelationshipRowState();
}

class _RelationshipRowState extends State<RelationshipRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = widget.controller;
    final e = c.edgeOrGhost(widget.edgeId);
    if (e == null) return const SizedBox.shrink();
    final ghost = c.index.edge(e.id) == null;
    final strike = ghost ? const TextStyle(decoration: TextDecoration.lineThrough) : const TextStyle();
    final row = Container(
      padding: EdgeInsets.all(widget.dense ? t.spacing.xxs : t.spacing.xs),
      decoration: BoxDecoration(color: _hovered ? t.raised : null, borderRadius: BorderRadius.circular(t.radius)),
      child: Row(
        children: [
          Icon(Icons.circle_outlined, size: t.dotSize, color: relationshipColour(c, t, e.id)),
          SizedBox(width: t.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.standard.merge(strike)),
                Text(relationshipEnds(c, e), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
              ],
            ),
          ),
          ...elementMarks(context, c, e.id, edge: true),
        ],
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Relationship ${e.label}, ${relationshipEnds(c, e)}${ghost ? ', removed' : ''}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _hovered = true);
            c.hover(e.id);
          },
          onExit: (_) {
            setState(() => _hovered = false);
            if (c.hovered.value == e.id) c.hover(null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Tooltip(
              message: 'Inspect ${e.label}',
              child: Opacity(opacity: ghost ? 0.55 : 1, child: row),
            ),
          ),
        ),
      ),
    );
  }
}
