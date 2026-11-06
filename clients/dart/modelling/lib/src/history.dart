// history.dart: undo, redo, typing merge and the pending op list a host
// sends on save (design §6.1).

import 'apply.dart' as edit;
import 'model.dart';
import 'op.dart';
import 'validate.dart';

/// One applied change: the operations and the inverse that undoes them.
class EditStep {
  EditStep(List<Op> ops, List<Op> inverse)
      : ops = List.unmodifiable(ops),
        inverse = List.unmodifiable(inverse);

  final List<Op> ops;
  final List<Op> inverse;
}

/// The edit history of one model: [apply] records a step, [undo] and [redo]
/// move through them, and [pendingOps] is what changed since [markSaved].
///
/// Consecutive node.set or edge.set steps that set the same single field of
/// the same element (typing) merge into one step, unless the earlier step has
/// been saved.
class EditHistory {
  EditHistory(Model model, {this.limits = const Limits()})
      : _model = model,
        _saved = const [];

  /// The limits every apply validates against.
  final Limits limits;

  Model _model;
  final _done = <EditStep>[];
  final _undone = <EditStep>[];
  List<EditStep> _saved;

  /// The current model.
  Model get model => _model;

  bool get canUndo => _done.isNotEmpty;
  bool get canRedo => _undone.isNotEmpty;

  /// The steps that [undo] would undo, oldest first.
  List<EditStep> get steps => List.unmodifiable(_done);

  /// Applies [ops] to the current model, records the step and clears redo.
  /// Throws [EditException] (and records nothing) when they fail. Set
  /// [merge] false to keep this step separate from a typing run.
  Model apply(List<Op> ops, {bool merge = true}) {
    if (ops.isEmpty) return _model;
    final (result, inverse) = _apply(_model, ops);
    final last = _done.isEmpty ? null : _done.last;
    if (merge && last != null && !_saved.contains(last) && _typing(last.ops, ops)) {
      _done[_done.length - 1] = EditStep(ops, last.inverse);
    } else {
      _done.add(EditStep(ops, inverse));
    }
    _undone.clear();
    return _model = result;
  }

  /// Undoes the last step and returns the model.
  Model undo() {
    if (_done.isEmpty) throw StateError('nothing to undo');
    final step = _done.last;
    _model = _apply(_model, step.inverse).$1;
    _undone.add(_done.removeLast());
    return _model;
  }

  /// Redoes the last undone step and returns the model.
  Model redo() {
    if (_undone.isEmpty) throw StateError('nothing to redo');
    final step = _undone.last;
    _model = _apply(_model, step.ops).$1;
    _done.add(_undone.removeLast());
    return _model;
  }

  /// Marks the current model as saved: [pendingOps] becomes empty.
  void markSaved() => _saved = List.unmodifiable(_done);

  /// Whether the model differs (by history) from the last save.
  bool get isDirty => pendingOps.isNotEmpty;

  /// The operations that take the saved model to the current one: inverses
  /// of saved steps since undone (latest first), then the steps applied
  /// since. Undone unsaved steps are not included.
  List<Op> get pendingOps {
    var common = 0;
    while (common < _saved.length && common < _done.length && identical(_saved[common], _done[common])) {
      common++;
    }
    return List.unmodifiable([
      for (var i = _saved.length - 1; i >= common; i--) ..._saved[i].inverse,
      for (var i = common; i < _done.length; i++) ..._done[i].ops,
    ]);
  }

  (Model, List<Op>) _apply(Model m, List<Op> ops) => edit.apply(m, ops, limits);
}

/// Whether [next] continues [prev] as typing: both a single node.set or
/// edge.set of the same one field on the same element.
bool _typing(List<Op> prev, List<Op> next) {
  if (prev.length != 1 || next.length != 1) return false;
  final a = prev.single, b = next.single;
  return (a.op == Ops.nodeSet || a.op == Ops.edgeSet) &&
      a.op == b.op &&
      a.id == b.id &&
      a.fields.length == 1 &&
      b.fields.length == 1 &&
      a.fields.keys.single == b.fields.keys.single;
}
