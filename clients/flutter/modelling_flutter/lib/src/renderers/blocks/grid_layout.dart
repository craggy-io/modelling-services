// grid_layout.dart: the grid blocks layout. Inside every area, children sit
// on a 10-column grid: an explicit width is a view size's `w` (tenths), an
// auto one shares the row; rows wrap when their spans pass 10, and each row
// is as tall as its tallest child. Pure packing plus the render object
// that places the children.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:modelling/modelling.dart' show NodeSize;

/// Columns in every area's grid; a size's `w` counts these.
const gridColumns = NodeSize.maxW;

/// Where one child sits: its [row], first [column] and [span] of columns.
@immutable
class GridSlot {
  const GridSlot(this.row, this.column, this.span);

  final int row;
  final int column;
  final int span;

  @override
  bool operator ==(Object other) =>
      other is GridSlot && other.row == row && other.column == column && other.span == span;

  @override
  int get hashCode => Object.hash(row, column, span);

  @override
  String toString() => 'GridSlot($row, $column, $span)';
}

/// An auto child takes what is left of a row rather than wrap, when at
/// least this many columns are left.
const minAutoSpan = 3;

/// The span an auto-width child gets among [children] siblings when at
/// most [autoColumns] share a row.
int autoSpan(int children, int autoColumns) => gridColumns ~/ math.max(1, math.min(children, autoColumns));

/// Packs children left to right: [widths] holds each child's explicit span
/// (1–10) or null for auto. An auto child shares its row with up to
/// [autoColumns] siblings; one that is [wide] (an area with children) takes
/// at least half a row, and takes the rest of a row when at least
/// [minAutoSpan] columns are left. A row closes when the next span would pass 10; its
/// spare columns go to its auto children, left to right, so rows end flush
/// wherever an auto child can stretch.
List<GridSlot> packGrid(List<int?> widths, {int autoColumns = 3, List<bool> wide = const []}) {
  final auto = autoSpan(widths.length, autoColumns);
  final half = autoSpan(2, autoColumns);
  final spans = [
    for (var i = 0; i < widths.length; i++)
      (widths[i] ?? (i < wide.length && wide[i] ? math.max(auto, half) : auto)).clamp(1, gridColumns),
  ];
  final rowOf = List.filled(widths.length, 0);
  var row = 0, used = 0;
  final rows = <List<int>>[[]];
  for (var i = 0; i < spans.length; i++) {
    final left = gridColumns - used;
    if (widths[i] == null && spans[i] > left && left >= minAutoSpan) spans[i] = left;
    if (used + spans[i] > gridColumns && rows.last.isNotEmpty) {
      rows.add([]);
      row++;
      used = 0;
    }
    rows.last.add(i);
    rowOf[i] = row;
    used += spans[i];
  }
  for (final members in rows) {
    final autos = [
      for (final i in members)
        if (widths[i] == null) i,
    ];
    var spare = gridColumns - members.fold(0, (sum, i) => sum + spans[i]);
    for (var k = 0; spare > 0 && autos.isNotEmpty; k = (k + 1) % autos.length, spare--) {
      spans[autos[k]]++;
    }
  }
  final slots = <GridSlot>[];
  var column = 0;
  for (var i = 0; i < spans.length; i++) {
    if (i > 0 && rowOf[i] != rowOf[i - 1]) column = 0;
    slots.add(GridSlot(rowOf[i], column, spans[i]));
    column += spans[i];
  }
  return slots;
}

/// The pixel width of [span] columns in a grid [width] wide with [gap]
/// gutters.
double spanWidth(int span, double width, double gap) {
  final column = (width - (gridColumns - 1) * gap) / gridColumns;
  return span * column + (span - 1) * gap;
}

/// The span closest to [pixels] in a grid [width] wide with [gap] gutters.
int spanFor(double pixels, double width, double gap) {
  final column = (width - (gridColumns - 1) * gap) / gridColumns;
  return ((pixels + gap) / (column + gap)).round().clamp(1, gridColumns);
}

/// Places its children in [slots]; a child with a [heights] entry is that
/// tall, the rest stretch to their row's tallest child. When the slots
/// change (a drop preview opens a gap, a drop or resize lands) children
/// glide from where they were drawn to their new places over [duration];
/// hit tests use the new places at once.
class GridFlow extends MultiChildRenderObjectWidget {
  const GridFlow({
    super.key,
    required this.slots,
    required this.heights,
    required this.gap,
    required this.vsync,
    this.duration = Duration.zero,
    super.children,
  });

  final List<GridSlot> slots;
  final List<double?> heights;
  final double gap;
  final TickerProvider vsync;
  final Duration duration;

  @override
  RenderGridFlow createRenderObject(BuildContext context) => RenderGridFlow(slots, heights, gap, vsync, duration);

  @override
  void updateRenderObject(BuildContext context, RenderGridFlow renderObject) => renderObject
    ..slots = slots
    ..heights = heights
    ..gap = gap
    ..vsync = vsync
    ..duration = duration;
}

class _GridData extends ContainerBoxParentData<RenderBox> {
  /// Where the child is laid out once the glide ends.
  Rect? target;

  /// Where it was drawn when the current glide began.
  Offset? from;
}

class RenderGridFlow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _GridData>, RenderBoxContainerDefaultsMixin<RenderBox, _GridData> {
  RenderGridFlow(this._slots, this._heights, this._gap, TickerProvider vsync, Duration duration)
    : _motion = AnimationController(vsync: vsync, duration: duration) {
    // Each frame of a glide moves the children towards their targets.
    // They keep their final size: scaling would stretch their content and
    // an in-between size can be too small for it.
    _motion.addListener(() {
      if (!_starting) markNeedsLayout();
    });
  }

  final AnimationController _motion;

  /// True while [performLayout] restarts the glide, which must not re-dirty it.
  var _starting = false;
  var _moved = false;

  List<GridSlot> _slots;
  set slots(List<GridSlot> v) {
    if (listEquals(v, _slots)) return;
    _slots = v;
    _moved = true;
    markNeedsLayout();
  }

  List<double?> _heights;
  set heights(List<double?> v) {
    if (listEquals(v, _heights)) return;
    _heights = v;
    _moved = true;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  set vsync(TickerProvider v) => _motion.resync(v);

  set duration(Duration v) => _motion.duration = v;

  /// How far the current glide has come (1 when still).
  double get _progress => _motion.isAnimating ? Curves.easeOutCubic.transform(_motion.value) : 1;

  static Offset _shown(_GridData d, double progress) =>
      d.from == null || progress >= 1 ? d.target!.topLeft : Offset.lerp(d.from, d.target!.topLeft, progress)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridData) child.parentData = _GridData();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final kids = getChildrenAsList();
    final glide = _moved && (_motion.duration ?? Duration.zero) > Duration.zero;
    if (glide) {
      // A child already drawn glides from where it is now; a new one
      // appears in place.
      final now = _progress;
      for (final kid in kids) {
        final data = kid.parentData! as _GridData;
        data.from = data.target == null ? null : _shown(data, now);
      }
      _starting = true;
      _motion.forward(from: 0);
      _starting = false;
    }
    _moved = false;
    var top = 0.0;
    var i = 0;
    while (i < kids.length) {
      final row = i < _slots.length ? _slots[i].row : -1;
      final start = i;
      var tallest = 0.0;
      for (; i < kids.length && (i < _slots.length ? _slots[i].row : -1) == row; i++) {
        final slot = i < _slots.length ? _slots[i] : const GridSlot(0, 0, gridColumns);
        final w = spanWidth(slot.span, width, _gap);
        final fixed = i < _heights.length ? _heights[i] : null;
        kids[i].layout(
          fixed == null ? BoxConstraints.tightFor(width: w) : BoxConstraints.tightFor(width: w, height: fixed),
          parentUsesSize: true,
        );
        tallest = math.max(tallest, kids[i].size.height);
      }
      for (var k = start; k < i; k++) {
        final slot = k < _slots.length ? _slots[k] : const GridSlot(0, 0, gridColumns);
        final fixed = k < _heights.length ? _heights[k] : null;
        if (fixed == null && kids[k].size.height != tallest) {
          kids[k].layout(BoxConstraints.tightFor(width: kids[k].size.width, height: tallest), parentUsesSize: true);
        }
        final x = slot.column == 0 ? 0.0 : spanWidth(slot.column, width, _gap) + _gap;
        (kids[k].parentData! as _GridData).target = Offset(x, top) & kids[k].size;
      }
      top += tallest + _gap;
    }
    final progress = _progress;
    for (final kid in kids) {
      final data = kid.parentData! as _GridData;
      data.offset = _shown(data, progress);
    }
    size = constraints.constrain(Size(width, kids.isEmpty ? 0 : top - _gap));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
