// editor_panels.dart: the editor's side panels. Docked, a panel sits beside
// the board with a hairline edge that drags to resize it; collapsed, it
// slides away. Narrow, it is a drawer over the board with a scrim. Panel
// widths are remembered for the session.

import 'package:flutter/material.dart';

import '../theme/model_theme.dart';

/// Which side a panel is on.
enum PanelSide { left, right }

/// Panel widths the user dragged to, kept for the session (by side).
final panelWidths = <PanelSide, double>{};

/// The narrowest and widest a panel may be dragged.
const minPanelWidth = 220.0, maxPanelWidth = 520.0;

/// A titled block inside a panel: an overline heading, an optional
/// trailing widget and its body.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, this.trailing, required this.child, this.expand = false});

  final String title;
  final Widget? trailing;
  final Widget child;

  /// Whether the body fills the remaining height (a list).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final head = Padding(
      padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.sm, t.spacing.xs, t.spacing.xs),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Expanded(child: Text(title.toUpperCase(), style: t.overline)),
            ?trailing,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        head,
        if (expand) Expanded(child: child) else child,
      ],
    );
  }
}

/// A docked side panel [width] wide (0 when collapsed) whose inner edge
/// drags to resize it.
class DockedPanel extends StatefulWidget {
  const DockedPanel({
    super.key,
    required this.side,
    required this.open,
    required this.width,
    required this.onResize,
    required this.child,
  });

  final PanelSide side;
  final bool open;
  final double width;
  final ValueChanged<double> onResize;
  final Widget child;

  @override
  State<DockedPanel> createState() => _DockedPanelState();
}

class _DockedPanelState extends State<DockedPanel> {
  var _hovered = false;
  var _dragging = false;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final left = widget.side == PanelSide.left;
    final edgeActive = _hovered || _dragging;
    final edge = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: ValueKey('panel-edge-${widget.side.name}'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) =>
            widget.onResize((widget.width + (left ? d.delta.dx : -d.delta.dx)).clamp(minPanelWidth, maxPanelWidth)),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: t.standardDuration(context),
              width: edgeActive ? 2 : 1,
              color: edgeActive ? t.focus : t.divider,
            ),
          ),
        ),
      ),
    );
    return AnimatedContainer(
      key: ValueKey('panel-${widget.side.name}'),
      duration: _dragging ? Duration.zero : t.standardDuration(context),
      curve: Curves.easeOutCubic,
      width: widget.open ? widget.width : 0,
      color: t.panel,
      child: ClipRect(
        child: OverflowBox(
          alignment: left ? Alignment.centerRight : Alignment.centerLeft,
          minWidth: widget.width,
          maxWidth: widget.width,
          child: Row(
            children: [
              if (!left) edge,
              Expanded(child: widget.child),
              if (left) edge,
            ],
          ),
        ),
      ),
    );
  }
}

/// A panel as a drawer over [child] (narrow layouts): slides in from its
/// side over a scrim; tapping the scrim calls [onClose].
class PanelDrawer extends StatelessWidget {
  const PanelDrawer({super.key, required this.side, required this.open, required this.onClose, required this.panel});

  final PanelSide side;
  final bool open;
  final VoidCallback onClose;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final duration = t.standardDuration(context);
    final left = side == PanelSide.left;
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = (bounds.maxWidth * 0.85).clamp(0.0, left ? t.panelWidth + 40 : t.inspectorWidth + 40);
        return Stack(
          children: [
            IgnorePointer(
              ignoring: !open,
              child: GestureDetector(
                key: ValueKey('drawer-scrim-${side.name}'),
                onTap: onClose,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: duration,
                  child: ColoredBox(color: t.shadow, child: const SizedBox.expand()),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              width: width,
              left: left ? (open ? 0 : -width - 24) : null,
              right: left ? null : (open ? 0 : -width - 24),
              child: Container(
                key: ValueKey('drawer-${side.name}'),
                decoration: BoxDecoration(
                  color: t.panel,
                  border: Border(
                    left: left ? BorderSide.none : BorderSide(color: t.divider),
                    right: left ? BorderSide(color: t.divider) : BorderSide.none,
                  ),
                  boxShadow: [BoxShadow(color: t.shadow, blurRadius: 24)],
                ),
                child: panel,
              ),
            ),
          ],
        );
      },
    );
  }
}
