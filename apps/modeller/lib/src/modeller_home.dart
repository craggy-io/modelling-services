// modeller_home.dart: the editor: a ModelEditor (grid blocks, palette,
// docked inspector, every renderer) over the open model, with the app's
// File menu (new, templates, import, open, save, save as, export) at the
// start of its top bar, and connecting an agent and the gallery among its
// actions. The profile
// picker is the editor's model overview. Unsaved edits are confirmed
// before they are discarded. A model linked in the page address opens
// first, unsaved.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'agent_dialog.dart';
import 'gallery_page.dart';
import 'import_dialog.dart';
import 'model_link.dart';
import 'samples.dart';

class ModellerHome extends StatefulWidget {
  const ModellerHome({super.key, required this.bundled, this.linked = (model: null, error: null)});

  final Bundled bundled;

  /// The model linked in the page address (see [readLinkedModel]): it
  /// opens as a new unsaved document; an error shows in the status bar.
  final LinkedModel linked;

  @override
  State<ModellerHome> createState() => _ModellerHomeState();
}

class _ModellerHomeState extends State<ModellerHome> {
  final _source = FileModelSource();
  final _exportKey = GlobalKey(debugLabel: 'modeller export');
  late LoadedModel _loaded;
  late ModelController _c;

  @override
  void initState() {
    super.initState();
    final (model: linked, error: failed) = widget.linked;
    _loaded = _untitled(linked ?? Model.empty('Untitled model', 'New model'));
    _c = _controllerFor(_loaded, renderer: 'blocks', saved: linked == null)..notice.value = failed;
  }

  /// A model with no file yet: saving asks where, named after its title.
  static LoadedModel _untitled(Model m) => LoadedModel(
    model: m,
    summary: ModelSummary(id: exportStem(m), title: m.title, subject: m.subject),
  );

  ModelController _controllerFor(LoadedModel loaded, {required String renderer, bool saved = true}) => ModelController(
    loaded.model,
    base: loaded.base,
    profile: widget.bundled.profileFor(loaded.model),
    renderer: renderer,
    saved: saved,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Shows [loaded] in a fresh controller, keeping the renderer.
  void _show(LoadedModel loaded) {
    final old = _c;
    setState(() {
      _loaded = loaded;
      _c = _controllerFor(loaded, renderer: old.renderer);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Whether the open model's unsaved edits may be dropped (asks if any).
  Future<bool> _mayDiscard() async {
    if (!_c.dirty) return true;
    return ModelChrome.of(context).confirm(
      context,
      title: 'Discard unsaved changes?',
      message: '"${_c.model.title}" has edits that are not saved. Discard them?',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  Future<void> _replaceWith(LoadedModel? loaded) async {
    if (loaded == null || !await _mayDiscard() || !mounted) return;
    _show(loaded);
  }

  Future<void> _newBlank() => _replaceWith(_untitled(Model.empty('Untitled model', 'New model')));

  Future<void> _newFrom(Template t) => _replaceWith(_untitled(widget.bundled.templates[t.id]!));

  Future<void> _import() async {
    final m = await showImportDialog(context);
    await _replaceWith(m == null ? null : _untitled(m));
  }

  Future<void> _open() async {
    try {
      await _replaceWith(await _source.open());
    } on Object catch (e) {
      _c.notice.value = 'Could not open: $e';
    }
  }

  /// Stores the model and remembers where; the workspace's Save and the
  /// File menu both come here.
  Future<void> _store(List<Op> ops, Model result, {bool asNew = false}) async {
    final saved = asNew ? await _source.saveAs(_loaded, result) : await _source.save(_loaded, ops, result);
    setState(() => _loaded = LoadedModel(model: result, summary: saved, base: _loaded.base));
    _c.notice.value = 'Saved ${saved.id}.';
  }

  Future<void> _save({bool asNew = false}) async {
    final c = _c, result = c.model;
    try {
      await _store(c.pendingOps, result, asNew: asNew);
      if (c.model == result) c.markSaved();
    } on StateError catch (e) {
      c.notice.value = e.message;
    } on Object catch (e) {
      c.notice.value = 'Could not save: $e';
    }
  }

  void _openGallery() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GalleryPage(bundled: widget.bundled)));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: RepaintBoundary(
        key: _exportKey,
        child: ModelEditor(
          key: ObjectKey(_c),
          controller: _c,
          renderers: modellerRenderers,
          profiles: widget.bundled.profiles,
          exportName: exportStem(_c.model),
          onSave: _store,
          onOpenLink: (link) => _c.notice.value = 'Open ${link.model} with File › Open.',
          onEvidence: (ref) => _c.notice.value = 'Evidence ${ref.scheme}:${ref.id}${ref.selector}',
          leading: _menu(),
          shortcuts: {ModelKeys.newModel: _newBlank, ModelKeys.open: _open, ModelKeys.saveAs: () => _save(asNew: true)},
          actions: [
            ModelEditorAction(
              key: const ValueKey('connect-agent'),
              label: 'Connect agent',
              icon: Icons.smart_toy_outlined,
              onPressed: () => showAgentDialog(context),
            ),
            ModelEditorAction(
              key: const ValueKey('open-gallery'),
              label: 'Gallery',
              icon: Icons.grid_view_rounded,
              onPressed: _openGallery,
            ),
          ],
        ),
      ),
    ),
  );

  /// The File menu, drawn by the editor's chrome like its other menus.
  Widget _menu() => ModelChrome.of(context).menu(
    key: const ValueKey('file-menu'),
    label: 'File',
    entries: [
      ModelMenuItem(
        label: 'New blank',
        icon: Icons.note_add_outlined,
        shortcut: ModelKeys.newModel,
        onSelected: _newBlank,
      ),
      ModelSubmenu(
        label: 'New from template',
        icon: Icons.dashboard_customize_outlined,
        entries: [for (final t in modellerTemplates) ModelMenuItem(label: t.title, onSelected: () => _newFrom(t))],
      ),
      ModelMenuItem(label: 'Import Mermaid or outline…', icon: Icons.input_rounded, onSelected: _import),
      ModelMenuItem(label: 'Open…', icon: Icons.folder_open_outlined, shortcut: ModelKeys.open, onSelected: _open),
      const ModelMenuDivider(),
      ModelMenuItem(label: 'Save', icon: Icons.save_outlined, shortcut: ModelKeys.save, onSelected: _save),
      ModelMenuItem(
        label: 'Save as…',
        icon: Icons.save_as_outlined,
        shortcut: ModelKeys.saveAs,
        onSelected: () => _save(asNew: true),
      ),
      const ModelMenuDivider(),
      ModelSubmenu(
        label: 'Export',
        icon: Icons.ios_share_rounded,
        entries: [
          for (final e in ModelExport.values)
            ModelMenuItem(
              label: e.label,
              onSelected: () => runExport(_c, e, stem: exportStem(_c.model), capture: _exportKey),
            ),
        ],
      ),
    ],
  );
}
