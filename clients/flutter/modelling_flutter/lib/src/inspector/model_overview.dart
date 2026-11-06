// model_overview.dart: the docked inspector with nothing selected: the
// model's title, subject and notes (editable), its profile, a summary of
// what is in it and its lint findings, each of which selects its element.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../shared/markers.dart';
import '../theme/model_theme.dart';
import 'field_editors.dart';
import 'inspector_sections.dart';

/// Findings by severity: errors, warnings, info.
(int, int, int) lintCounts(List<Finding> findings) => (
  findings.where((f) => f.severity == Severity.error).length,
  findings.where((f) => f.severity == Severity.warning).length,
  findings.where((f) => f.severity == Severity.info).length,
);

class ModelOverview extends StatelessWidget {
  const ModelOverview({super.key, required this.controller, this.profiles = const []});

  final ModelController controller;
  final List<Profile> profiles;

  /// Findings listed before "and N more".
  static const shownFindings = 8;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final m = c.model;
    final editable = !c.readOnly;
    final (errors, warnings, info) = lintCounts(c.lint);
    final findings = c.lint;
    Widget field(String key, String label, String value, {bool multiline = false}) => Padding(
      padding: EdgeInsets.only(bottom: t.spacing.sm),
      child: CommitField(
        key: ValueKey('overview-$key'),
        label: label,
        value: value,
        multiline: multiline,
        onCommit: (v) {
          if (key != 'notes' && v.trim().isEmpty) return 'A $key cannot be blank';
          return c.tryApply([
                Op.modelSet({key: key == 'notes' ? v : v.trim()}),
              ])
              ? null
              : c.notice.value;
        },
      ),
    );
    return ListView(
      key: const ValueKey('model-overview'),
      padding: EdgeInsets.only(bottom: t.spacing.xl),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.md, t.spacing.md, t.spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MODEL', style: t.overline),
              SizedBox(height: t.spacing.xxs),
              Text(m.title, style: t.heading.copyWith(fontSize: (t.heading.fontSize ?? 15) + 2)),
              if (m.subject.isNotEmpty) Text(m.subject, style: t.small),
            ],
          ),
        ),
        InspectorSection(
          title: 'Details',
          children: editable
              ? [
                  field('title', 'Title', m.title),
                  field('subject', 'Subject', m.subject),
                  field('notes', 'Notes', m.notes, multiline: true),
                ]
              : [
                  if (m.notes.isNotEmpty)
                    SelectableText(m.notes, style: t.standard)
                  else
                    Text('No notes.', style: t.small),
                ],
        ),
        if (profiles.isNotEmpty || c.profile != null)
          InspectorSection(
            title: 'Profile',
            children: [
              chrome.select<Profile?>(
                key: const ValueKey('profile-picker'),
                label: 'Profile',
                value: c.profile,
                options: [
                  const ModelOption<Profile?>(null, 'No profile'),
                  for (final p in {...profiles, ?c.profile}) ModelOption<Profile?>(p, p.title.isEmpty ? p.id : p.title),
                ],
                onChanged: editable ? (p) => c.useProfile(p) : null,
              ),
            ],
          ),
        InspectorSection(
          title: 'Summary',
          children: [
            _Stat(label: 'Areas', value: '${m.nodes.length}'),
            _Stat(label: 'Top-level areas', value: '${c.index.children('').length}'),
            _Stat(label: 'Relationships', value: '${m.edges.length}'),
            _Stat(
              label: 'Kinds in use',
              value:
                  '${{for (final n in m.nodes)
                    if (n.kind.isNotEmpty) n.kind}.length}',
            ),
            if (!c.diff.isEmpty) _Stat(label: 'Changed from the base', value: '${c.diff.count}'),
          ],
        ),
        InspectorSection(
          title: 'Checks',
          children: [
            Wrap(
              spacing: t.spacing.xs,
              runSpacing: t.spacing.xs,
              children: [
                ModelBadge(text: '$errors errors', colour: t.lintError, icon: Icons.error_outline_rounded),
                ModelBadge(text: '$warnings warnings', colour: t.lintWarning, icon: Icons.warning_amber_rounded),
                ModelBadge(text: '$info info', colour: t.lintInfo, icon: Icons.info_outline_rounded),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            if (findings.isEmpty) Text('No findings. The model passes every check.', style: t.small),
            for (final f in findings.take(shownFindings)) _FindingRow(controller: c, finding: f),
            if (findings.length > shownFindings)
              Padding(
                padding: EdgeInsets.only(top: t.spacing.xxs),
                child: Text('and ${findings.length - shownFindings} more', style: t.small),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xxs / 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.small)),
          Text(value, style: t.standard.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.controller, required this.finding});

  final ModelController controller;
  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final c = controller;
    final f = finding;
    final ref = c.index.node(f.element) != null
        ? ModelElementRef.node(f.element)
        : (c.index.edge(f.element) != null ? ModelElementRef.edge(f.element) : null);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: t.spacing.xxs + 1),
            child: ModelChrome.of(context).statusDot(color: severityColour(t, f.severity)),
          ),
          SizedBox(width: t.spacing.xs),
          Expanded(
            child: Text(
              f.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.small.copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
    if (ref == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (ref.isNode) c.reveal(ref.id);
          c.select(ref);
        },
        child: row,
      ),
    );
  }
}
