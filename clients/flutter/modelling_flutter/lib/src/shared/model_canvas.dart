// model_canvas.dart: the pan-and-zoom surface the graph and matrix
// renderers draw on (design §7.6): zoom in, out and to fit, and the part
// of the drawing in view, so renderers cull what they build and paint.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../theme/model_theme.dart';
import '../workspace/model_hooks.dart';
import 'board_insets.dart';

/// Builds the drawing for the part of it in view ([visible], in drawing
/// coordinates).
typedef CanvasBuilder = Widget Function(BuildContext context, Rect visible);

/// A pannable, zoomable drawing of [size] with a zoom toolbar. [origin] is
/// the drawing coordinate at its top-left; when it moves (the drawing grew
/// up or left), the view shifts with it so nothing jumps.
class ModelCanvas extends StatefulWidget {
  const ModelCanvas({
    super.key,
    required this.size,
    required this.builder,
    this.origin = Offset.zero,
    this.leading = const [],
    this.trailing = const [],
    this.minScale = 0.1,
    this.maxScale = 3,
  });

  final Size size;
  final Offset origin;
  final CanvasBuilder builder;

  /// Toolbar widgets before and after the zoom buttons.
  final List<Widget> leading;
  final List<Widget> trailing;
  final double minScale;
  final double maxScale;

  @override
  State<ModelCanvas> createState() => _ModelCanvasState();
}

class _ModelCanvasState extends State<ModelCanvas> {
  final _view = TransformationController();
  Size _viewport = Size.zero;
  var _fitted = false;

  /// The view's edges a fit keeps clear (insets and a floating toolbar).
  EdgeInsets _margin = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _view.addListener(_moved);
  }

  void _moved() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ModelCanvas old) {
    super.didUpdateWidget(old);
    final shift = widget.origin - old.origin;
    if (shift != Offset.zero) {
      final s = _view.value.getMaxScaleOnAxis();
      _view.value = Matrix4.identity()
        ..translateByDouble(shift.dx * s, shift.dy * s, 0, 1)
        ..multiply(_view.value);
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// Shows the whole drawing, no larger than actual size, centred in the
  /// part of the view clear of a floating toolbar.
  void fit() {
    final v = _viewport, d = widget.size;
    if (v.isEmpty || d.isEmpty) return;
    final area = _margin.deflateRect(Offset.zero & v);
    if (area.isEmpty) return;
    final s = [area.width / d.width, area.height / d.height, 1.0].reduce((a, b) => a < b ? a : b);
    final scale = s.clamp(widget.minScale, widget.maxScale).toDouble();
    final dx = area.left + ((area.width - d.width * scale) / 2).clamp(0, double.infinity).toDouble();
    final dy = area.top + ((area.height - d.height * scale) / 2).clamp(0, double.infinity).toDouble();
    _view.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _zoom(double by) {
    final s = _view.value.getMaxScaleOnAxis();
    final f = (s * by).clamp(widget.minScale, widget.maxScale) / s;
    final c = _viewport.center(Offset.zero);
    _view.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(_view.value);
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final inset = BoardInsets.maybeOf(context);
    final zoom = [
      ...widget.trailing,
      chrome.iconButton(icon: Icons.zoom_out, tooltip: 'Zoom out', onPressed: () => _zoom(1 / 1.25)),
      chrome.iconButton(icon: Icons.zoom_in, tooltip: 'Zoom in', onPressed: () => _zoom(1.25)),
      chrome.iconButton(icon: Icons.fit_screen, tooltip: 'Zoom to fit', onPressed: fit),
    ];
    // On a full-bleed board the drawing fills it and the toolbars float
    // over its corners; elsewhere they sit in a row above it.
    _margin = inset == null ? EdgeInsets.zero : inset.copyWith(top: inset.top + _toolbarHeight + t.spacing.xs);
    final view = LayoutBuilder(
      builder: (context, bounds) {
        _viewport = bounds.biggest;
        if (!_fitted) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) fit();
          });
        }
        final visible = MatrixUtils.inverseTransformRect(_view.value, Offset.zero & _viewport);
        return RepaintBoundary(
          key: ModelHooks.of(context).captureKey,
          child: InteractiveViewer(
            transformationController: _view,
            constrained: false,
            boundaryMargin: EdgeInsets.all(_viewport.shortestSide),
            minScale: widget.minScale,
            maxScale: widget.maxScale,
            child: SizedBox.fromSize(size: widget.size, child: widget.builder(context, visible)),
          ),
        );
      },
    );
    if (inset == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [...widget.leading, const Spacer(), ...zoom]),
          SizedBox(height: t.spacing.xxs),
          Expanded(child: view),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: view),
        if (widget.leading.isNotEmpty)
          Positioned(
            left: inset.left,
            top: inset.top,
            child: _FloatingBar(children: widget.leading),
          ),
        Positioned(
          right: inset.right,
          top: inset.top,
          child: _FloatingBar(key: const ValueKey('canvas-toolbar'), children: zoom),
        ),
      ],
    );
  }
}

/// The height of a floating canvas toolbar (a medium icon button and its
/// frame).
const _toolbarHeight = 34.0;

/// A toolbar floating over a canvas: the panel surface with a hairline
/// and a soft shadow.
class _FloatingBar extends StatelessWidget {
  const _FloatingBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Container(
      height: _toolbarHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.divider, width: t.borderWidth),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
