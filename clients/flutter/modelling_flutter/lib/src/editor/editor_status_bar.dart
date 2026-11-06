// editor_status_bar.dart: the editor's bottom bar: what is shown (areas and
// relationships, changes from the base), lint counts, the latest notice,
// the overlay picker and legend, the board zoom and the saved state.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../inspector/model_overview.dart';
import '../theme/model_theme.dart';

/// The zoom steps the status bar moves between.
const zoomSteps = [0.5, 0.67, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0];

/// The next zoom step from [zoom] towards [up] (bigger) or smaller.
double nextZoom(double zoom, {required bool up}) => up
    ? zoomSteps.firstWhere((z) => z > zoom + 0.001, orElse: () => zoomSteps.last)
    : zoomSteps.lastWhere((z) => z < zoom - 0.001, orElse: () => zoomSteps.first);

class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.controller,
    required this.shown,
    required this.zoomable,
    required this.onLint,
  });

  final ModelController controller;

  /// Areas the active renderer draws.
  final int shown;

  /// Whether the active renderer follows the board zoom.
  final bool zoomable;

  /// Opens the lint summary (the model overview).
  final VoidCallback onLint;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final m = c.model;
    final (errors, warnings, info) = lintCounts(c.lint);
    final overlay = c.overlay;
    final areas = m.nodes.length, edges = m.edges.length;
    final counts = [
      if (shown < areas) '$shown of $areas areas' else '$areas ${areas == 1 ? 'area' : 'areas'}',
      '$edges ${edges == 1 ? 'relationship' : 'relationships'}',
      if (!c.diff.isEmpty) '${c.diff.count} changed',
    ].join('  ·  ');
    Widget lint(IconData icon, int n, Color colour, String what) => chrome.tooltip(
      message: '$n $what',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.spacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: n == 0 ? t.muted : colour),
            const SizedBox(width: 3),
            Text('$n', style: t.small.copyWith(color: n == 0 ? t.muted : t.text)),
          ],
        ),
      ),
    );
    final divider = Container(
      width: 1,
      height: 14,
      margin: EdgeInsets.symmetric(horizontal: t.spacing.sm),
      color: t.divider,
    );
    return Container(
      key: const ValueKey('editor-status'),
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border(
          top: BorderSide(color: t.divider, width: t.borderWidth),
        ),
      ),
      child: Row(
        children: [
          // The left group shrinks first: counts ellipsize, the notice takes the rest.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    counts,
                    key: const ValueKey('editor-counts'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small,
                  ),
                ),
                divider,
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('editor-lint'),
                    onTap: onLint,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        lint(Icons.error_outline_rounded, errors, t.lintError, 'errors'),
                        lint(Icons.warning_amber_rounded, warnings, t.lintWarning, 'warnings'),
                        lint(Icons.info_outline_rounded, info, t.lintInfo, 'notes'),
                      ],
                    ),
                  ),
                ),
                divider,
                Expanded(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: c.notice,
                    builder: (context, notice, _) => notice == null
                        ? const SizedBox.shrink()
                        : Semantics(
                            liveRegion: true,
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 14, color: t.lintWarning),
                                SizedBox(width: t.spacing.xxs),
                                Flexible(
                                  child: Text(
                                    notice,
                                    key: const ValueKey('model-notice'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.small.copyWith(color: t.text),
                                  ),
                                ),
                                chrome.iconButton(
                                  icon: Icons.close_rounded,
                                  tooltip: 'Dismiss',
                                  onPressed: () => c.notice.value = null,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (!c.diff.isEmpty)
            chrome.filterChip(
              label: 'Changed only',
              selected: c.changedOnly,
              tooltip: c.changedOnly ? 'Show the whole model' : 'Hide what still matches the base',
              onPressed: () => c.changedOnly = !c.changedOnly,
            ),
          if (overlay != null)
            for (final e in overlay.legend.entries) ...[
              SizedBox(width: t.spacing.xs),
              chrome.statusDot(color: e.value),
              SizedBox(width: t.spacing.xxs),
              Text(e.key, style: t.small),
            ],
          if (c.overlays.isNotEmpty)
            chrome.menuButton(
              key: const ValueKey('overlay-picker'),
              icon: Icons.layers_outlined,
              tooltip: overlay == null ? 'Overlay' : 'Overlay: ${overlay.label}',
              items: [
                ModelMenuItem(label: 'No overlay', onSelected: () => c.activeOverlay = null),
                for (final o in c.overlays) ModelMenuItem(label: o.label, onSelected: () => c.activeOverlay = o.id),
              ],
            ),
          if (zoomable) ...[
            divider,
            ValueListenableBuilder<double>(
              valueListenable: c.zoom,
              builder: (context, zoom, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  chrome.iconButton(
                    key: const ValueKey('zoom-out'),
                    icon: Icons.remove_rounded,
                    tooltip: 'Zoom out',
                    onPressed: zoom > zoomSteps.first ? () => c.zoom.value = nextZoom(zoom, up: false) : null,
                  ),
                  chrome.tooltip(
                    message: 'Reset zoom',
                    child: GestureDetector(
                      onTap: () => c.zoom.value = 1,
                      child: SizedBox(
                        width: 44,
                        child: Text(
                          '${(zoom * 100).round()}%',
                          key: const ValueKey('zoom-level'),
                          textAlign: TextAlign.center,
                          style: t.small.copyWith(color: t.text),
                        ),
                      ),
                    ),
                  ),
                  chrome.iconButton(
                    key: const ValueKey('zoom-in'),
                    icon: Icons.add_rounded,
                    tooltip: 'Zoom in',
                    onPressed: zoom < zoomSteps.last ? () => c.zoom.value = nextZoom(zoom, up: true) : null,
                  ),
                ],
              ),
            ),
          ],
          if (!c.readOnly) ...[
            divider,
            Icon(
              c.dirty ? Icons.circle : Icons.cloud_done_outlined,
              size: c.dirty ? 8 : 14,
              color: c.dirty ? t.focus : t.muted,
            ),
            SizedBox(width: t.spacing.xxs + 2),
            Text(
              c.dirty ? 'Unsaved changes' : 'No unsaved changes',
              key: const ValueKey('editor-saved-state'),
              style: t.small.copyWith(color: c.dirty ? t.text : t.muted),
            ),
          ],
        ],
      ),
    );
  }
}
