// model_workspace.dart: the toolbar, status line and active renderer for one
// controller, with the host's theme, chrome and hooks (design §7.5).

import 'package:flutter/material.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../renderers/blocks/blocks_renderer.dart';
import '../renderers/model_renderer.dart';
import '../renderers/outline/outline_renderer.dart';
import '../theme/model_theme.dart';
import 'model_hooks.dart';
import 'model_shortcuts.dart';
import 'workspace_status.dart';
import 'workspace_toolbar.dart';

/// A model's workspace: "Find area" search, "Changed only", renderer and
/// overlay pickers, undo/redo and save when editable, export, the status
/// line and the active renderer.
class ModelWorkspace extends StatefulWidget {
  const ModelWorkspace({
    super.key,
    required this.controller,
    this.theme,
    this.chrome,
    this.renderers = const [BlocksRenderer(), OutlineRenderer()],
    this.onEvidence,
    this.onAttachEvidence,
    this.onOpenLink,
    this.onSave,
    this.openLabel = 'Open',
    this.exportName,
  });

  final ModelController controller;

  /// Overrides the inherited [ModelTheme].
  final ModelTheme? theme;

  /// Overrides the inherited [ModelChrome].
  final ModelChrome? chrome;

  /// Renderers to switch between; the controller's `renderer` picks one.
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

  @override
  State<ModelWorkspace> createState() => _ModelWorkspaceState();
}

class _ModelWorkspaceState extends State<ModelWorkspace> {
  final _capture = GlobalKey(debugLabel: 'model capture');
  final _fallbackCapture = GlobalKey(debugLabel: 'workspace capture');
  late ModelHooks _hooks = _makeHooks();
  var _saving = false;

  ModelHooks _makeHooks() => ModelHooks(
    onEvidence: widget.onEvidence,
    onAttachEvidence: widget.onAttachEvidence,
    onOpenLink: widget.onOpenLink,
    openLabel: widget.openLabel,
    captureKey: _capture,
  );

  @override
  void didUpdateWidget(ModelWorkspace old) {
    super.didUpdateWidget(old);
    if (old.onEvidence != widget.onEvidence ||
        old.onAttachEvidence != widget.onAttachEvidence ||
        old.onOpenLink != widget.onOpenLink ||
        old.openLabel != widget.openLabel) {
      _hooks = _makeHooks();
    }
  }

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
    final t = ModelTheme.of(context);
    return ModelShortcuts(
      controller: c,
      onSave: widget.onSave == null ? null : _save,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final renderer = _renderer;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspaceToolbar(
                controller: c,
                renderers: widget.renderers,
                active: renderer,
                canSave: widget.onSave != null,
                saving: _saving,
                onSave: _save,
                exportName: widget.exportName,
                capture: () => _capture.currentContext == null ? _fallbackCapture : _capture,
              ),
              SizedBox(height: t.spacing.xs),
              WorkspaceStatus(controller: c, shown: renderer.shownAreas(c, t)),
              SizedBox(height: t.spacing.xs),
              Expanded(
                child: RepaintBoundary(
                  key: _fallbackCapture,
                  child: KeyedSubtree(key: ValueKey('renderer-${renderer.id}'), child: renderer.build(context, c)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
