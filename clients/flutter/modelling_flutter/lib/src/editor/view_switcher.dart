// view_switcher.dart: the editor's segmented control over its renderers:
// icon and label segments on a recessed track, the active one raised on a
// rounded rectangle concentric with the track. With [compact] it is a
// single menu button.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../renderers/model_renderer.dart';
import '../theme/model_theme.dart';

/// The gap between the switcher's track and its segments.
const trackInset = 2.0;

class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    super.key,
    required this.controller,
    required this.renderers,
    required this.active,
    this.labels = true,
    this.compact = false,
  });

  final ModelController controller;
  final List<ModelRenderer> renderers;
  final ModelRenderer active;

  /// Shows each segment's label (else icons with tooltips).
  final bool labels;

  /// One menu button instead of segments.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    if (renderers.length < 2) return const SizedBox.shrink();
    if (compact) {
      return chrome.menuButton(
        key: const ValueKey('view-menu'),
        icon: active.icon,
        tooltip: 'Show as',
        items: [
          for (final r in renderers)
            ModelMenuItem(label: r.label, icon: r.icon, onSelected: () => controller.renderer = r.id),
        ],
      );
    }
    return Container(
      height: 32,
      padding: const EdgeInsets.all(trackInset),
      decoration: BoxDecoration(
        color: t.canvas,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.divider, width: t.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Segments fill the track's height, so the raised one is a
        // rounded rectangle rather than a pill hugging its label.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in renderers)
            _Segment(renderer: r, selected: r.id == active.id, label: labels, controller: controller),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({required this.renderer, required this.selected, required this.label, required this.controller});

  final ModelRenderer renderer;
  final bool selected;
  final bool label;
  final ModelController controller;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final r = widget.renderer;
    final on = widget.selected;
    final colour = on ? t.text : (_hovered ? t.text : t.muted);
    final segment = AnimatedContainer(
      duration: t.standardDuration(context),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: widget.label ? t.spacing.sm : t.spacing.xs),
      decoration: BoxDecoration(
        color: on ? t.surface : Colors.transparent,
        // Concentric with the track: its radius less the inset and border.
        borderRadius: BorderRadius.circular(t.innerRadius(trackInset + t.borderWidth)),
        border: Border.all(color: on ? t.divider : Colors.transparent, width: t.borderWidth),
        boxShadow: on ? [BoxShadow(color: t.shadow, blurRadius: 4, offset: const Offset(0, 1))] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(r.icon, size: 16, color: on ? t.focus : colour),
          if (widget.label) ...[
            SizedBox(width: t.spacing.xxs + 2),
            Text(
              r.label,
              style: t.small.copyWith(color: colour, fontWeight: on ? FontWeight.w600 : FontWeight.w500),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: on,
      label: 'Show as ${r.label.toLowerCase()}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ModelChrome.of(context).tooltip(
          message: widget.label ? 'Show as ${r.label.toLowerCase()}' : r.label,
          child: GestureDetector(
            key: ValueKey('renderer-${r.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.controller.renderer = r.id,
            child: segment,
          ),
        ),
      ),
    );
  }
}
