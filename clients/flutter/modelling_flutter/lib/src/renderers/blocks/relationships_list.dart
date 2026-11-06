// relationships_list.dart: the collapsible "Relationships · N" list under
// the board (theme.md §5.17); hovering a row previews its connector.

import 'package:flutter/material.dart';

import '../../controller/model_controller.dart';
import '../../shared/relationship_row.dart';
import '../../theme/model_theme.dart';

/// Edge ids the board lists: every relationship (and removed ones in diff
/// mode), or only changed ones under "Changed only".
List<String> listedEdges(ModelController c) => [
  for (final e in c.model.edges)
    if (!c.changedOnly || c.diff.edgeChange(e.id) != null) e.id,
  ...c.diff.removedEdges.keys,
];

class RelationshipsList extends StatefulWidget {
  const RelationshipsList({super.key, required this.controller, required this.onInspect});

  final ModelController controller;
  final ValueChanged<String> onInspect;

  @override
  State<RelationshipsList> createState() => _RelationshipsListState();
}

class _RelationshipsListState extends State<RelationshipsList> {
  var _open = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final ids = listedEdges(widget.controller);
    final duration = t.standardDuration(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: _open ? 'Hide relationships' : 'Show relationships',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: EdgeInsets.all(t.spacing.xs),
                decoration: BoxDecoration(
                  color: _hovered ? t.raised : null,
                  borderRadius: BorderRadius.circular(t.radius),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Relationships · ${ids.length}',
                        style: t.standard.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: duration,
                      child: Icon(Icons.chevron_right, size: t.iconSize, color: t.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final id in ids)
                      RelationshipRow(controller: widget.controller, edgeId: id, onPressed: () => widget.onInspect(id)),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
