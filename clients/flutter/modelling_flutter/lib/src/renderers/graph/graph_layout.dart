// graph_layout.dart: where the graph renderer draws each area. Areas with
// shown contents are compound boxes around them. Each box's contents (and
// the top level) are laid out in layers, left to right, along the directed
// relationships between them (lifted to that level), cycles broken in
// document order; within a layer areas keep document order, then one
// barycentre pass. Deterministic: the same model always draws the same.
// A saved position (the view's `positions`) places an area's box and its
// contents move with it; containing boxes grow to keep enclosing them.

import 'package:flutter/painting.dart';
import 'package:modelling/modelling.dart' hide View;

import '../../controller/model_controller.dart';
import '../../shared/shown_elements.dart';
import '../../theme/model_theme.dart';

/// Sizes the graph renderer lays out with.
class GraphMetrics {
  const GraphMetrics._();

  static const leafHeight = 40.0;
  static const header = 32.0;
  static const minWidth = 120.0;
  static const maxWidth = 260.0;
  static const layerGap = 72.0;
  static const margin = 32.0;

  /// Room after the label for the marks (change, lint, overlay).
  static const marksRoom = 64.0;
}

/// One drawn area.
class GraphBox {
  const GraphBox(this.node, this.rect, this.place, {required this.container});

  final ShownNode node;
  final Rect rect;

  /// Its saved or laid-out top-left (the rect may have grown past it to
  /// enclose moved contents); what dragging saves.
  final Offset place;

  /// Whether it encloses shown contents (drawn as a compound box).
  final bool container;

  String get id => node.id;

  /// Where its label goes: the whole box, or a container's header.
  Rect get labelRect => container ? Rect.fromLTWH(rect.left, rect.top, rect.width, GraphMetrics.header) : rect;
}

/// The graph's boxes (parents before contents), the relationships drawn
/// between them, and the drawing's bounds.
class GraphLayout {
  const GraphLayout(this.boxes, this.edges, this.bounds);

  final Map<String, GraphBox> boxes;
  final List<String> edges;
  final Rect bounds;
}

/// Lays out [c]'s shown areas. [positions] overrides the saved ones (the
/// renderer passes a dragged area's live position).
GraphLayout layoutGraph(ModelController c, ModelTheme t, {Map<String, Position>? positions}) {
  final shown = shownNodes(c);
  final ids = {for (final n in shown) n.id};
  final edges = shownEdges(c, ids);
  final saved = positions ?? c.positions;
  final pad = t.padding;

  final parent = {for (final n in shown) n.id: n.parent};
  final kids = <String?, List<String>>{};
  for (final n in shown) {
    (kids[n.parent] ??= []).add(n.id);
  }

  // Directed relationships, for layering.
  final directed = <(String, String)>[];
  for (final id in edges) {
    final e = c.edgeOrGhost(id)!;
    if (!e.undirected) directed.add((e.from, e.to));
  }

  final size = <String, Size>{};
  final local = <String, Offset>{};
  final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);

  double labelWidth(String id) {
    painter.text = TextSpan(
      text: c.labelOf(id),
      style: t.standard.copyWith(fontWeight: FontWeight.w500),
    );
    painter.layout();
    return painter.width + 2 * t.spacing.sm + GraphMetrics.marksRoom;
  }

  late final Size Function(List<String> items) block;

  Size measure(String id) {
    final inner = kids[id];
    final w = labelWidth(id).clamp(GraphMetrics.minWidth, GraphMetrics.maxWidth).toDouble();
    if (inner == null) return size[id] = Size(w, GraphMetrics.leafHeight);
    final b = block(inner);
    return size[id] = Size(
      (b.width + 2 * pad).clamp(w, double.infinity).toDouble(),
      b.height + 2 * pad + GraphMetrics.header,
    );
  }

  block = (items) {
    for (final id in items) {
      measure(id);
    }
    final layers = _layers(items, directed, parent);
    var x = 0.0, height = 0.0;
    final columns = <(double, List<String>)>[];
    for (final layer in layers) {
      final w = layer.map((id) => size[id]!.width).reduce((a, b) => a > b ? a : b);
      final h = layer.map((id) => size[id]!.height).reduce((a, b) => a + b) + t.gap * (layer.length - 1);
      columns.add((x, layer));
      if (h > height) height = h;
      x += w + GraphMetrics.layerGap;
    }
    for (final (cx, layer) in columns) {
      final h = layer.map((id) => size[id]!.height).reduce((a, b) => a + b) + t.gap * (layer.length - 1);
      var y = (height - h) / 2;
      for (final id in layer) {
        local[id] = Offset(cx, y);
        y += size[id]!.height + t.gap;
      }
    }
    return Size(x - GraphMetrics.layerGap, height);
  };

  block(kids[null] ?? const []);

  // Absolute places, top-down; a saved position moves the box and its
  // contents.
  final at = <String, Offset>{};
  for (final n in shown) {
    final p = saved[n.id];
    final inside = n.parent == null
        ? const Offset(GraphMetrics.margin, GraphMetrics.margin)
        : at[n.parent]! + Offset(pad, pad + GraphMetrics.header);
    at[n.id] = p != null ? Offset(p.$1, p.$2) : inside + local[n.id]!;
  }

  // Rects, bottom-up: a container grows to enclose moved contents.
  final rects = <String, Rect>{};
  for (final n in shown.reversed) {
    var r = at[n.id]! & size[n.id]!;
    final inner = kids[n.id];
    if (inner != null) {
      final b = inner.map((k) => rects[k]!).reduce((a, b) => a.expandToInclude(b));
      r = r.expandToInclude(
        Rect.fromLTRB(b.left - pad, b.top - pad - GraphMetrics.header, b.right + pad, b.bottom + pad),
      );
    }
    rects[n.id] = r;
  }

  final boxes = {for (final n in shown) n.id: GraphBox(n, rects[n.id]!, at[n.id]!, container: kids.containsKey(n.id))};
  final bounds = rects.isEmpty
      ? Rect.zero
      : rects.values.reduce((a, b) => a.expandToInclude(b)).inflate(GraphMetrics.margin);
  painter.dispose();
  return GraphLayout(boxes, edges, bounds);
}

/// Splits sibling [items] into layers along [directed] relationships
/// lifted to them (via [parent]). Back edges, found depth-first in
/// document order, are ignored, so cycles still lay out.
List<List<String>> _layers(List<String> items, List<(String, String)> directed, Map<String, String?> parent) {
  final mine = items.toSet();
  String? lift(String id) {
    for (String? p = id; p != null; p = parent[p]) {
      if (mine.contains(p)) return p;
    }
    return null;
  }

  final out = {for (final id in items) id: <String>[]};
  for (final (from, to) in directed) {
    final a = lift(from), b = lift(to);
    if (a != null && b != null && a != b && !out[a]!.contains(b)) out[a]!.add(b);
  }
  final order = {for (var i = 0; i < items.length; i++) items[i]: i};
  for (final l in out.values) {
    l.sort((a, b) => order[a]!.compareTo(order[b]!));
  }

  // Depth-first: drop back edges, collect a topological order.
  final state = <String, int>{}; // 1 on the stack, 2 done
  final post = <String>[];
  final forward = {for (final id in items) id: <String>[]};
  void visit(String id) {
    state[id] = 1;
    for (final next in out[id]!) {
      if (state[next] == 1) continue;
      forward[id]!.add(next);
      if (state[next] == null) visit(next);
    }
    state[id] = 2;
    post.add(id);
  }

  for (final id in items) {
    if (state[id] == null) visit(id);
  }

  final rank = {for (final id in items) id: 0};
  for (final id in post.reversed) {
    for (final next in forward[id]!) {
      if (rank[next]! < rank[id]! + 1) rank[next] = rank[id]! + 1;
    }
  }
  final count = rank.values.fold(0, (a, b) => a > b ? a : b) + 1;
  final layers = [for (var i = 0; i < count; i++) <String>[]];
  for (final id in items) {
    layers[rank[id]!].add(id);
  }

  // One barycentre pass: order each layer by its predecessors' places.
  final place = <String, double>{};
  for (var i = 0; i < layers.length; i++) {
    if (i > 0) {
      double key(String id) {
        final from = [
          for (final e in forward.entries)
            if (e.value.contains(id) && place.containsKey(e.key)) place[e.key]!,
        ];
        return from.isEmpty ? double.infinity : from.reduce((a, b) => a + b) / from.length;
      }

      final keys = {for (final id in layers[i]) id: key(id)};
      layers[i].sort((a, b) {
        final k = keys[a]!.compareTo(keys[b]!);
        return k != 0 ? k : order[a]!.compareTo(order[b]!);
      });
    }
    for (var j = 0; j < layers[i].length; j++) {
      place[layers[i][j]] = j.toDouble();
    }
  }
  return layers.where((l) => l.isNotEmpty).toList();
}
