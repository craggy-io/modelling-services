import 'package:flutter_test/flutter_test.dart';
import 'package:modelling/modelling.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'support/fixtures.dart';

void main() {
  group('replace', () {
    test('keeps view state for ids that still exist', () {
      final c = ModelController(appModel());
      c.select(const ModelElementRef.node('net'));
      c.toggleFolded('ui', folded: false);
      c.toggleFolded('pinner', folded: true);
      c.search = 'layer';
      c.drillIn('app');
      c.togglePin('e1');
      c.togglePin('e2');
      c.focus('ui');

      c.replace(appModel().copyWith(title: 'Payment app v2'));

      expect(c.model.title, 'Payment app v2');
      expect(c.selection, const ModelElementRef.node('net'));
      expect(c.trail, ['app']);
      expect(c.collapsed, contains('ui'));
      expect(c.expanded, contains('pinner'));
      expect(c.search, 'layer');
      expect(c.pinned, {'e1', 'e2'});
      expect(c.focused, 'ui');
    });

    test('drops view state for ids that are gone', () {
      final c = ModelController(appModel());
      c.select(const ModelElementRef.node('server'));
      c.drillIn('app');
      c.drillIn('net');
      c.toggleFolded('net', folded: false);
      c.togglePin('e2');
      final (next, _) = apply(appModel(), [
        Op.nodeRemove('net', cascade: true),
        Op.nodeRemove('server', cascade: true),
      ]);

      c.replace(next);

      expect(c.selection, isNull);
      expect(c.trail, ['app']);
      expect(c.collapsed, isEmpty);
      expect(c.pinned, isEmpty);
    });

    test('starts a fresh history and can set a base', () {
      final c = ModelController(appModel());
      c.apply([
        Op.nodeSet('ui', {'label': 'UI'}),
      ]);
      expect(c.dirty, isTrue);
      c.replace(appRevision(), base: appModel());
      expect(c.dirty, isFalse);
      expect(c.canUndo, isFalse);
      expect(c.diff.count, 4); // cache added, server removed, ui changed, e2 removed
    });
  });

  group('history', () {
    test('undo, redo, pendingOps and markSaved', () {
      final c = ModelController(appModel());
      var notified = 0;
      c.addListener(() => notified++);
      c.apply([
        Op.nodeSet('ui', {'label': 'U'}),
      ]);
      c.apply([
        Op.nodeSet('ui', {'label': 'UI'}),
      ]); // merges with the previous step
      c.apply([Op.nodeAdd(Node(id: 'x', label: 'X'))]);
      expect(c.history.steps, hasLength(2));
      expect(c.pendingOps.map((o) => o.op), ['node.set', 'node.add']);
      expect(notified, 3);

      c.undo();
      expect(c.model.nodeById('x'), isNull);
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.model.nodeById('x'), isNotNull);

      c.markSaved();
      expect(c.dirty, isFalse);
      expect(c.pendingOps, isEmpty);
      c.undo();
      expect(c.dirty, isTrue);
      expect(c.pendingOps.single.op, 'node.remove');
    });

    test('tryApply reports a refused edit through notice', () {
      final c = ModelController(appModel());
      expect(
        c.tryApply([
          Op.nodeSet('ui', {'label': ''}),
        ]),
        isFalse,
      );
      expect(c.notice.value, isNotNull);
      expect(c.model, appModel());
    });

    test('undo prunes view state for removed elements', () {
      final c = ModelController(appModel());
      c.apply([Op.nodeAdd(Node(id: 'x', label: 'X'))]);
      c.select(const ModelElementRef.node('x'));
      c.undo();
      expect(c.selection, isNull);
    });
  });

  group('views', () {
    test('saveView writes a view.put op and applyView restores it', () {
      final c = ModelController(appModel());
      c.renderer = 'outline';
      c.toggleFolded('net', folded: false);
      c.filter = Filter(kinds: ['component']);
      c.drillIn('app');
      c.saveView('mine', title: 'Mine');

      final v = c.model.views.firstWhere((v) => v.id == 'mine');
      expect(v.renderer, 'outline');
      expect(v.root, 'app');
      expect(v.collapsed, ['net']);
      expect(v.filter!.kinds, ['component']);
      expect(c.pendingOps.single.op, 'view.put');
      expect(c.activeView, 'mine');

      c.applyView(c.model.views.firstWhere((v) => v.id == 'overview'));
      expect(c.renderer, 'blocks');
      expect(c.trail, isEmpty);
      expect(c.collapsed, {'net'});
      expect(c.filter.kinds, isEmpty);
      c.applyView(v);
      expect(c.renderer, 'outline');
      expect(c.trail, ['app']);
    });
  });

  group('diff and visibility', () {
    test('changes, ghosts and changed-only', () {
      final c = ModelController(appRevision(), base: appModel());
      expect(c.diff.nodeChange('cache'), ChangeKind.added);
      expect(c.diff.nodeChange('ui'), ChangeKind.changed);
      expect(c.diff.removedNodes.keys, ['server']);
      expect(c.diff.removedEdges.keys, ['e2']);
      expect(c.diff.ghostsIn(''), ['server']);
      expect(c.labelOf('server'), 'Payment server');

      c.changedOnly = true;
      expect(c.visibility.included, {'app', 'ui', 'net', 'cache'});
      c.base = null;
      expect(c.changedOnly, isFalse);
      expect(c.visibility.included, hasLength(6));
    });

    test('search keeps matches and their contents, not their parents', () {
      final c = ModelController(appModel());
      c.search = 'network';
      expect(c.visibility.roots, ['net']);
      expect(c.visibility.included, {'net', 'pinner'});
    });

    test('relationship colours go in edge-id order, by kind with a profile', () {
      final c = ModelController(appModel());
      expect(
        [
          for (final e in ['e1', 'e2', 'e3', 'e4']) c.slotOf(e),
        ],
        [0, 1, 2, 3],
      );
      c.profile = androidProfile();
      expect(
        [
          for (final e in ['e1', 'e2', 'e3', 'e4']) c.slotOf(e),
        ],
        [0, 0, 1, 2],
      );
    });

    test('lint follows the profile', () {
      final c = ModelController(appModel(), profile: androidProfile());
      expect(c.lintFor('server').map((f) => f.rule), contains('profile.kind-required'));
    });
  });

  group('editing intents', () {
    test('reparent refuses cycles and profile violations with a reason', () {
      final c = ModelController(appModel(), profile: androidProfile());
      expect(c.reparentRefusal('app', 'pinner'), contains('is inside Application'));
      expect(c.reparentRefusal('net', 'net'), 'An area cannot contain itself.');
      expect(c.reparentRefusal('pinner', 'app'), 'An Application cannot contain a Class.');
      expect(c.reparent('app', 'ui'), isFalse);
      expect(c.notice.value, contains('cannot move into it'));
      expect(c.reparent('pinner', 'ui'), isTrue);
      expect(c.model.nodeById('pinner')!.parent, 'ui');
    });

    test('indent, outdent and reorder', () {
      final c = ModelController(appModel());
      expect(c.indent('net'), isTrue);
      expect(c.index.parent('net'), 'ui');
      expect(c.outdent('net'), isTrue);
      expect(c.index.parent('net'), 'app');
      expect(c.index.children('app'), ['ui', 'net']);
      expect(c.reorder('ui', up: false), isTrue);
      expect(c.index.children('app'), ['net', 'ui']);
      expect(c.reorder('ui', up: true), isTrue);
      expect(c.index.children('app'), ['ui', 'net']);
    });

    test('add, rename, delete and relationships', () {
      final c = ModelController(appModel());
      final a = c.addChild('net')!;
      expect(c.index.parent(a), 'net');
      expect(c.selection, ModelElementRef.node(a));
      final b = c.addSibling('ui')!;
      expect(c.index.children('app'), ['ui', b, 'net']);
      expect(c.rename(ModelElementRef.node(b), '  Store '), isTrue);
      expect(c.labelOf(b), 'Store');
      expect(c.removalOf('net'), (2, 3));
      expect(c.deleteNode('net'), isTrue);
      expect(c.model.nodeById('pinner'), isNull);
      final e = c.addRelationship('ui', b, label: 'writes')!;
      expect(c.model.edgeById(e)!.to, b);
      expect(c.newEdgeId(), isNot(e));
    });
  });

  group('positions and profile', () {
    test('setPositions writes the active view; saveView keeps them', () {
      final c = ModelController(appModel());
      expect(c.positions, isEmpty);
      expect(c.setPositions({'net': (10, 20)}), isTrue);
      expect(c.activeView, 'layout');
      expect(c.positions, {'net': (10.0, 20.0)});
      c.saveView('layout', title: 'Layout');
      expect(c.model.views.last.positions, {'net': (10.0, 20.0)});
      c.setPositions(const {}, replace: true);
      expect(c.positions, isEmpty);
      c.undo();
      c.undo();
      expect(c.positions, {'net': (10.0, 20.0)});
    });

    test('useProfile names the profile in the model, undoably', () {
      final m = appModel().copyWith(profile: '');
      final c = ModelController(m);
      final p = androidProfile();
      expect(c.useProfile(p), isTrue);
      expect(c.profile, p);
      expect(c.model.profile, 'craggy.profile/android-app@1');
      c.undo();
      expect(c.model.profile, '');
      expect(c.useProfile(null), isTrue);
      expect(c.profile, isNull);
    });
  });
}
