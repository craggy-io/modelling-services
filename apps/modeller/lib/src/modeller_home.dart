// modeller_home.dart: the editor: a File menu (new, templates, import,
// open, save, save as, export), a profile picker, the gallery, and a
// ModelWorkspace with every renderer over the open model. Unsaved edits
// are confirmed before they are discarded.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'gallery_page.dart';
import 'import_dialog.dart';
import 'samples.dart';

class ModellerHome extends StatefulWidget {
  const ModellerHome({super.key, required this.bundled});

  final Bundled bundled;

  @override
  State<ModellerHome> createState() => _ModellerHomeState();
}

class _ModellerHomeState extends State<ModellerHome> {
  final _source = FileModelSource();
  final _exportKey = GlobalKey(debugLabel: 'modeller export');
  late LoadedModel _loaded = _untitled(Model.empty('Untitled model', 'New model'));
  late ModelController _c = _controllerFor(_loaded, renderer: 'blocks');

  /// A model with no file yet: saving asks where, named after its title.
  static LoadedModel _untitled(Model m) => LoadedModel(
    model: m,
    summary: ModelSummary(id: exportStem(m), title: m.title, subject: m.subject),
  );

  ModelController _controllerFor(LoadedModel loaded, {required String renderer}) => ModelController(
    loaded.model,
    base: loaded.base,
    profile: widget.bundled.profileFor(loaded.model),
    renderer: renderer,
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
  Widget build(BuildContext context) => ListenableBuilder(listenable: _c, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final c = _c;
    final t = ModelTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _menu(),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
                  child: Text(
                    '${c.model.title}${c.dirty ? ' •' : ''}',
                    key: const ValueKey('modeller-title'),
                    style: t.heading,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 240,
                  child: ModelChrome.of(context).select<Profile?>(
                    key: const ValueKey('profile-picker'),
                    label: 'Profile',
                    value: c.profile,
                    options: [
                      const ModelOption<Profile?>(null, 'No profile'),
                      for (final p in widget.bundled.profiles)
                        ModelOption<Profile?>(p, p.title.isEmpty ? p.id : p.title),
                    ],
                    onChanged: (p) => c.useProfile(p),
                  ),
                ),
                SizedBox(width: t.spacing.sm),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(t.spacing.md),
                child: RepaintBoundary(
                  key: _exportKey,
                  child: ModelWorkspace(
                    key: ObjectKey(c),
                    controller: c,
                    renderers: modellerRenderers,
                    exportName: exportStem(c.model),
                    onSave: _store,
                    onOpenLink: (link) => c.notice.value = 'Open ${link.model} with File › Open.',
                    onEvidence: (ref) => c.notice.value = 'Evidence ${ref.scheme}:${ref.id}${ref.selector}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() => MenuBar(
    style: const MenuStyle(
      elevation: WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    children: [
      SubmenuButton(
        menuChildren: [
          MenuItemButton(onPressed: _newBlank, child: const Text('New blank')),
          SubmenuButton(
            menuChildren: [
              for (final t in modellerTemplates) MenuItemButton(onPressed: () => _newFrom(t), child: Text(t.title)),
            ],
            child: const Text('New from template'),
          ),
          MenuItemButton(onPressed: _import, child: const Text('Import Mermaid or outline…')),
          MenuItemButton(onPressed: _open, child: const Text('Open…')),
          const Divider(),
          MenuItemButton(onPressed: _save, child: const Text('Save')),
          MenuItemButton(onPressed: () => _save(asNew: true), child: const Text('Save as…')),
          const Divider(),
          SubmenuButton(
            menuChildren: [
              for (final e in ModelExport.values)
                MenuItemButton(
                  onPressed: () => runExport(_c, e, stem: exportStem(_c.model), capture: _exportKey),
                  child: Text(e.label),
                ),
            ],
            child: const Text('Export'),
          ),
        ],
        child: const Text('File'),
      ),
      MenuItemButton(onPressed: _openGallery, child: const Text('Gallery')),
    ],
  );
}
