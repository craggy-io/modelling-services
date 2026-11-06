// model_source.dart: where models come from and go back to (design §6.2).
// Hosts implement ModelSource over their own storage (labs: its client);
// the package ships memory and file sources.

import 'package:flutter/foundation.dart';
import 'package:modelling/modelling.dart';

/// What a source lists: enough to pick a model.
@immutable
class ModelSummary {
  const ModelSummary({required this.id, required this.title, this.subject = ''});

  /// A summary of [m] stored under [id].
  factory ModelSummary.of(String id, Model m) => ModelSummary(id: id, title: m.title, subject: m.subject);

  final String id;
  final String title;
  final String subject;

  @override
  bool operator ==(Object other) =>
      other is ModelSummary && other.id == id && other.title == title && other.subject == subject;

  @override
  int get hashCode => Object.hash(id, title, subject);
}

/// A model read from a source: whether it may be edited, and the base to
/// compare it with, if any.
@immutable
class LoadedModel {
  const LoadedModel({required this.model, required this.summary, this.editable = true, this.base});

  final Model model;
  final ModelSummary summary;
  final bool editable;
  final Model? base;
}

/// Lists, reads and saves models.
abstract interface class ModelSource {
  Future<List<ModelSummary>> list();

  /// Throws [StateError] when there is no model [id].
  Future<LoadedModel> read(String id);

  /// Stores [result] (the model [at] after [ops]) and returns its summary,
  /// whose id may differ from [at]'s (a save-as).
  Future<ModelSummary> save(LoadedModel at, List<Op> ops, Model result);
}
