// inspector.dart: the one inspector every renderer opens (design §7.2,
// theme.md §5.17): an area's or relationship's values, evidence,
// relationships, link, changes and lint. Read-only mode shows values; edit
// mode edits through operations, so everything is undoable. A host with a
// docked inspector (ModelHooks.onInspect) gets the selection instead of a
// dialog.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/model_diff.dart';
import '../shared/relationship_row.dart';
import '../workspace/model_hooks.dart';
import 'inspector_body.dart';

/// Opens the inspector for [element] (an area or relationship, current or
/// removed) and selects it: a dialog, or the host's docked inspector when
/// its hooks have `onInspect`.
Future<void> inspectElement(BuildContext context, ModelController c, ModelElementRef element) {
  c.select(element);
  final hooks = ModelHooks.of(context);
  if (hooks.onInspect != null) {
    hooks.onInspect!(element);
    return Future.value();
  }
  final scopes = captureModelScopes(context);
  final chrome = ModelChrome.of(context);
  final node = element.isNode ? c.nodeOrGhost(element.id) : null;
  final edge = element.isNode ? null : c.edgeOrGhost(element.id);
  if (node == null && edge == null) return Future.value();

  void reopen(BuildContext dialog, ModelElementRef next) {
    Navigator.of(dialog).pop();
    inspectElement(context, c, next);
  }

  return chrome.showInspector(
    context,
    title: node?.label ?? edge!.label,
    subtitle: inspectorSubtitle(c, element),
    actions: (dialog) =>
        inspectorActions(dialog, c, element, hooks: hooks, chrome: chrome, close: () => Navigator.of(dialog).pop()),
    body: (dialog) => scopes(
      ListenableBuilder(
        listenable: c,
        builder: (context, _) => element.isNode
            ? NodeInspectorBody(
                controller: c,
                id: element.id,
                onInspect: (id) => reopen(dialog, ModelElementRef.edge(id)),
              )
            : EdgeInspectorBody(
                controller: c,
                id: element.id,
                onInspect: (id) => reopen(dialog, ModelElementRef.node(id)),
              ),
      ),
    ),
  );
}

/// "Area · id" (with [area] for "Area") or the relationship's ends, then
/// how it changed.
String inspectorSubtitle(ModelController c, ModelElementRef element, {String area = 'Area'}) {
  final node = element.isNode ? c.nodeOrGhost(element.id) : null;
  final edge = element.isNode ? null : c.edgeOrGhost(element.id);
  final change = element.isNode ? c.diff.nodeChange(element.id) : c.diff.edgeChange(element.id);
  return [
    if (node != null) '$area · ${node.id}' else if (edge != null) relationshipEnds(c, edge),
    if (change != null) ModelDiff.describe(change),
  ].join(' · ');
}

/// The inspector's actions for [element]: attach evidence, delete, open
/// the linked model. [close] runs before an action that leaves the
/// inspector (null when it is docked and stays). A dialog passes the
/// [hooks] and [chrome] it captured, since it is built outside their scopes.
List<Widget> inspectorActions(
  BuildContext context,
  ModelController c,
  ModelElementRef element, {
  VoidCallback? close,
  ModelHooks? hooks,
  ModelChrome? chrome,
}) {
  final ui = chrome ?? ModelChrome.of(context);
  final host = hooks ?? ModelHooks.of(context);
  final node = element.isNode ? c.nodeOrGhost(element.id) : null;
  final edge = element.isNode ? null : c.edgeOrGhost(element.id);
  if (node == null && edge == null) return const [];
  final ghost = !(element.isNode ? c.index.node(element.id) != null : c.index.edge(element.id) != null);
  return [
    if (host.onAttachEvidence != null && !ghost)
      ui.button(
        label: 'Attach evidence',
        icon: Icons.attach_file,
        onPressed: () {
          close?.call();
          host.onAttachEvidence!(element);
        },
      ),
    if (!c.readOnly && !ghost)
      ui.button(
        key: const ValueKey('inspector-delete'),
        label: node != null ? 'Delete area' : 'Delete relationship',
        icon: Icons.delete_outline,
        variant: ModelButtonVariant.ghost,
        onPressed: () async {
          final ok = node != null ? await confirmDeleteNode(context, c, node.id, chrome: ui) : c.deleteEdge(edge!.id);
          if (ok && context.mounted) close?.call();
        },
      ),
    if (node?.link != null && host.onOpenLink != null)
      ui.button(
        label: host.openLabel,
        icon: Icons.chevron_right,
        variant: ModelButtonVariant.primary,
        onPressed: () {
          close?.call();
          host.onOpenLink!(node!.link!);
        },
      ),
  ];
}

/// Deletes an area, asking first when that takes nested areas or
/// relationships with it. Returns whether it was deleted.
Future<bool> confirmDeleteNode(BuildContext context, ModelController c, String id, {ModelChrome? chrome}) async {
  final (areas, relationships) = c.removalOf(id);
  if (areas > 0 || relationships > 0) {
    final parts = [
      if (areas > 0) '$areas nested ${areas == 1 ? 'area' : 'areas'}',
      if (relationships > 0) '$relationships ${relationships == 1 ? 'relationship' : 'relationships'}',
    ];
    final ok = await (chrome ?? ModelChrome.of(context)).confirm(
      context,
      title: 'Delete ${c.labelOf(id)}?',
      message: 'This also deletes ${parts.join(' and ')}.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
  }
  return c.deleteNode(id);
}
