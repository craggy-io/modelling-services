// file_source.dart: models in files (design §6.2). Opens `.model.json`
// (and imports Mermaid `.mmd` and outline `.md`) through file_selector on
// desktop and the web; saves in place on desktop, as a download on the web.
// The platform half lives in platform/, behind a conditional import.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:modelling/modelling.dart';

import 'model_source.dart';
import 'platform/file_platform.dart' as files;

/// Models in local files. Ids are paths on desktop and file names on the
/// web; opened files are kept for [read] during the session.
class FileModelSource implements ModelSource {
  FileModelSource({this.maxRecents = 10});

  final int maxRecents;
  final _opened = <String, LoadedModel>{};

  /// The file types [open] offers.
  static const typeGroups = [
    XTypeGroup(label: 'Models', extensions: ['json']),
    XTypeGroup(label: 'Mermaid', extensions: ['mmd']),
    XTypeGroup(label: 'Outline', extensions: ['md']),
  ];

  /// Asks the user for a file and loads it; null when cancelled.
  Future<LoadedModel?> open() async {
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (file == null) return null;
    final id = file.path.isEmpty ? file.name : file.path;
    return load(id, await file.readAsString());
  }

  /// Reads [text] by [id]'s extension: Mermaid (`.mmd`), outline (`.md`)
  /// or a model document. Imports are saved as new `.model.json` files.
  LoadedModel load(String id, String text) {
    final lower = id.toLowerCase();
    final model = lower.endsWith('.mmd')
        ? parseMermaid(text)
        : lower.endsWith('.md')
        ? parseOutline(text)
        : Model.decode(text);
    final loaded = LoadedModel(model: model, summary: ModelSummary.of(id, model));
    _opened[id] = loaded;
    _remember(id);
    return loaded;
  }

  void _remember(String id) {
    final recents = [id, ...files.readRecents().where((r) => r != id)];
    files.writeRecents(recents.take(maxRecents).toList());
  }

  /// Recently opened files (titles known for those opened this session).
  @override
  Future<List<ModelSummary>> list() async => [
    for (final id in files.readRecents()) _opened[id]?.summary ?? ModelSummary(id: id, title: _name(id)),
  ];

  @override
  Future<LoadedModel> read(String id) async {
    final have = _opened[id];
    if (have != null) return have;
    if (!files.canWriteInPlace) throw StateError('open "$id" again to read it in this browser session');
    return load(id, await XFile(id).readAsString());
  }

  /// Writes [result]: in place for a `.json` file on desktop, else through
  /// a save dialog (desktop) or a download (web).
  @override
  Future<ModelSummary> save(LoadedModel at, List<Op> ops, Model result) => _write(at, result, inPlace: true);

  /// Writes [result] to a new file: a save dialog (desktop) or a download
  /// (web). Throws [StateError] when cancelled.
  Future<ModelSummary> saveAs(LoadedModel at, Model result) => _write(at, result, inPlace: false);

  Future<ModelSummary> _write(LoadedModel at, Model result, {required bool inPlace}) async {
    final bytes = Uint8List.fromList(utf8.encode(result.encode()));
    var id = at.summary.id;
    if (inPlace && files.canWriteInPlace && id.toLowerCase().endsWith('.json')) {
      await files.writePath(id, bytes);
    } else {
      final saved = await files.saveBytes(
        _suggest(id),
        bytes,
        mimeType: 'application/json',
        extensions: const ['json'],
      );
      if (saved == null) throw StateError('save cancelled');
      id = saved;
    }
    final summary = ModelSummary.of(id, result);
    _opened[id] = LoadedModel(model: result, summary: summary, base: at.base);
    _remember(id);
    return summary;
  }

  static String _name(String id) => id.split(RegExp(r'[\\/]')).last;

  static String _suggest(String id) {
    final name = _name(id);
    final stem = name.replaceFirst(RegExp(r'(\.model)?\.(json|mmd|md)$', caseSensitive: false), '');
    return '${stem.isEmpty ? 'model' : stem}.model.json';
  }
}
