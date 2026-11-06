// slop_draggable.dart: a Draggable that starts only once the pointer has
// moved a few pixels, so a whole card can be the drag source while a click
// on it (or on a button inside it) still lands as a tap.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A [Draggable] that starts after the pointer moves [slop] pixels (at
/// least the platform's own slop for the pointer kind).
class SlopDraggable<T extends Object> extends Draggable<T> {
  const SlopDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    this.slop = 4,
  });

  final double slop;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      _SlopDragRecognizer(slop, allowedButtonsFilter: allowedButtonsFilter)..onStart = onStart;
}

class _SlopDragRecognizer extends MultiDragGestureRecognizer {
  _SlopDragRecognizer(this.slop, {super.allowedButtonsFilter}) : super(debugOwner: null);

  final double slop;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _SlopPointerState(event.position, event.kind, gestureSettings, slop);

  @override
  String get debugDescription => 'slop multidrag';
}

class _SlopPointerState extends MultiDragPointerState {
  _SlopPointerState(super.initialPosition, super.kind, super.gestureSettings, this.slop);

  final double slop;

  @override
  void checkForResolutionAfterMove() {
    final threshold = computeHitSlop(kind, gestureSettings);
    if (pendingDelta!.distance > (slop > threshold ? slop : threshold)) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) => starter(initialPosition);
}
