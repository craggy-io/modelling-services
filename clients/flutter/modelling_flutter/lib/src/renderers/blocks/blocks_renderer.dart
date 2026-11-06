// blocks_renderer.dart: the default renderer: nested area blocks with
// relationship dots (a port of labs' CraggyModelView, theme.md §5.17).

import 'package:flutter/material.dart';

import '../../controller/model_controller.dart';
import '../../theme/model_theme.dart';
import '../model_renderer.dart';
import 'blocks_board.dart';
import 'blocks_layout.dart';

/// Nested area blocks: search, collapse, drill-in, paging, relationship
/// dots with hover/pinned connectors, diff ghosts, keyboard navigation and
/// (unless read-only) editing gestures.
///
/// [grid] (off by default) is the grid layout: the board is the model's
/// top-level areas on a dotted canvas, and inside every area children sit
/// on a 10-column grid with fixed widths and heights from the active view's
/// `sizes`, resized by dragging their edges and reordered by dragging.
class BlocksRenderer extends ModelRenderer {
  const BlocksRenderer({this.grid = false});

  final bool grid;

  @override
  String get id => 'blocks';

  @override
  String get label => 'Blocks';

  @override
  IconData get icon => Icons.dashboard_outlined;

  @override
  Widget build(BuildContext context, ModelController controller) => BlocksBoard(controller: controller, grid: grid);

  @override
  int shownAreas(ModelController controller, ModelTheme theme) => layoutBlocks(controller, theme).shown;
}
