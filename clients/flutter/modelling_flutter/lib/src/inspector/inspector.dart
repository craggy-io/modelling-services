// inspector.dart: the one inspector every renderer opens (design §7.2,
// theme.md §5.17): an area's or relationship's values, evidence,
// relationships, link, changes and lint. Read-only mode shows values; edit
// mode edits through operations, so everything is undoable.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/model_diff.dart';
import '../shared/relationship_row.dart';
import '../theme/model_theme.dart';
import '../workspace/model_hooks.dart';
import 'field_editors.dart';
import 'inspector_sections.dart';

/// Opens the inspector for [element] (an area or relationship, current or
/// removed) and selects it.
Future<void> inspectElement(BuildContext context, ModelController c, ModelElementRef element) {
  c.select(element);
  final scopes = captureModelScopes(context);
  final chrome = ModelChrome.of(context);
  final hooks = ModelHooks.of(context);
  final node = element.isNode ? c.nodeOrGhost(element.id) : null;
  final edge = element.isNode ? null : c.edgeOrGhost(element.id);
  if (node == null && edge == null) return Future.value();
  final ghost = !(element.isNode ? c.index.node(element.id) != null : c.index.edge(element.id) != null);
  final change = element.isNode ? c.diff.nodeChange(element.id) : c.diff.edgeChange(element.id);
  final subtitle = [
    if (node != null) 'Area · ${node.id}' else relationshipEnds(c, edge!),
    if (change != null) ModelDiff.describe(change),
  ].join(' · ');

  void reopen(BuildContext dialog, ModelElementRef next) {
    Navigator.of(dialog).pop();
    inspectElement(context, c, next);
  }

  return chrome.showInspector(
    context,
    title: node?.label ?? edge!.label,
    subtitle: subtitle,
    actions: (dialog) => [
      if (hooks.onAttachEvidence != null && !ghost)
        chrome.button(
          label: 'Attach evidence',
          icon: Icons.attach_file,
          onPressed: () {
            Navigator.of(dialog).pop();
            hooks.onAttachEvidence!(element);
          },
        ),
      if (!c.readOnly && !ghost)
        chrome.button(
          label: node != null ? 'Delete area' : 'Delete relationship',
          icon: Icons.delete_outline,
          variant: ModelButtonVariant.ghost,
          onPressed: () async {
            final ok = node != null
                ? await confirmDeleteNode(dialog, c, node.id, chrome: chrome)
                : c.deleteEdge(edge!.id);
            if (ok && dialog.mounted) Navigator.of(dialog).pop();
          },
        ),
      if (node?.link != null && hooks.onOpenLink != null)
        chrome.button(
          label: hooks.openLabel,
          icon: Icons.chevron_right,
          variant: ModelButtonVariant.primary,
          onPressed: () {
            Navigator.of(dialog).pop();
            hooks.onOpenLink!(node!.link!);
          },
        ),
    ],
    body: (dialog) => scopes(
      ListenableBuilder(
        listenable: c,
        builder: (context, _) => element.isNode
            ? _NodeBody(controller: c, id: element.id, onInspect: (id) => reopen(dialog, ModelElementRef.edge(id)))
            : _EdgeBody(controller: c, id: element.id, onInspect: (id) => reopen(dialog, ModelElementRef.node(id))),
      ),
    ),
  );
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

class _NodeBody extends StatelessWidget {
  const _NodeBody({required this.controller, required this.id, required this.onInspect});

  final ModelController controller;
  final String id;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = ModelTheme.of(context);
    final n = c.nodeOrGhost(id);
    if (n == null) return Text('This area no longer exists.', style: t.small);
    final ref = ModelElementRef.node(id);
    final editable = !c.readOnly && c.index.node(id) != null;
    final kinds = c.profile?.nodeKinds ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable) ...[
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-label'),
              label: 'Label',
              value: n.label,
              onCommit: (v) => c.rename(ref, v) ? null : 'A label cannot be blank',
            ),
          ),
          _gap(t, _kindEditor(context, c, ref, n.kind, {for (final e in kinds.entries) e.key: e.value.label})),
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-notes'),
              label: 'Notes',
              value: n.notes,
              multiline: true,
              onCommit: (v) => c.setFields(ref, {'notes': v}) ? null : c.notice.value,
            ),
          ),
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-tags'),
              label: 'Tags',
              hint: 'Comma-separated',
              value: n.tags.join(', '),
              onCommit: (v) => c.setFields(ref, {'tags': parseTags(v)}) ? null : c.notice.value,
            ),
          ),
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-link'),
              label: 'Links to model',
              value: n.link?.model ?? '',
              onCommit: (v) =>
                  c.setFields(ref, {'link': v.trim().isEmpty ? null : Link(model: v.trim(), node: n.link?.node ?? '')})
                  ? null
                  : c.notice.value,
            ),
          ),
        ] else ...[
          if (n.notes.isNotEmpty) _gap(t, SelectableText(n.notes, style: t.standard)),
          if (n.kind.isNotEmpty) InspectorValue('Kind', kinds[n.kind]?.label ?? n.kind),
          if (n.tags.isNotEmpty) InspectorValue('Tags', n.tags.join(', ')),
          if (n.link != null)
            InspectorValue('Links to', [n.link!.model, if (n.link!.node.isNotEmpty) n.link!.node].join(' · ')),
          if (n.kind.isNotEmpty || n.tags.isNotEmpty || n.link != null) SizedBox(height: t.spacing.sm),
        ],
        _properties(c, ref, n.kind, n.properties, editable),
        RelationshipsSection(controller: c, nodeId: id, onInspect: onInspect),
        EvidenceSection(controller: c, element: ref, evidence: n.evidence, editable: editable),
        ChangesSection(controller: c, element: ref),
        LintSection(findings: c.lintFor(id)),
      ],
    );
  }
}

class _EdgeBody extends StatelessWidget {
  const _EdgeBody({required this.controller, required this.id, required this.onInspect});

  final ModelController controller;
  final String id;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final e = c.edgeOrGhost(id);
    if (e == null) return Text('This relationship no longer exists.', style: t.small);
    final ref = ModelElementRef.edge(id);
    final editable = !c.readOnly && c.index.edge(id) != null;
    final kinds = c.profile?.edgeKinds ?? const {};
    final nodes = [for (final n in c.model.nodes) ModelOption(n.id, n.label)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable) ...[
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-label'),
              label: 'Label',
              value: e.label,
              onCommit: (v) => c.rename(ref, v) ? null : 'A label cannot be blank',
            ),
          ),
          _gap(
            t,
            Row(
              children: [
                Expanded(
                  child: chrome.select<String>(
                    key: const ValueKey('inspector-from'),
                    label: 'From',
                    value: e.from,
                    options: nodes,
                    onChanged: (v) => c.setFields(ref, {'from': v}),
                  ),
                ),
                SizedBox(width: t.spacing.xs),
                Expanded(
                  child: chrome.select<String>(
                    key: const ValueKey('inspector-to'),
                    label: 'To',
                    value: e.to,
                    options: nodes,
                    onChanged: (v) => c.setFields(ref, {'to': v}),
                  ),
                ),
              ],
            ),
          ),
          _gap(t, _kindEditor(context, c, ref, e.kind, {for (final k in kinds.entries) k.key: k.value.label})),
          _gap(
            t,
            Align(
              alignment: Alignment.centerLeft,
              child: chrome.filterChip(
                label: 'Undirected',
                selected: e.undirected,
                tooltip: e.undirected ? 'Give it a direction' : 'Remove its direction',
                onPressed: () => c.setFields(ref, {'undirected': !e.undirected}),
              ),
            ),
          ),
          _gap(
            t,
            CommitField(
              key: const ValueKey('inspector-notes'),
              label: 'Notes',
              value: e.notes,
              multiline: true,
              onCommit: (v) => c.setFields(ref, {'notes': v}) ? null : c.notice.value,
            ),
          ),
        ] else ...[
          if (e.notes.isNotEmpty) _gap(t, SelectableText(e.notes, style: t.standard)),
          InspectorValue('Ends', relationshipEnds(c, e)),
          if (e.kind.isNotEmpty) InspectorValue('Kind', kinds[e.kind]?.label ?? e.kind),
          if (e.undirected) const InspectorValue('Direction', 'Undirected'),
          SizedBox(height: t.spacing.sm),
        ],
        if (!editable)
          InspectorSection(
            title: 'Ends',
            children: [
              for (final end in {e.from, e.to})
                chrome.button(
                  label: c.labelOf(end),
                  variant: ModelButtonVariant.link,
                  size: ModelButtonSize.sm,
                  onPressed: () => onInspect(end),
                ),
            ],
          ),
        _properties(c, ref, e.kind, e.properties, editable),
        EvidenceSection(controller: c, element: ref, evidence: e.evidence, editable: editable),
        ChangesSection(controller: c, element: ref),
        LintSection(findings: c.lintFor(id)),
      ],
    );
  }
}

Widget _gap(ModelTheme t, Widget child) => Padding(
  padding: EdgeInsets.only(bottom: t.spacing.sm),
  child: child,
);

/// A select over the profile's kinds, or a free text field without one.
Widget _kindEditor(
  BuildContext context,
  ModelController c,
  ModelElementRef ref,
  String kind,
  Map<String, String> kinds,
) {
  if (kinds.isEmpty) {
    return CommitField(
      key: const ValueKey('inspector-kind'),
      label: 'Kind',
      value: kind,
      onCommit: (v) => c.setFields(ref, {'kind': v.trim()}) ? null : c.notice.value,
    );
  }
  return ModelChrome.of(context).select<String>(
    key: const ValueKey('inspector-kind'),
    label: 'Kind',
    value: kind,
    options: [
      const ModelOption('', '(none)'),
      for (final e in kinds.entries) ModelOption(e.key, e.value),
      if (kind.isNotEmpty && !kinds.containsKey(kind)) ModelOption(kind, '$kind (not in the profile)'),
    ],
    onChanged: (v) => c.setFields(ref, {'kind': v}),
  );
}

Widget _properties(ModelController c, ModelElementRef ref, String kind, Properties props, bool editable) {
  if (editable) {
    return InspectorSection(
      title: 'Properties',
      children: [PropertiesEditor(controller: c, element: ref, kind: kind, properties: props)],
    );
  }
  if (props.isEmpty) return const SizedBox.shrink();
  final keys = props.keys.toList()..sort();
  return InspectorSection(
    title: 'Properties',
    children: [for (final k in keys) InspectorValue(k, propertyText(props[k]))],
  );
}
