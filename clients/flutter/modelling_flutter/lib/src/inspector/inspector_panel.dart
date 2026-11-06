// inspector_panel.dart: the inspector docked in the editor's right panel.
// It follows the selection: an area's or relationship's header, actions and
// the same sections as the dialog; with nothing selected, the model
// overview.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_types.dart';
import '../shared/kind_style.dart';
import '../theme/model_theme.dart';
import 'inspector.dart';
import 'inspector_body.dart';
import 'model_overview.dart';

class DockedInspector extends StatelessWidget {
  const DockedInspector({super.key, required this.controller, this.profiles = const []});

  final ModelController controller;

  /// Profiles the overview offers to pick from.
  final List<Profile> profiles;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final sel = c.selection;
    if (sel == null || !c.exists(sel)) return ModelOverview(controller: c, profiles: profiles);
    return Column(
      key: ValueKey('docked-inspector-$sel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(controller: c, element: sel),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: ModelTheme.of(context).spacing.xl),
            child: sel.isNode
                ? NodeInspectorBody(controller: c, id: sel.id, onInspect: (id) => c.select(ModelElementRef.edge(id)))
                : EdgeInspectorBody(controller: c, id: sel.id, onInspect: (id) => c.select(ModelElementRef.node(id))),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.element});

  final ModelController controller;
  final ModelElementRef element;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final node = element.isNode ? c.nodeOrGhost(element.id) : null;
    final edge = element.isNode ? null : c.edgeOrGhost(element.id);
    final style = node != null ? kindStyle(t, c.profile, node.kind) : null;
    final actions = inspectorActions(context, c, element);
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.md, t.spacing.xs, t.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (style != null)
                KindChip(style: style, size: 32)
              else
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.paletteAt(c.slotOf(element.id)).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: t.paletteAt(c.slotOf(element.id))),
                ),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node?.label ?? edge!.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.heading.copyWith(fontSize: (t.heading.fontSize ?? 15) + 2),
                    ),
                    SizedBox(height: t.spacing.xxs / 2),
                    Text(
                      inspectorSubtitle(c, element, area: style?.label ?? 'Area'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.small,
                    ),
                  ],
                ),
              ),
              chrome.iconButton(
                key: const ValueKey('inspector-close'),
                icon: Icons.close_rounded,
                tooltip: 'Clear selection',
                onPressed: () => c.select(null),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            SizedBox(height: t.spacing.sm),
            Wrap(spacing: t.spacing.xs, runSpacing: t.spacing.xs, children: actions),
          ],
        ],
      ),
    );
  }
}
