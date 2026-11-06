// model_editor.dart: a full editor shell around one controller, for hosts
// that want a design tool rather than a board (design §7.7): a top bar, a
// left panel with the component palette and the layers tree, the active
// renderer, the inspector docked on the right, and a status bar. Side
// panels resize by their edge, collapse, and below [ModelEditor.drawerWidth]
// become drawers. ModelWorkspace stays the compact host widget.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../inspector/inspector_panel.dart';
import '../renderers/blocks/blocks_renderer.dart';
import '../renderers/model_renderer.dart';
import '../renderers/outline/outline_renderer.dart';
import '../shared/board_insets.dart';
import '../theme/model_theme.dart';
import '../workspace/model_export.dart';
import '../workspace/model_hooks.dart';
import '../workspace/model_shortcuts.dart';
import 'component_palette.dart';
import 'editor_panels.dart';
import 'editor_status_bar.dart';
import 'editor_top_bar.dart';
import 'layers_tree.dart';

class ModelEditor extends StatefulWidget {
  const ModelEditor({
    super.key,
    required this.controller,
    this.theme,
    this.chrome,
    this.renderers = const [BlocksRenderer(grid: true), OutlineRenderer()],
    this.onEvidence,
    this.onAttachEvidence,
    this.onOpenLink,
    this.onSave,
    this.openLabel = 'Open',
    this.exportName,
    this.leading,
    this.actions = const [],
    this.shortcuts = const {},
    this.profiles = const [],
    this.palette = true,
    this.inspector = true,
  });

  /// Below this width the side panels are drawers over the board.
  static const drawerWidth = 900.0;

  final ModelController controller;

  /// Overrides the inherited [ModelTheme].
  final ModelTheme? theme;

  /// Overrides the inherited [ModelChrome].
  final ModelChrome? chrome;

  /// Renderers the view switcher offers; the controller's `renderer` picks.
  final List<ModelRenderer> renderers;
  final ModelEvidenceHook? onEvidence;
  final ModelAttachHook? onAttachEvidence;
  final ModelLinkHook? onOpenLink;

  /// Stores edits; on success the controller is marked saved. Null hides
  /// Save.
  final ModelSaveHook? onSave;
  final String openLabel;

  /// File name stem for exports (defaults to a slug of the title).
  final String? exportName;

  /// The host's widget at the start of the top bar (a File menu, a back
  /// button).
  final Widget? leading;

  /// The host's top bar actions.
  final List<ModelEditorAction> actions;

  /// The host's own keys over the editor (the modeller's Ctrl+N, Ctrl+O
  /// and Ctrl+Shift+S; see [ModelKeys]).
  final Map<ShortcutActivator, VoidCallback> shortcuts;

  /// Profiles the model overview offers.
  final List<Profile> profiles;

  /// Shows the left panel (palette and layers).
  final bool palette;

  /// Docks the inspector on the right (else inspecting opens a dialog).
  final bool inspector;

  @override
  State<ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<ModelEditor> {
  final _capture = GlobalKey(debugLabel: 'editor capture');
  final _fallbackCapture = GlobalKey(debugLabel: 'editor board');
  late ModelHooks _hooks = _makeHooks();
  var _saving = false;
  var _leftOpen = true, _rightOpen = true;
  var _leftDrawer = false, _rightDrawer = false;
  var _narrow = false;

  ModelHooks _makeHooks() => ModelHooks(
    onEvidence: widget.onEvidence,
    onAttachEvidence: widget.onAttachEvidence,
    onOpenLink: widget.onOpenLink,
    onInspect: widget.inspector ? (_) => _showInspector() : null,
    openLabel: widget.openLabel,
    captureKey: _capture,
  );

  @override
  void didUpdateWidget(ModelEditor old) {
    super.didUpdateWidget(old);
    if (old.onEvidence != widget.onEvidence ||
        old.onAttachEvidence != widget.onAttachEvidence ||
        old.onOpenLink != widget.onOpenLink ||
        old.openLabel != widget.openLabel ||
        old.inspector != widget.inspector) {
      _hooks = _makeHooks();
    }
  }

  void _showInspector() {
    if (_narrow) {
      if (!_rightDrawer) setState(() => _rightDrawer = true);
    } else if (!_rightOpen) {
      setState(() => _rightOpen = true);
    }
  }

  void _toggle(PanelSide side) => setState(() {
    final left = side == PanelSide.left;
    if (_narrow) {
      left ? _leftDrawer = !_leftDrawer : _rightDrawer = !_rightDrawer;
      left ? _rightDrawer = false : _leftDrawer = false;
    } else {
      left ? _leftOpen = !_leftOpen : _rightOpen = !_rightOpen;
    }
  });

  ModelRenderer get _renderer {
    final id = widget.controller.renderer;
    return widget.renderers.firstWhere((r) => r.id == id, orElse: () => widget.renderers.first);
  }

  Future<void> _save() async {
    final save = widget.onSave;
    final c = widget.controller;
    if (save == null || !c.dirty || _saving) return;
    setState(() => _saving = true);
    await saveThrough(c, save);
    if (mounted) setState(() => _saving = false);
  }

  void _export(BuildContext context, ModelExport e) => runExport(
    widget.controller,
    e,
    stem: widget.exportName ?? exportStem(widget.controller.model),
    capture: _capture.currentContext == null ? _fallbackCapture : _capture,
    pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 2,
  );

  @override
  Widget build(BuildContext context) {
    Widget child = ModelHooksScope(
      hooks: _hooks,
      child: Builder(builder: _build),
    );
    if (widget.chrome != null) child = ModelChromeScope(chrome: widget.chrome!, child: child);
    if (widget.theme != null) child = ModelThemeScope(theme: widget.theme!, child: child);
    return child;
  }

  Widget _build(BuildContext context) {
    final c = widget.controller;
    return ModelShortcuts(
      controller: c,
      onSave: widget.onSave == null ? null : _save,
      bindings: widget.shortcuts,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => LayoutBuilder(
          builder: (context, bounds) {
            _narrow = bounds.maxWidth < ModelEditor.drawerWidth;
            return _layout(context, ModelTheme.of(context));
          },
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, ModelTheme t) {
    final c = widget.controller;
    final renderer = _renderer;
    final grid = renderer is BlocksRenderer && renderer.grid;
    final left = widget.palette ? _leftPanel(context, t) : null;
    final right = widget.inspector ? DockedInspector(controller: c, profiles: widget.profiles) : null;
    final board = ColoredBox(
      color: t.canvas,
      child: RepaintBoundary(
        key: _fallbackCapture,
        // Every renderer fills the board edge to edge; the others keep
        // their content off the edges themselves, through BoardInsets.
        child: SizedBox.expand(
          child: KeyedSubtree(
            key: ValueKey('renderer-view-${renderer.id}'),
            child: grid
                ? renderer.build(context, c)
                : BoardInsets(padding: EdgeInsets.all(t.spacing.md), child: renderer.build(context, c)),
          ),
        ),
      ),
    );
    final Widget middle;
    if (_narrow) {
      middle = Stack(
        children: [
          Positioned.fill(child: board),
          if (left != null)
            Positioned.fill(
              child: PanelDrawer(
                side: PanelSide.left,
                open: _leftDrawer,
                onClose: () => setState(() => _leftDrawer = false),
                panel: left,
              ),
            ),
          if (right != null)
            Positioned.fill(
              child: PanelDrawer(
                side: PanelSide.right,
                open: _rightDrawer,
                onClose: () => setState(() => _rightDrawer = false),
                panel: right,
              ),
            ),
        ],
      );
    } else {
      middle = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (left != null) _docked(PanelSide.left, _leftOpen, t.panelWidth, left),
          Expanded(child: board),
          if (right != null) _docked(PanelSide.right, _rightOpen, t.inspectorWidth, right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorTopBar(
          controller: c,
          renderers: widget.renderers,
          active: renderer,
          leading: widget.leading,
          actions: widget.actions,
          canSave: widget.onSave != null,
          saving: _saving,
          onSave: _save,
          onExport: (e) => _export(context, e),
          onToggleLeft: left == null ? null : () => _toggle(PanelSide.left),
          onToggleRight: right == null ? null : () => _toggle(PanelSide.right),
        ),
        Expanded(child: middle),
        EditorStatusBar(
          controller: c,
          shown: renderer.shownAreas(c, t),
          zoomable: grid,
          onLint: () {
            c.select(null);
            _showInspector();
          },
        ),
      ],
    );
  }

  Widget _docked(PanelSide side, bool open, double initial, Widget child) => DockedPanel(
    side: side,
    open: open,
    width: panelWidths[side] ?? initial,
    onResize: (w) => setState(() => panelWidths[side] = w),
    child: child,
  );

  Widget _leftPanel(BuildContext context, ModelTheme t) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!c.readOnly)
          PanelSection(
            title: c.profile == null ? 'Components' : 'Components · ${c.profile!.title}',
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.spacing.sm, 0, t.spacing.sm, t.spacing.sm),
              child: ComponentPalette(controller: c),
            ),
          ),
        Container(height: t.borderWidth, color: t.divider),
        Expanded(
          child: PanelSection(
            title: 'Layers',
            expand: true,
            child: LayersTree(controller: c),
          ),
        ),
      ],
    );
  }
}
