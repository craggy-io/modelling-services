// markers.dart: the small marks every renderer puts beside an element:
// change dot, lint badge, overlay badge and link marker.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../theme/model_theme.dart';
import 'model_diff.dart';

/// The colour a theme gives a change kind.
Color changeColour(ModelTheme t, ChangeKind kind) => switch (kind) {
  ChangeKind.added => t.added,
  ChangeKind.changed => t.changed,
  ChangeKind.removed => t.removed,
};

/// The colour a theme gives a lint severity.
Color severityColour(ModelTheme t, Severity s) => switch (s) {
  Severity.error => t.lintError,
  Severity.warning => t.lintWarning,
  Severity.info => t.lintInfo,
};

/// The status dot after an element that differs from the base; its
/// tooltip says how.
class ChangeMarker extends StatelessWidget {
  const ChangeMarker(this.kind, {super.key});

  final ChangeKind kind;

  @override
  Widget build(BuildContext context) => Semantics(
    label: ModelDiff.describe(kind),
    child: ModelChrome.of(
      context,
    ).statusDot(color: changeColour(ModelTheme.of(context), kind), tooltip: ModelDiff.describe(kind)),
  );
}

/// A pill with a short text in [colour] (lint counts, overlay badges).
class ModelBadge extends StatelessWidget {
  const ModelBadge({super.key, required this.text, required this.colour, this.tooltip, this.icon});

  final String text;
  final Color colour;
  final String? tooltip;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.xs - 2, vertical: 1),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: colour), if (text.isNotEmpty) const SizedBox(width: 2)],
          if (text.isNotEmpty) Text(text, style: t.small.copyWith(color: colour, height: 1.2)),
        ],
      ),
    );
    final semantic = Semantics(
      label: tooltip ?? text,
      child: ExcludeSemantics(child: pill),
    );
    return tooltip == null ? semantic : ModelChrome.of(context).tooltip(message: tooltip!, child: semantic);
  }
}

/// The marks after an area's label: change, link, lint and overlay.
List<Widget> elementMarks(BuildContext context, ModelController c, String id, {required bool edge}) {
  final t = ModelTheme.of(context);
  final change = edge ? c.diff.edgeChange(id) : c.diff.nodeChange(id);
  final findings = c.lintFor(id).where((f) => f.severity != Severity.info).toList();
  final node = edge ? null : c.index.node(id);
  final mark = edge ? null : c.overlay?.marks[id];
  final out = <Widget>[
    if (change != null) ChangeMarker(change),
    if (node?.link != null)
      ModelBadge(
        key: ValueKey('link-$id'),
        text: '',
        icon: Icons.link,
        colour: t.muted,
        tooltip: 'Links to ${node!.link!.model}',
      ),
    if (findings.isNotEmpty)
      ModelBadge(
        key: ValueKey('lint-$id'),
        text: '${findings.length}',
        icon: Icons.error_outline,
        colour: severityColour(
          t,
          findings.any((f) => f.severity == Severity.error) ? Severity.error : Severity.warning,
        ),
        tooltip: findings.map((f) => f.message).join('\n'),
      ),
    if (mark != null)
      ModelBadge(
        key: ValueKey('overlay-$id'),
        text: mark.badge,
        colour: mark.color,
        tooltip: '${c.overlay!.label}: ${mark.badge}${mark.value == null ? '' : ' (${(mark.value! * 100).round()}%)'}',
      ),
  ];
  return [
    for (final w in out) ...[SizedBox(width: t.spacing.xxs), w],
  ];
}
