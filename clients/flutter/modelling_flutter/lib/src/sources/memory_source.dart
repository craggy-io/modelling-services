// memory_source.dart: a ModelSource held in memory, for tests and the
// gallery. Saving applies the ops to the stored model, as a server would.

import 'package:modelling/modelling.dart';

import 'model_source.dart';

class MemoryModelSource implements ModelSource {
  MemoryModelSource([Map<String, Model> models = const {}, Map<String, Model> bases = const {}])
    : _models = {...models},
      _bases = {...bases};

  final Map<String, Model> _models;
  final Map<String, Model> _bases;

  /// Ids that read as not editable.
  final readOnly = <String>{};

  /// Stores [model] under [id], with an optional [base] to compare against.
  void put(String id, Model model, {Model? base}) {
    _models[id] = model;
    if (base != null) _bases[id] = base;
  }

  /// The stored model, if any.
  Model? operator [](String id) => _models[id];

  @override
  Future<List<ModelSummary>> list() async => [for (final e in _models.entries) ModelSummary.of(e.key, e.value)];

  @override
  Future<LoadedModel> read(String id) async {
    final m = _models[id];
    if (m == null) throw StateError('no model "$id"');
    return LoadedModel(model: m, summary: ModelSummary.of(id, m), editable: !readOnly.contains(id), base: _bases[id]);
  }

  /// Applies [ops] to the stored model, so concurrent changes the ops don't
  /// touch survive; refuses when the outcome differs from [result].
  @override
  Future<ModelSummary> save(LoadedModel at, List<Op> ops, Model result) async {
    final id = at.summary.id;
    if (readOnly.contains(id)) throw StateError('model "$id" is read-only');
    final stored = _models[id] ?? at.model;
    final (next, _) = apply(stored, ops);
    if (identical(stored, at.model) && next != result) throw StateError('the saved model differs from the edited one');
    _models[id] = next;
    return ModelSummary.of(id, next);
  }
}
