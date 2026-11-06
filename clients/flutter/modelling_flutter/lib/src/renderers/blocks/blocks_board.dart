// blocks_board.dart: the blocks renderer's board: drill-in trail, the
// nested areas with the connector painter over them, paging, the
// relationships list, keyboard navigation and the editing gestures.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../inspector/inspector.dart';
import '../../shared/inline_rename.dart';
import '../../shared/new_relationship.dart';
import '../../theme/model_theme.dart';
import '../../workspace/model_hooks.dart';
import 'area_box.dart';
import 'blocks_layout.dart';
import 'connector_painter.dart';
import 'grid_canvas.dart';
import 'relationships_list.dart';
import '../../shared/no_areas.dart';

/// The nested-blocks board for [controller]; [grid] lays areas out on the
/// 10-column grid with resize handles (see [BlocksRenderer.grid]).
class BlocksBoard extends StatefulWidget {
  const BlocksBoard({super.key, required this.controller, this.grid = false});

  final ModelController controller;
  final bool grid;

  @override
  State<BlocksBoard> createState() => _BlocksBoardState();
}

class _BlocksBoardState extends State<BlocksBoard> with InlineRenameState<BlocksBoard> implements BlocksBoardHandle {
  final _diagram = GlobalKey();
  final _anchors = <String, GlobalKey>{};
  final _focus = FocusNode(debugLabel: 'blocks board');
  List<String> _order = const [];

  @override
  ModelController get controller => widget.controller;

  @override
  GlobalKey anchor(String id) => _anchors[id] ??= GlobalKey(debugLabel: 'area $id');

  @override
  FocusNode get renameReturnFocus => _focus;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The drawn label of [id], or of its nearest drawn containing area when
  /// [id] is collapsed, past the page or outside the open region.
  Rect? _drawn(String id, RenderBox diagram) {
    String? at = id;
    while (at != null && at.isNotEmpty) {
      final box = _anchors[at]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        return box.localToGlobal(Offset.zero, ancestor: diagram) & box.size;
      }
      at = controller.parentOf(at);
    }
    return null;
  }

  @override
  void press(String id) {
    controller.focus(id);
    _focus.requestFocus();
  }

  @override
  void inspect(String id) {
    press(id);
    inspectElement(context, controller, ModelElementRef.node(id));
  }

  @override
  void inspectEdge(String id) => inspectElement(context, controller, ModelElementRef.edge(id));

  @override
  Future<void> delete(String id) async {
    final next = _neighbour(id);
    if (await confirmDeleteNode(context, controller, id) && next != null) controller.focus(next);
  }

  String? _neighbour(String id) {
    final at = _order.indexOf(id);
    if (at < 0) return null;
    return at + 1 < _order.length ? _order[at + 1] : (at > 0 ? _order[at - 1] : null);
  }

  @override
  void connect(String from, String to) => promptRelationship(context, controller, from, to);

  void _moveFocus(int step) {
    if (_order.isEmpty) return;
    final at = _order.indexOf(controller.focused ?? '');
    final next = at < 0 ? (step > 0 ? 0 : _order.length - 1) : (at + step).clamp(0, _order.length - 1);
    controller.focus(_order[next]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchors[_order[next]]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final c = controller;
    final id = c.focused;
    final editable = id != null && !c.readOnly && c.index.node(id) != null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
    } else if (key == LogicalKeyboardKey.arrowRight && id != null) {
      if (c.index.children(id).isNotEmpty) c.drillIn(id);
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.backspace) {
      c.back();
    } else if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && id != null) {
      inspect(id);
    } else if (key == LogicalKeyboardKey.space && id != null) {
      final layout = layoutBlocks(c, ModelTheme.of(context));
      final area = _find(layout.root, id);
      if (area == null || area.childCount == 0) return KeyEventResult.ignored;
      c.toggleFolded(id, folded: area.folded);
    } else if (key == LogicalKeyboardKey.f2 && editable) {
      startRename(id);
    } else if ((key == LogicalKeyboardKey.delete) && editable) {
      delete(id);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  BlockArea? _find(BlockArea a, String id) {
    if (a.id == id) return a;
    for (final k in a.children) {
      final f = _find(k, id);
      if (f != null) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    final layout = layoutBlocks(c, t);
    _order = layout.order;
    final limit = c.limit ?? t.pageSize;
    final listed = listedEdges(c);
    final empty = layout.included == 0 && layout.root.children.isEmpty;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.trail.isNotEmpty) ...[
            Row(
              children: [
                chrome.button(
                  label: 'Back to parent area',
                  icon: Icons.arrow_back,
                  variant: ModelButtonVariant.ghost,
                  size: ModelButtonSize.sm,
                  onPressed: c.back,
                ),
                SizedBox(width: t.spacing.xs),
                Expanded(
                  child: Text(
                    c.trail.map(c.labelOf).join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
          ],
          Expanded(
            child: widget.grid
                ? GridCanvas(board: this, layout: layout, diagram: _diagram, drawn: _drawn, onInspectEdge: inspectEdge)
                : empty
                ? NoAreas(controller: c)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RepaintBoundary(
                          key: ModelHooks.of(context).captureKey,
                          child: CustomPaint(
                            key: _diagram,
                            foregroundPainter: ConnectorPainter(
                              controller: c,
                              diagram: _diagram,
                              drawn: _drawn,
                              theme: t,
                            ),
                            child: AreaBox(area: layout.root, board: this),
                          ),
                        ),
                        if (layout.more(limit)) ...[
                          SizedBox(height: t.spacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: chrome.button(
                              label: 'Show more areas',
                              variant: ModelButtonVariant.ghost,
                              onPressed: () => c.showMore(t.pageSize),
                            ),
                          ),
                        ],
                        if (listed.isNotEmpty) ...[
                          SizedBox(height: t.spacing.sm),
                          RelationshipsList(controller: c, onInspect: inspectEdge),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
