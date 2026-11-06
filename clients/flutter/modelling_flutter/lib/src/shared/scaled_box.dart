// scaled_box.dart: draws its child scaled and takes the scaled size, so a
// zoomed board still scrolls over exactly what is drawn and hit tests land
// where the pointer is.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [child] out at [width] / [scale] and draws it [scale] times larger.
class ScaledBox extends SingleChildRenderObjectWidget {
  const ScaledBox({super.key, required this.scale, super.child});

  final double scale;

  @override
  RenderScaledBox createRenderObject(BuildContext context) => RenderScaledBox(scale);

  @override
  void updateRenderObject(BuildContext context, RenderScaledBox renderObject) => renderObject.scale = scale;
}

class RenderScaledBox extends RenderProxyBox {
  RenderScaledBox(this._scale);

  double _scale;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = constraints;
    final inner = BoxConstraints(
      minWidth: c.minWidth / _scale,
      maxWidth: c.maxWidth / _scale,
      minHeight: c.minHeight / _scale,
      maxHeight: c.maxHeight / _scale,
    );
    child!.layout(inner, parentUsesSize: true);
    size = c.constrain(child!.size * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushTransform(needsCompositing, offset, Matrix4.diagonal3Values(_scale, _scale, 1), super.paint);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
    transform: Matrix4.diagonal3Values(_scale, _scale, 1),
    position: position,
    hitTest: (result, position) => child!.hitTest(result, position: position),
  );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.scaleByDouble(_scale, _scale, 1, 1);
}
