// host_model_source.dart: models in the host's source (design §6.2), for
// signed-in users. Saves send the whole result model as `.model.json`
// text with its {title, subject}; the ops aren't needed by a
// whole-document store. Each model's version stays inside the host.

import 'package:modelling/modelling.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'host.dart';

class HostModelSource implements ModelSource {
  HostModelSource(this._host);

  final HostSource _host;

  /// Ids read from or saved to the host; saving any other model makes a
  /// new one.
  final _held = <String>{};

  /// What the host calls its source.
  String get label => _host.label;

  /// Whether [id] is a model in the host.
  bool holds(String id) => _held.contains(id);

  /// The host's models, with when each last changed.
  Future<List<HostEntry>> entries() => _host.list();

  @override
  Future<List<ModelSummary>> list() async => [
    for (final e in await entries()) ModelSummary(id: e.id, title: e.title, subject: e.subject),
  ];

  @override
  Future<LoadedModel> read(String id) async {
    final model = Model.decode(await _host.read(id));
    _held.add(id);
    return LoadedModel(model: model, summary: ModelSummary.of(id, model));
  }

  /// Writes [result] over [at] when [at] is in the host, else as a new
  /// model.
  @override
  Future<ModelSummary> save(LoadedModel at, List<Op> ops, Model result) =>
      _write(holds(at.summary.id) ? at.summary.id : null, result);

  /// Writes [result] as a new model.
  Future<ModelSummary> saveAs(Model result) => _write(null, result);

  Future<void> remove(String id) async {
    await _host.remove(id);
    _held.remove(id);
  }

  Future<ModelSummary> _write(String? id, Model result) async {
    final saved = await _host.save(id, result.encode(), title: result.title, subject: result.subject);
    _held.add(saved);
    return ModelSummary.of(saved, result);
  }
}
