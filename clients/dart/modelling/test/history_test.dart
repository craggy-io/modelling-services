import 'package:modelling/modelling.dart';
import 'package:test/test.dart';

Model base() => Model(title: 'T', subject: 'S', nodes: [Node(id: 'a', label: 'A'), Node(id: 'b', label: 'B')]);

Op setLabel(String id, String label) => Op.nodeSet(id, {'label': label});

void main() {
  test('undo and redo walk the steps', () {
    final h = EditHistory(base());
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
    h.apply([Op.nodeAdd(Node(id: 'c', label: 'C'))]);
    h.apply([Op.nodeRemove('a')]);
    expect(h.model.nodes.map((n) => n.id), ['b', 'c']);
    expect(h.undo().nodes.map((n) => n.id), ['a', 'b', 'c']);
    expect(h.undo(), base());
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isTrue);
    expect(h.redo().nodes.map((n) => n.id), ['a', 'b', 'c']);
    expect(h.redo().nodes.map((n) => n.id), ['b', 'c']);
    expect(h.canRedo, isFalse);
    expect(() => h.redo(), throwsStateError);
  });

  test('a new step clears redo', () {
    final h = EditHistory(base());
    h.apply([Op.nodeRemove('a')]);
    h.undo();
    h.apply([Op.nodeRemove('b')]);
    expect(h.canRedo, isFalse);
    expect(h.model.nodes.map((n) => n.id), ['a']);
  });

  test('a failed apply records nothing', () {
    final h = EditHistory(base());
    expect(() => h.apply([Op.nodeRemove('nope')]), throwsA(isA<EditException>()));
    expect(() => h.apply([setLabel('a', ' ')]),
        throwsA(isA<EditException>().having((e) => e.index, 'index', -1).having((e) => e.code, 'code', 'label.empty')));
    expect(h.canUndo, isFalse);
    expect(h.model, base());
  });

  test('typing on one field of one element merges into one step', () {
    final h = EditHistory(base());
    for (final label in ['X', 'Xy', 'Xyz']) {
      h.apply([setLabel('a', label)]);
    }
    expect(h.steps, hasLength(1));
    expect(h.steps.single.ops.single.fields, {'label': 'Xyz'});
    expect(h.steps.single.inverse.single.fields, {'label': 'A'});
    expect(h.undo(), base());
  });

  test('typing does not merge across fields, elements, ops or when asked not to', () {
    final h = EditHistory(base());
    h.apply([setLabel('a', 'X')]);
    h.apply([
      Op.nodeSet('a', {'notes': 'n'})
    ]);
    h.apply([setLabel('b', 'Y')]);
    h.apply([setLabel('b', 'Yz')], merge: false);
    h.apply([
      Op.nodeSet('b', {'label': 'Q', 'notes': 'm'})
    ]);
    h.apply([
      Op.nodeSet('b', {'label': 'R', 'notes': 'o'})
    ]);
    expect(h.steps, hasLength(6));
  });

  test('edge.set typing merges too', () {
    final m = base().copyWith(edges: [Edge(id: 'e', from: 'a', to: 'b', label: 'u')]);
    final h = EditHistory(m);
    h.apply([
      Op.edgeSet('e', {'label': 'us'})
    ]);
    h.apply([
      Op.edgeSet('e', {'label': 'use'})
    ]);
    expect(h.steps, hasLength(1));
    expect(h.undo(), m);
  });

  test('pending ops are the ops since the last save', () {
    final h = EditHistory(base());
    expect(h.pendingOps, isEmpty);
    h.apply([Op.nodeAdd(Node(id: 'c', label: 'C'))]);
    h.markSaved();
    expect(h.pendingOps, isEmpty);
    expect(h.isDirty, isFalse);
    final saved = h.model;
    h.apply([Op.nodeRemove('a')]);
    h.apply([Op.nodeAdd(Node(id: 'd', label: 'D'))]);
    h.undo(); // undone unsaved steps are dropped
    expect(h.pendingOps.map((o) => o.toJson()), [Op.nodeRemove('a').toJson()]);
    expect(apply(saved, h.pendingOps).$1, h.model);
  });

  test('pending ops undo saved steps that were undone', () {
    final h = EditHistory(base());
    h.apply([setLabel('a', 'X')]);
    h.apply([Op.nodeRemove('b')]);
    h.markSaved();
    final saved = h.model;
    h.undo();
    h.undo();
    h.apply([Op.nodeAdd(Node(id: 'z', label: 'Z'))]);
    expect(apply(saved, h.pendingOps).$1, h.model);
    expect(h.pendingOps.first.op, Ops.nodeAdd); // re-adds b first
  });

  test('saved steps are not merged into', () {
    final h = EditHistory(base());
    h.apply([setLabel('a', 'X')]);
    h.markSaved();
    final saved = h.model;
    h.apply([setLabel('a', 'Xy')]);
    expect(h.steps, hasLength(2));
    expect(h.pendingOps.map((o) => o.toJson()), [setLabel('a', 'Xy').toJson()]);
    expect(apply(saved, h.pendingOps).$1, h.model);
  });

  test('undo then redo back to the save is clean', () {
    final h = EditHistory(base());
    h.apply([setLabel('a', 'X')]);
    h.markSaved();
    h.undo();
    expect(h.isDirty, isTrue);
    h.redo();
    expect(h.isDirty, isFalse);
  });
}
