// outline_renderer.dart: an indented tree with relationships listed under
// each area (design §7.2). Lazy, narrow-screen friendly, fully keyboard
// editable, and the accessible fallback for the other renderers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../controller/model_types.dart';
import '../../inspector/inspector.dart';
import '../../shared/board_insets.dart';
import '../../shared/inline_rename.dart';
import '../../theme/model_theme.dart';
import '../model_renderer.dart';
import 'outline_row_view.dart';
import 'outline_rows.dart';
import '../../shared/no_areas.dart';

/// The outline renderer.
class OutlineRenderer extends ModelRenderer {
  const OutlineRenderer();

  @override
  String get id => 'outline';

  @override
  String get label => 'Outline';

  @override
  IconData get icon => Icons.format_list_bulleted;

  @override
  Widget build(BuildContext context, ModelController controller) => OutlineView(controller: controller);

  @override
  int shownAreas(ModelController controller, ModelTheme theme) =>
      outlineRows(controller, theme.openDepth).where((r) => r.isArea && !r.ghost).length;
}

/// Row height; fixed so the list is lazy and keyboard focus can scroll to
/// any row without building it.
const outlineRowHeight = 36.0;

/// The outline for [controller].
///
/// Keys: Up/Down move; Right expands or enters, Left collapses or goes to
/// the parent; Space folds; Ctrl+I inspects (Enter too when read-only).
/// Editing: Enter adds a sibling, Tab / Shift+Tab move into the previous
/// sibling / out of the parent, F2 renames, Delete deletes, Alt+Up/Down
/// reorder.
class OutlineView extends StatefulWidget {
  const OutlineView({super.key, required this.controller});

  final ModelController controller;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView> with InlineRenameState<OutlineView> {
  final _focus = FocusNode(debugLabel: 'outline');
  final _scroll = ScrollController();
  List<OutlineRow> _rows = const [];

  /// The list's top padding (on a full-bleed board).
  double _listTop = 0;

  @override
  ModelController get controller => widget.controller;

  @override
  FocusNode get renameReturnFocus => _focus;

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _press(String id) {
    controller.focus(id);
    _focus.requestFocus();
  }

  void _inspect(ModelElementRef ref) {
    if (ref.isNode) _press(ref.id);
    inspectElement(context, controller, ref);
  }

  List<String> get _areas => [
    for (final r in _rows)
      if (r.isArea) r.id,
  ];

  void _go(String id) {
    controller.focus(id);
    final at = _rows.indexWhere((r) => r.isArea && r.id == id);
    if (at < 0 || !_scroll.hasClients) return;
    final top = _listTop + at * outlineRowHeight, bottom = top + outlineRowHeight;
    final p = _scroll.position;
    if (top < p.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > p.pixels + p.viewportDimension) {
      _scroll.jumpTo((bottom - p.viewportDimension).clamp(0, p.maxScrollExtent));
    }
  }

  void _step(int by) {
    final areas = _areas;
    if (areas.isEmpty) return;
    final at = areas.indexOf(controller.focused ?? '');
    _go(areas[at < 0 ? (by > 0 ? 0 : areas.length - 1) : (at + by).clamp(0, areas.length - 1)]);
  }

  Future<void> _delete(String id) async {
    final areas = _areas, at = areas.indexOf(id);
    final next = at + 1 < areas.length ? areas[at + 1] : (at > 0 ? areas[at - 1] : null);
    if (await confirmDeleteNode(context, controller, id) && next != null) controller.focus(next);
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final c = controller;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final id = c.focused;
    final row = id == null ? null : _rows.where((r) => r.isArea && r.id == id).firstOrNull;
    final live = row != null && !row.ghost;
    final edit = live && !c.readOnly;
    final enter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

    if (edit && keys.isAltPressed && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      c.reorder(id!, up: key == LogicalKeyboardKey.arrowUp);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _step(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowRight && row != null) {
      if (row.folded) {
        c.toggleFolded(id, folded: true);
      } else if (row.childCount > 0) {
        _step(1);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft && row != null) {
      if (row.childCount > 0 && !row.folded) {
        c.toggleFolded(id, folded: false);
      } else if (c.parentOf(id!) != '') {
        _go(c.parentOf(id));
      }
    } else if (key == LogicalKeyboardKey.space && row != null && row.childCount > 0) {
      c.toggleFolded(id, folded: row.folded);
    } else if (row != null && ((key == LogicalKeyboardKey.keyI && keys.isControlPressed) || (enter && !edit))) {
      _inspect(ModelElementRef.node(id!));
    } else if (edit && enter) {
      final added = c.addSibling(id!);
      if (added != null) startRename(added);
    } else if (edit && key == LogicalKeyboardKey.tab) {
      keys.isShiftPressed ? c.outdent(id!) : c.indent(id!);
    } else if (edit && key == LogicalKeyboardKey.f2) {
      startRename(id!);
    } else if (edit && key == LogicalKeyboardKey.delete) {
      _delete(id!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = controller;
    _rows = outlineRows(c, t.openDepth);
    final inset = BoardInsets.maybeOf(context);
    _listTop = inset == null ? 0 : inset.top / 2;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.trail.isNotEmpty)
            Padding(
              padding: inset == null ? EdgeInsets.zero : EdgeInsets.fromLTRB(inset.left, inset.top, inset.right, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: chrome.button(
                  label: 'Back to parent area',
                  icon: Icons.arrow_back,
                  variant: ModelButtonVariant.ghost,
                  size: ModelButtonSize.sm,
                  onPressed: c.back,
                ),
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? NoAreas(controller: c)
                : ListView.builder(
                    controller: _scroll,
                    padding: inset == null ? null : EdgeInsets.symmetric(vertical: _listTop),
                    itemExtent: outlineRowHeight,
                    itemCount: _rows.length,
                    itemBuilder: (context, i) => OutlineRowView(
                      row: _rows[i],
                      controller: c,
                      renaming: renaming == _rows[i].id && _rows[i].isArea,
                      renameText: renameText,
                      onCommitRename: commitRename,
                      onCancelRename: cancelRename,
                      onPress: _press,
                      onRename: startRename,
                      onInspect: _inspect,
                      gutter: inset?.left ?? 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
