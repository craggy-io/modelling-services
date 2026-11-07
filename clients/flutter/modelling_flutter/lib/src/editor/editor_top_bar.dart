// editor_top_bar.dart: the editor's one-row top bar. Panel toggles, the
// host's leading widget, the model title (renamed in place) with a dirty
// dot, the view switcher, search, undo/redo, export, the host's actions,
// Save and the host's trailing widget. Three slots: the left group at the start, the right group flush
// with the end, the switcher centred on the bar. It never wraps: as it
// narrows, the title ellipsizes, the switcher drops its labels, search
// folds into a button, and the rest moves into an overflow menu.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../renderers/model_renderer.dart';
import '../shared/inline_rename.dart';
import '../theme/model_theme.dart';
import '../workspace/model_export.dart';
import '../workspace/model_shortcuts.dart';
import 'view_switcher.dart';

/// A host action in the editor's top bar. The first, the host's lead, is a
/// labelled primary button at the widest sizes; the rest are icon buttons
/// with the label as tooltip. A narrow bar moves them all into its overflow
/// menu.
@immutable
class ModelEditorAction {
  const ModelEditorAction({required this.label, required this.icon, required this.onPressed, this.key});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? key;
}

/// How much of the top bar fits at a width.
enum BarFit { wide, medium, narrow, tiny }

BarFit barFit(double width) => width >= 1280
    ? BarFit.wide
    : width >= 1000
    ? BarFit.medium
    : width >= 720
    ? BarFit.narrow
    : BarFit.tiny;

class EditorTopBar extends StatefulWidget {
  const EditorTopBar({
    super.key,
    required this.controller,
    required this.renderers,
    required this.active,
    required this.leading,
    this.trailing,
    required this.actions,
    required this.canSave,
    required this.saving,
    required this.onSave,
    required this.onExport,
    required this.onToggleLeft,
    required this.onToggleRight,
  });

  final ModelController controller;
  final List<ModelRenderer> renderers;
  final ModelRenderer active;
  final Widget? leading;

  /// The host's widget at the very end of the bar (an account button).
  final Widget? trailing;
  final List<ModelEditorAction> actions;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;
  final ValueChanged<ModelExport> onExport;
  final VoidCallback? onToggleLeft;
  final VoidCallback? onToggleRight;

  @override
  State<EditorTopBar> createState() => _EditorTopBarState();
}

class _EditorTopBarState extends State<EditorTopBar> {
  late final _search = TextEditingController(text: widget.controller.search);
  final _searchFocus = FocusNode();
  final _title = TextEditingController();
  var _renaming = false;
  var _searchOpen = false;

  @override
  void didUpdateWidget(EditorTopBar old) {
    super.didUpdateWidget(old);
    final text = widget.controller.search;
    if (!_searchFocus.hasFocus && _search.text != text) _search.text = text;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _title.dispose();
    super.dispose();
  }

  void _startRename() {
    final title = widget.controller.model.title;
    setState(() {
      _renaming = true;
      _title.text = title;
      _title.selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    });
  }

  void _commitRename() {
    if (!_renaming) return;
    final c = widget.controller;
    final next = _title.text.trim();
    if (next.isNotEmpty && next != c.model.title) {
      c.tryApply([
        Op.modelSet({'title': next}),
      ]);
    }
    setState(() => _renaming = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Container(
      height: t.barHeight,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.xs),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border(
          bottom: BorderSide(color: t.divider, width: t.borderWidth),
        ),
      ),
      child: LayoutBuilder(builder: (context, bounds) => _row(context, t, barFit(bounds.maxWidth))),
    );
  }

  Widget _row(BuildContext context, ModelTheme t, BarFit fit) {
    final chrome = ModelChrome.of(context);
    final c = widget.controller;
    final gap = SizedBox(width: t.spacing.xxs);
    final editable = !c.readOnly;
    final overflow = fit == BarFit.narrow || fit == BarFit.tiny;
    final search = SizedBox(
      width: fit == BarFit.wide ? 220 : 180,
      child: chrome.searchField(
        key: const ValueKey('model-search'),
        controller: _search,
        focusNode: _searchFocus,
        hint: 'Find area',
        onChanged: (v) => c.search = v,
      ),
    );
    final searching = overflow && _searchOpen;
    final left = Row(
      key: const ValueKey('editor-bar-left'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onToggleLeft != null)
          chrome.iconButton(
            key: const ValueKey('toggle-left-panel'),
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Components and layers',
            size: ModelButtonSize.md,
            onPressed: widget.onToggleLeft,
          ),
        ?widget.leading,
        gap,
        Flexible(child: _titleView(context, t, editable)),
      ],
    );
    final centre = KeyedSubtree(
      key: const ValueKey('editor-bar-centre'),
      child: searching
          ? SizedBox(width: 320, child: search)
          : ViewSwitcher(
              controller: c,
              renderers: widget.renderers,
              active: widget.active,
              labels: fit == BarFit.wide,
              compact: fit == BarFit.tiny,
            ),
    );
    final right = Row(
      key: const ValueKey('editor-bar-right'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overflow)
          chrome.iconButton(
            key: const ValueKey('toggle-search'),
            icon: searching ? Icons.close_rounded : Icons.search_rounded,
            tooltip: searching ? 'Close search' : 'Find area',
            size: ModelButtonSize.md,
            onPressed: () => setState(() => _searchOpen = !_searchOpen),
          )
        else ...[
          search,
          SizedBox(width: t.spacing.xs),
        ],
        if (editable && fit != BarFit.tiny) ...[
          chrome.iconButton(
            key: const ValueKey('editor-undo'),
            icon: Icons.undo_rounded,
            tooltip: 'Undo (${shortcutLabel(ModelKeys.undo)})',
            size: ModelButtonSize.md,
            onPressed: c.canUndo ? c.undo : null,
          ),
          chrome.iconButton(
            key: const ValueKey('editor-redo'),
            icon: Icons.redo_rounded,
            tooltip: 'Redo (${shortcutLabel(ModelKeys.redo)})',
            size: ModelButtonSize.md,
            onPressed: c.canRedo ? c.redo : null,
          ),
        ],
        if (overflow)
          chrome.menuButton(
            key: const ValueKey('editor-more'),
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            items: _more(fit),
          )
        else ...[
          chrome.menuButton(
            key: const ValueKey('editor-export'),
            icon: Icons.ios_share_rounded,
            tooltip: 'Export',
            items: [
              for (final e in ModelExport.values) ModelMenuItem(label: e.label, onSelected: () => widget.onExport(e)),
            ],
          ),
          for (final (i, a) in widget.actions.indexed) ...[
            gap,
            // Only the first action, the host's lead, has room for its label.
            if (i == 0 && fit == BarFit.wide)
              chrome.button(
                key: a.key,
                label: a.label,
                icon: a.icon,
                variant: ModelButtonVariant.primary,
                size: ModelButtonSize.sm,
                onPressed: a.onPressed,
              )
            else
              chrome.iconButton(
                key: a.key,
                icon: a.icon,
                tooltip: a.label,
                size: ModelButtonSize.md,
                onPressed: a.onPressed,
              ),
          ],
        ],
        if (widget.canSave && editable) ...[
          SizedBox(width: t.spacing.xs),
          chrome.button(
            key: const ValueKey('editor-save'),
            label: widget.saving ? 'Saving…' : 'Save',
            icon: Icons.check_rounded,
            variant: ModelButtonVariant.primary,
            size: ModelButtonSize.sm,
            onPressed: c.dirty && !widget.saving ? widget.onSave : null,
          ),
        ],
        if (widget.onToggleRight != null) ...[
          gap,
          chrome.iconButton(
            key: const ValueKey('toggle-right-panel'),
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Inspector',
            size: ModelButtonSize.md,
            onPressed: widget.onToggleRight,
          ),
        ],
        if (widget.trailing case final trailing?) ...[SizedBox(width: t.spacing.xs), trailing],
      ],
    );
    return CustomMultiChildLayout(
      delegate: _BarSlots(gap: t.spacing.sm),
      children: [
        LayoutId(id: _Slot.left, child: left),
        LayoutId(id: _Slot.centre, child: centre),
        LayoutId(id: _Slot.right, child: right),
      ],
    );
  }

  List<ModelMenuItem> _more(BarFit fit) {
    final c = widget.controller;
    return [
      if (fit == BarFit.tiny && !c.readOnly) ...[
        if (c.canUndo) ModelMenuItem(label: 'Undo', icon: Icons.undo_rounded, onSelected: c.undo),
        if (c.canRedo) ModelMenuItem(label: 'Redo', icon: Icons.redo_rounded, onSelected: c.redo),
      ],
      for (final a in widget.actions)
        if (a.onPressed != null) ModelMenuItem(label: a.label, icon: a.icon, onSelected: a.onPressed!),
      for (final e in ModelExport.values)
        ModelMenuItem(label: e.label, icon: Icons.ios_share_rounded, onSelected: () => widget.onExport(e)),
    ];
  }

  Widget _titleView(BuildContext context, ModelTheme t, bool editable) {
    final c = widget.controller;
    if (_renaming) {
      return SizedBox(
        width: 260,
        child: InlineRenameField(
          controller: _title,
          onCommit: _commitRename,
          onCancel: () => setState(() => _renaming = false),
        ),
      );
    }
    final title = Text(
      c.model.title,
      key: const ValueKey('editor-title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.heading,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: editable
              ? MouseRegion(
                  cursor: SystemMouseCursors.text,
                  child: ModelChrome.of(context).tooltip(
                    message: 'Rename the model',
                    child: GestureDetector(onTap: _startRename, child: title),
                  ),
                )
              : title,
        ),
        if (c.dirty && !c.readOnly) ...[
          SizedBox(width: t.spacing.xs),
          ModelChrome.of(
            context,
          ).statusDot(key: const ValueKey('editor-dirty'), color: t.focus, tooltip: 'Unsaved changes'),
        ],
      ],
    );
  }
}

enum _Slot { left, centre, right }

/// The bar's three slots: the left group pinned to the start, the right
/// group flush with the end, and the centre on the bar's own centre line
/// (nudged left only when the right group would meet it). The left group
/// gets what is left before the centre, so the title takes the free room
/// and ellipsizes first; the groups never overlap.
class _BarSlots extends MultiChildLayoutDelegate {
  _BarSlots({required this.gap});

  final double gap;

  @override
  void performLayout(Size size) {
    final right = layoutChild(_Slot.right, BoxConstraints.loose(size));
    final centre = layoutChild(
      _Slot.centre,
      BoxConstraints.loose(Size(math.max(0, size.width - right.width - gap), size.height)),
    );
    final x = math.max(0.0, math.min((size.width - centre.width) / 2, size.width - right.width - gap - centre.width));
    final left = layoutChild(_Slot.left, BoxConstraints.loose(Size(math.max(0, x - gap), size.height)));
    double middle(Size s) => (size.height - s.height) / 2;
    positionChild(_Slot.left, Offset(0, middle(left)));
    positionChild(_Slot.centre, Offset(x, middle(centre)));
    positionChild(_Slot.right, Offset(size.width - right.width, middle(right)));
  }

  @override
  bool shouldRelayout(_BarSlots old) => old.gap != gap;
}
