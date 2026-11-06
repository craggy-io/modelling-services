// inspector_sections.dart: the inspector's read-mostly sections: evidence,
// relationships, changes from the base, lint findings and plain values.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/markers.dart';
import '../shared/model_diff.dart';
import '../shared/relationship_row.dart';
import '../theme/model_theme.dart';
import '../workspace/model_hooks.dart';
import 'field_editors.dart';

/// An overline heading and its contents, spaced like theme.md §5.17.
class InspectorSection extends StatelessWidget {
  const InspectorSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    if (ModelHooks.of(context).onInspect != null) {
      // Docked: a hairline between sections and room around each.
      return Container(
        padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: t.divider, width: t.borderWidth),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: t.overline),
            SizedBox(height: t.spacing.xs),
            ...children,
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: t.overline),
          SizedBox(height: t.spacing.xxs),
          ...children,
        ],
      ),
    );
  }
}

/// A "Name: value" line for read-only values.
class InspectorValue extends StatelessWidget {
  const InspectorValue(this.name, this.value, {super.key});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.xxs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$name  ', style: t.small),
            TextSpan(text: value, style: t.standard),
          ],
        ),
      ),
    );
  }
}

/// The evidence an element cites: open each through the host, remove
/// (when editable).
class EvidenceSection extends StatelessWidget {
  const EvidenceSection({
    super.key,
    required this.controller,
    required this.element,
    required this.evidence,
    required this.editable,
  });

  final ModelController controller;
  final ModelElementRef element;
  final List<Evidence> evidence;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final open = ModelHooks.of(context).onEvidence;
    final docked = ModelHooks.of(context).onInspect != null;
    return InspectorSection(
      title: 'Evidence',
      children: [
        if (evidence.isEmpty) Text('No evidence cited.', style: t.small),
        for (final e in evidence)
          Padding(
            padding: EdgeInsets.only(top: t.spacing.xxs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.caption, style: t.standard),
                      Text(
                        [
                          if (e.ref.scheme != 'artifact') e.ref.scheme,
                          e.ref.id,
                          if (e.ref.selector.isNotEmpty) e.ref.selector,
                        ].join(' · '),
                        style: t.small,
                      ),
                    ],
                  ),
                ),
                if (open != null)
                  chrome.iconButton(
                    icon: Icons.open_in_new,
                    tooltip: 'Open evidence',
                    onPressed: () {
                      if (!docked) Navigator.of(context).pop();
                      open(e.ref);
                    },
                  ),
                if (editable)
                  chrome.iconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Remove evidence ${e.caption}',
                    onPressed: () => controller.removeEvidence(element, e.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The relationships touching an area; each opens its own inspector.
class RelationshipsSection extends StatelessWidget {
  const RelationshipsSection({super.key, required this.controller, required this.nodeId, required this.onInspect});

  final ModelController controller;
  final String nodeId;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) {
    final ids = controller.diff.hasBase ? controller.diff.edgesAt(nodeId) : controller.index.touching(nodeId);
    if (ids.isEmpty) return const SizedBox.shrink();
    return InspectorSection(
      title: 'Relationships',
      children: [
        for (final id in ids)
          RelationshipRow(controller: controller, edgeId: id, dense: true, onPressed: () => onInspect(id)),
      ],
    );
  }
}

String _show(Object? v) => switch (v) {
  null => '(none)',
  String s when s.isEmpty => '(empty)',
  String s => s,
  _ => v is num || v is bool ? propertyText(v) : jsonEncode(v),
};

/// Each field that differs from the base: old → new.
class ChangesSection extends StatelessWidget {
  const ChangesSection({super.key, required this.controller, required this.element});

  final ModelController controller;
  final ModelElementRef element;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final d = controller.diff;
    final kind = element.isNode ? d.nodeChange(element.id) : d.edgeChange(element.id);
    if (kind == null) return const SizedBox.shrink();
    final fields = d.fields(element.id, edge: !element.isNode);
    return InspectorSection(
      title: 'Changes from the base',
      children: [
        Row(
          children: [
            ChangeMarker(kind),
            SizedBox(width: t.spacing.xs),
            Text(ModelDiff.describe(kind), style: t.small),
          ],
        ),
        for (final f in fields)
          Padding(
            padding: EdgeInsets.only(top: t.spacing.xxs),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${f.field}  ', style: t.small),
                  TextSpan(
                    text: _show(f.from),
                    style: t.standard.copyWith(color: t.removed),
                  ),
                  TextSpan(text: '  →  ', style: t.small),
                  TextSpan(
                    text: _show(f.to),
                    style: t.standard.copyWith(color: t.added),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Lint findings about one element.
class LintSection extends StatelessWidget {
  const LintSection({super.key, required this.findings});

  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const SizedBox.shrink();
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    return InspectorSection(
      title: 'Checks',
      children: [
        for (final f in findings)
          Padding(
            padding: EdgeInsets.only(top: t.spacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: t.spacing.xxs + 1),
                  child: chrome.statusDot(color: severityColour(t, f.severity), tooltip: f.severity.name),
                ),
                SizedBox(width: t.spacing.xs),
                Expanded(child: Text(f.message, style: t.standard)),
              ],
            ),
          ),
      ],
    );
  }
}
