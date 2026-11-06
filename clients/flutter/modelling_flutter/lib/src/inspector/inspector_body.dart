// inspector_body.dart: what the inspector shows for an area or a
// relationship, in the dialog and in the editor's docked panel alike.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/relationship_row.dart';
import '../shared/tags_field.dart';
import '../theme/model_theme.dart';
import '../workspace/model_hooks.dart';
import 'field_editors.dart';
import 'inspector_sections.dart';

/// An area's inspector contents: fields (or values when read-only),
/// properties, relationships, evidence, changes and lint.
class NodeInspectorBody extends StatelessWidget {
  const NodeInspectorBody({super.key, required this.controller, required this.id, required this.onInspect});

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
        ..._details(context, [
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
              TagsField(
                key: const ValueKey('inspector-tags'),
                label: 'Tags',
                tags: n.tags,
                onChanged: (tags) => c.setTags(ref, tags),
              ),
            ),
            _gap(
              t,
              CommitField(
                key: const ValueKey('inspector-link'),
                label: 'Links to model',
                value: n.link?.model ?? '',
                onCommit: (v) =>
                    c.setFields(ref, {
                      'link': v.trim().isEmpty ? null : Link(model: v.trim(), node: n.link?.node ?? ''),
                    })
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
        ]),
        _properties(c, ref, n.kind, n.properties, editable),
        RelationshipsSection(controller: c, nodeId: id, onInspect: onInspect),
        EvidenceSection(controller: c, element: ref, evidence: n.evidence, editable: editable),
        ChangesSection(controller: c, element: ref),
        LintSection(findings: c.lintFor(id)),
      ],
    );
  }
}

/// A relationship's inspector contents.
class EdgeInspectorBody extends StatelessWidget {
  const EdgeInspectorBody({super.key, required this.controller, required this.id, required this.onInspect});

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
        ..._details(context, [
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
        ]),
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

/// The fields above the sections: a "Details" section when docked, else
/// as they are.
List<Widget> _details(BuildContext context, List<Widget> fields) =>
    ModelHooks.of(context).onInspect == null ? fields : [InspectorSection(title: 'Details', children: fields)];

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
