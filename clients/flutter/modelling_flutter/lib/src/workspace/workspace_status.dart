// workspace_status.dart: the status line ("Showing X of Y areas · N
// relationships · M changed from the base"), the overlay legend and the
// latest notice (a refused gesture, a failed save, an export).

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../theme/model_theme.dart';

/// The status words for [c] with [shown] areas drawn.
String statusLine(ModelController c, int shown) {
  final m = c.model;
  final n = m.edges.length;
  return [
    'Showing $shown of ${m.nodes.length} areas',
    '$n relationship${n == 1 ? '' : 's'}',
    if (!c.diff.isEmpty) '${c.diff.count} changed from the base',
    if (!c.readOnly && c.dirty) 'unsaved changes',
  ].join(' · ');
}

class WorkspaceStatus extends StatelessWidget {
  const WorkspaceStatus({super.key, required this.controller, required this.shown});

  final ModelController controller;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final overlay = controller.overlay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(statusLine(controller, shown), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
        if (overlay != null && overlay.legend.isNotEmpty) ...[
          SizedBox(height: t.spacing.xxs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.xxs,
            children: [
              Text(overlay.label, style: t.small.copyWith(color: t.text)),
              for (final e in overlay.legend.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    chrome.statusDot(color: e.value),
                    SizedBox(width: t.spacing.xxs),
                    Text(e.key, style: t.small),
                  ],
                ),
            ],
          ),
        ],
        ValueListenableBuilder<String?>(
          valueListenable: controller.notice,
          builder: (context, notice, _) => notice == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(top: t.spacing.xxs),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: t.lintWarning),
                        SizedBox(width: t.spacing.xxs),
                        Expanded(
                          child: Text(
                            notice,
                            key: const ValueKey('model-notice'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.small.copyWith(color: t.lintWarning),
                          ),
                        ),
                        chrome.iconButton(
                          icon: Icons.close,
                          tooltip: 'Dismiss',
                          onPressed: () => controller.notice.value = null,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
