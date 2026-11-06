// new_relationship.dart: the dialog that finishes drawing a relationship:
// pick its kind from the profile (kinds allowed between the two ends), or
// give it a label when there is no profile.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../theme/model_theme.dart';
import '../workspace/model_hooks.dart';

/// Asks for the new relationship's kind and label, then adds it. Returns
/// the new edge id, or null when cancelled or refused.
Future<String?> promptRelationship(BuildContext context, ModelController c, String from, String to) async {
  final kinds = c.edgeKindsFor(from, to);
  if (c.profile != null && c.profile!.edgeKinds.isNotEmpty && kinds.isEmpty) {
    c.notice.value = 'The profile allows no relationship from ${c.labelOf(from)} to ${c.labelOf(to)}.';
    return null;
  }
  final scopes = captureModelScopes(context);
  final chrome = ModelChrome.of(context);
  var kind = kinds.isEmpty ? '' : kinds.keys.first;
  final label = TextEditingController(text: kinds.isEmpty ? '' : kinds.values.first.label);
  String? created;
  String? error;

  void create(BuildContext dialog) {
    if (label.text.trim().isEmpty) return;
    created = c.addRelationship(from, to, label: label.text, kind: kind, undirected: kinds[kind]?.undirected ?? false);
    if (created != null) Navigator.of(dialog).pop();
  }

  await chrome.showInspector(
    context,
    title: 'New relationship',
    subtitle: '${c.labelOf(from)} → ${c.labelOf(to)}',
    actions: (dialog) => [
      chrome.button(
        label: 'Create',
        icon: Icons.add_link,
        variant: ModelButtonVariant.primary,
        onPressed: () => create(dialog),
      ),
    ],
    body: (dialog) => scopes(
      StatefulBuilder(
        builder: (context, setState) {
          final t = ModelTheme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kinds.isNotEmpty) ...[
                chrome.select<String>(
                  key: const ValueKey('relationship-kind'),
                  label: 'Kind',
                  value: kind,
                  options: [for (final e in kinds.entries) ModelOption(e.key, e.value.label)],
                  onChanged: (v) => setState(() {
                    if (label.text == (kinds[kind]?.label ?? '')) label.text = kinds[v]?.label ?? '';
                    kind = v;
                  }),
                ),
                SizedBox(height: t.spacing.sm),
              ],
              chrome.textField(
                key: const ValueKey('relationship-label'),
                controller: label,
                label: 'Label',
                hint: 'calls, reads, owns…',
                error: error,
                autofocus: true,
                onChanged: (v) => setState(() => error = v.trim().isEmpty ? 'Give the relationship a label' : null),
                onSubmitted: (_) => create(dialog),
              ),
            ],
          );
        },
      ),
    ),
  );
  return created;
}
