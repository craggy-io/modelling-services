// Behaviour the conformance vectors don't pin. Expected values were checked
// against the Go implementation.

import 'dart:convert';

import 'package:modelling/modelling.dart';
import 'package:test/test.dart';

const doc = '{"format":"craggy.model","version":2,"title":"T","subject":"S"';

void main() {
  group('canonical JSON', () {
    test('numbers are exact decimals', () {
      final cases = <num, String>{
        0: '0',
        -0.0: '0',
        1.0: '1',
        1e3: '1000',
        2.5: '2.5',
        1e21: '1000000000000000000000',
        1.5e-7: '0.00000015',
        123456789012345678: '123456789012345680',
        1e15 + 0.3: '1000000000000000.2',
      };
      cases.forEach((n, want) => expect(canonicalJson(n), want, reason: '$n'));
    });

    test('strings escape as Go encoding/json', () {
      expect(canonicalJson('a"\\\n\r\t\b\f\x01<>&\u2028\u2029é😀'),
          r'"a\"\\\n\r\t\b\f\u0001\u003c\u003e\u0026\u2028\u2029' 'é\u{1F600}"');
      expect(canonicalJson('\ud800'), '"\ufffd"');
    });

    test('keys sort by UTF-8 bytes', () {
      expect(canonicalJson({'￿': 1, '😀': 2, 'b': 3, 'B': 4, 'é': 5}), '{"B":4,"b":3,"é":5,"￿":1,"😀":2}');
    });
  });

  group('decode', () {
    test('unknown fields are refused at every level', () {
      expect(() => Model.decode('$doc,"nodes":[{"id":"a","label":"A","link":{"model":"m","x":1}}]}'),
          throwsA(isA<ModelFormatException>()));
      expect(() => Model.decode('$doc,"views":[{"id":"v","renderer":"r","filter":{"nope":true}}]}'),
          throwsA(isA<ModelFormatException>()));
    });

    test('null leaves a field at its zero value, as in Go', () {
      final m = Model.decode('$doc,"notes":null,"nodes":[null],"edges":null}');
      expect(m.notes, '');
      expect(m.nodes.single.id, '');
      expect(m.issues().map((i) => i.code), ['id.invalid', 'label.empty']);
    });

    test('type mismatches and non-integer versions are refused', () {
      expect(() => Model.decode('{"format":"craggy.model","version":2,"title":3,"subject":"S"}'),
          throwsA(isA<ModelFormatException>()));
      expect(() => Model.decode('{"version":2.5}'), throwsA(isA<ModelFormatException>()));
      expect(() => Model.decode('[]'), throwsA(isA<ModelFormatException>()));
    });

    test('a decoded map decodes like its text', () {
      final text = '$doc,"nodes":[{"id":"a","label":"A"}]}';
      expect(Model.decode(jsonDecode(text) as Map), Model.decode(text));
    });

    test('empty evidence ids and view titles are omitted', () {
      final e = Evidence(caption: 'c', ref: Ref(scheme: 'url', id: 'u'));
      expect(e.toJson(), {
        'caption': 'c',
        'ref': {'scheme': 'url', 'id': 'u'}
      });
      expect(View(id: 'v', renderer: 'graph').toJson(), {'id': 'v', 'renderer': 'graph'});
      expect(
          View(id: 'v', renderer: 'graph', filter: Filter()).toJson(), {'id': 'v', 'renderer': 'graph', 'filter': {}});
    });

    test('positions read as Go [2]float64', () {
      final m = Model.decode('$doc,"views":[{"id":"v","renderer":"graph","positions":{"a":[1,2,3],"b":[4]}}]}');
      expect(m.views.single.positions, {'a': (1.0, 2.0), 'b': (4.0, 0.0)});
      expect(m.encode(), contains('"positions":{"a":[1,2],"b":[4,0]}'));
    });
  });

  group('values', () {
    test('equality is by value', () {
      expect(Node(id: 'a', label: 'A', properties: {'n': 1}), Node(id: 'a', label: 'A', properties: {'n': 1.0}));
      expect(Model.empty('T', 'S'), Model.decode('$doc}'));
      expect(Model.empty('T', 'S').hashCode, Model.decode('$doc}').hashCode);
    });

    test('copyWith clears links and filters only when asked', () {
      final n = Node(id: 'a', label: 'A', link: const Link(model: 'm'));
      expect(n.copyWith(label: 'B').link, const Link(model: 'm'));
      expect(n.copyWith(clearLink: true).link, isNull);
      final v = View(id: 'v', renderer: 'r', filter: Filter(text: 'x'));
      expect(v.copyWith(clearFilter: true).filter, isNull);
    });

    test('collections are unmodifiable', () {
      final n = Node(id: 'a', label: 'A', tags: ['x']);
      expect(() => n.tags.add('y'), throwsUnsupportedError);
    });

    test('validate throws every issue', () {
      expect(
          () => Model(title: '', subject: '').validate(),
          throwsA(isA<ModelValidationException>()
              .having((e) => e.issues.map((i) => i.code), 'codes', ['title', 'subject'])));
    });

    test('limits tighten the defaults', () {
      final m = Model(title: 'T', subject: 'S', nodes: [
        Node(id: 'a', label: 'A', properties: {'s': 'xxxx', 'n': 1, 'b': true})
      ]);
      expect(m.issues(const Limits(maxProperties: 2, maxValueBytes: 3)).map((i) => i.code),
          ['bounds.properties', 'property.value']);
      expect(m.issues(const Limits(maxBytes: 10)).map((i) => i.code), ['size']);
    });
  });

  group('ops', () {
    test('JSON round trip keeps Go field rules', () {
      final op = Op.nodeMove('a', index: 0);
      expect(op.toJson(), {'op': 'node.move', 'id': 'a', 'index': 0});
      expect(Op.fromJson(op.toJson()), op);
      final set = Op.nodeSet('a', {
        'link': const Link(model: 'm'),
        'notes': null,
        'tags': ['x']
      });
      expect(set.toJson(), {
        'op': 'node.set',
        'id': 'a',
        'fields': {
          'link': {'model': 'm'},
          'notes': null,
          'tags': ['x']
        }
      });
      expect(Op.propSet('node', 'a', 'k', false).toJson()['value'], false);
    });

    test('bad set values are refused with op.field', () {
      final m = Model(title: 'T', subject: 'S', nodes: [Node(id: 'a', label: 'A')]);
      expect(
          () => apply(m, [
                Op.nodeSet('a', {'label': 3})
              ]),
          throwsA(isA<EditException>().having((e) => e.code, 'code', 'op.field')));
    });

    test('apply never changes its input', () {
      final m = Model(title: 'T', subject: 'S', nodes: [Node(id: 'a', label: 'A')]);
      final before = m.encode();
      apply(m, [Op.nodeAdd(Node(id: 'b', label: 'B')), Op.propSet('node', 'a', 'k', 1)]);
      expect(m.encode(), before);
    });
  });

  group('query', () {
    test('haystack prints values as Go fmt.Sprint', () {
      final n = Node(id: 'a', label: 'A', properties: {'a': 3, 'b': 2.5, 'c': true, 'd': 1e6, 'e': 0.00001});
      expect(haystack(n), 'a\na\n\n3\n2.5\ntrue\n1e+06\n1e-05');
    });

    test('unknown directions follow both ways', () {
      expect(Direction.parse('out'), Direction.outgoing);
      expect(Direction.parse('in'), Direction.incoming);
      expect(Direction.parse(''), Direction.both);
    });

    test('index answers structure', () {
      final m = Model(title: 'T', subject: 'S', nodes: [
        Node(id: 'a', label: 'A'),
        Node(id: 'b', label: 'B', parent: 'a'),
        Node(id: 'c', label: 'C', parent: 'gone'),
      ], edges: [
        Edge(id: 'e', from: 'b', to: 'b', label: 'self'),
      ]);
      final ix = m.index;
      expect(ix.children(''), ['a', 'c']);
      expect(ix.parent('c'), '');
      expect(ix.depth('b'), 2);
      expect(ix.touching('b'), ['e']);
      expect(ix.nodeIndex('c'), 2);
      expect(ix.edgeIndex('x'), -1);
    });
  });

  group('export', () {
    test('slug', () {
      expect(slug('Hello, World!'), 'hello-world');
      expect(slug('***'), 'node');
      expect(slug('Ünïcode 2'), 'n-code-2');
      expect(slug('x' * 70), 'x' * 64);
    });

    test('parse errors name the line', () {
      expect(() => parseMermaid('flowchart LR\n  a ==|x b\n'),
          throwsA(isA<ModelFormatException>().having((e) => e.message, 'message', contains('line 2'))));
      expect(() => parseOutline('# T\n\n- a\n    - b\n'),
          throwsA(isA<ModelFormatException>().having((e) => e.message, 'message', contains('line 4'))));
    });

    test('RE2 \\s is ASCII: a no-break space is not whitespace', () {
      expect(() => parseMermaid('flowchart LR\n  A -->B\n'), throwsA(isA<ModelFormatException>()));
    });
  });
}
