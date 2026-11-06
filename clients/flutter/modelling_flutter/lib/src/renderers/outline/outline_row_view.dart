// outline_row_view.dart: one outline row: an area (fold toggle, label or
// rename field, kind, marks, inspect) or a relationship under its area.

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../shared/inline_rename.dart';
import '../../shared/markers.dart';
import '../../shared/relationship_row.dart';
import '../../theme/model_theme.dart';
import 'outline_rows.dart';

class OutlineRowView extends StatelessWidget {
  const OutlineRowView({
    super.key,
    required this.row,
    required this.controller,
    required this.renaming,
    required this.renameText,
    required this.onCommitRename,
    required this.onCancelRename,
    required this.onPress,
    required this.onRename,
    required this.onInspect,
  });

  final OutlineRow row;
  final ModelController controller;
  final bool renaming;
  final TextEditingController renameText;
  final VoidCallback onCommitRename;
  final VoidCallback onCancelRename;
  final ValueChanged<String> onPress;
  final ValueChanged<String> onRename;
  final ValueChanged<ModelElementRef> onInspect;

  @override
  Widget build(BuildContext context) => row.isArea ? _area(context) : _edge(context);

  Widget _area(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final n = c.nodeOrGhost(row.id)!;
    final focused = c.focused == row.id;
    final selected = c.selection == ModelElementRef.node(row.id);
    final editable = !c.readOnly && !row.ghost;
    final kind = n.kind.isEmpty ? '' : (c.profile?.nodeKinds[n.kind]?.label ?? n.kind);
    final label = renaming
        ? InlineRenameField(controller: renameText, onCommit: onCommitRename, onCancel: onCancelRename)
        : Text(
            n.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.standard.copyWith(
              fontWeight: FontWeight.w500,
              decoration: row.ghost ? TextDecoration.lineThrough : null,
            ),
          );
    final content = Container(
      key: ValueKey('outline-${row.id}'),
      padding: EdgeInsets.only(left: row.depth * t.indent, right: t.spacing.xxs),
      decoration: BoxDecoration(
        color: selected || focused ? t.raised : null,
        border: Border.all(color: focused ? t.focus : const Color(0x00000000), width: t.borderWidth),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: row.childCount == 0
                ? null
                : chrome.iconButton(
                    icon: row.folded ? Icons.chevron_right : Icons.expand_more,
                    tooltip: '${row.folded ? 'Expand' : 'Collapse'} ${n.label}',
                    onPressed: () => c.toggleFolded(row.id, folded: row.folded),
                  ),
          ),
          Flexible(child: label),
          if (kind.isNotEmpty && !renaming) ...[
            SizedBox(width: t.spacing.xs),
            Flexible(
              flex: 0,
              child: Text(kind, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
            ),
          ],
          ...elementMarks(context, c, row.id, edge: false),
          const Spacer(),
          chrome.iconButton(
            icon: Icons.info_outline,
            tooltip: 'Inspect ${n.label}',
            onPressed: () => onInspect(ModelElementRef.node(row.id)),
          ),
        ],
      ),
    );
    return Semantics(
      label: [
        'Area ${n.label}',
        'level ${row.depth + 1}',
        if (kind.isNotEmpty) kind,
        if (row.childCount > 0) row.folded ? 'collapsed' : 'expanded',
        if (row.ghost) 'removed since the base',
      ].join(', '),
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPress(row.id),
        onDoubleTap: editable ? () => onRename(row.id) : null,
        child: Opacity(opacity: row.ghost ? 0.55 : 1, child: content),
      ),
    );
  }

  Widget _edge(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = controller;
    final e = c.edgeOrGhost(row.edgeId!)!;
    return Padding(
      key: ValueKey('outline-edge-${e.id}'),
      padding: EdgeInsets.only(left: row.depth * t.indent + 28),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => c.hover(e.id),
        onExit: (_) {
          if (c.hovered.value == e.id) c.hover(null);
        },
        child: Semantics(
          button: true,
          label: 'Relationship ${e.label} to ${c.labelOf(e.to)}${row.ghost ? ', removed' : ''}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onInspect(ModelElementRef.edge(e.id)),
            child: Opacity(
              opacity: row.ghost ? 0.55 : 1,
              child: Row(
                children: [
                  Icon(
                    e.undirected ? Icons.remove : Icons.arrow_forward,
                    size: 14,
                    color: relationshipColour(c, t, e.id),
                  ),
                  SizedBox(width: t.spacing.xs),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: e.label,
                            style: t.small.copyWith(
                              color: t.text,
                              decoration: row.ghost ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          TextSpan(text: '  ${c.labelOf(e.to == row.id ? e.from : e.to)}', style: t.small),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...elementMarks(context, c, e.id, edge: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
