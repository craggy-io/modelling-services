// workspace_toolbar.dart: "Find area", "Changed only", renderer switcher,
// overlay picker, undo/redo/save when editable, and the export menu.

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../renderers/model_renderer.dart';
import '../theme/model_theme.dart';
import 'model_export.dart';

class WorkspaceToolbar extends StatefulWidget {
  const WorkspaceToolbar({
    super.key,
    required this.controller,
    required this.renderers,
    required this.active,
    required this.canSave,
    required this.saving,
    required this.onSave,
    required this.capture,
    this.exportName,
  });

  final ModelController controller;
  final List<ModelRenderer> renderers;
  final ModelRenderer active;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;
  final GlobalKey Function() capture;
  final String? exportName;

  @override
  State<WorkspaceToolbar> createState() => _WorkspaceToolbarState();
}

class _WorkspaceToolbarState extends State<WorkspaceToolbar> {
  late final _search = TextEditingController(text: widget.controller.search);
  final _searchFocus = FocusNode();

  @override
  void didUpdateWidget(WorkspaceToolbar old) {
    super.didUpdateWidget(old);
    final text = widget.controller.search;
    if (!_searchFocus.hasFocus && _search.text != text) _search.text = text;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = widget.controller;
    final search = chrome.searchField(
      key: const ValueKey('model-search'),
      controller: _search,
      focusNode: _searchFocus,
      hint: 'Find area',
      onChanged: (v) => c.search = v,
    );
    final actions = <Widget>[
      if (!c.diff.isEmpty)
        chrome.filterChip(
          label: 'Changed only',
          selected: c.changedOnly,
          tooltip: c.changedOnly ? 'Show the whole model' : 'Hide what still matches the base',
          onPressed: () => c.changedOnly = !c.changedOnly,
        ),
      if (widget.renderers.length > 1)
        for (final r in widget.renderers)
          chrome.filterChip(
            key: ValueKey('renderer-${r.id}'),
            label: r.label,
            selected: r.id == widget.active.id,
            tooltip: 'Show as ${r.label.toLowerCase()}',
            onPressed: () => c.renderer = r.id,
          ),
      if (c.overlays.isNotEmpty)
        SizedBox(
          width: 180,
          child: chrome.select<String?>(
            key: const ValueKey('overlay-picker'),
            value: c.activeOverlay,
            label: 'Overlay',
            options: [
              const ModelOption<String?>(null, 'None'),
              for (final o in c.overlays) ModelOption<String?>(o.id, o.label),
            ],
            onChanged: (id) => c.activeOverlay = id,
          ),
        ),
      if (!c.readOnly) ...[
        chrome.button(
          key: const ValueKey('add-area'),
          label: 'Add area',
          icon: Icons.add,
          size: ModelButtonSize.sm,
          onPressed: c.addArea,
        ),
        chrome.iconButton(
          icon: Icons.undo,
          tooltip: 'Undo',
          size: ModelButtonSize.md,
          onPressed: c.canUndo ? c.undo : null,
        ),
        chrome.iconButton(
          icon: Icons.redo,
          tooltip: 'Redo',
          size: ModelButtonSize.md,
          onPressed: c.canRedo ? c.redo : null,
        ),
        if (widget.canSave)
          chrome.button(
            label: widget.saving ? 'Saving…' : 'Save',
            icon: Icons.save_outlined,
            variant: ModelButtonVariant.primary,
            size: ModelButtonSize.sm,
            onPressed: c.dirty && !widget.saving ? widget.onSave : null,
          ),
      ],
      chrome.menuButton(
        icon: Icons.ios_share,
        tooltip: 'Export',
        items: [
          for (final e in ModelExport.values)
            ModelMenuItem(
              label: e.label,
              onSelected: () => runExport(
                c,
                e,
                stem: widget.exportName ?? exportStem(c.model),
                capture: widget.capture(),
                pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 2,
              ),
            ),
        ],
      ),
    ];
    final wrap = Wrap(
      spacing: t.spacing.xs,
      runSpacing: t.spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              SizedBox(height: t.spacing.xs),
              wrap,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: search),
            SizedBox(width: t.spacing.xs),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: wrap),
            ),
          ],
        );
      },
    );
  }
}
