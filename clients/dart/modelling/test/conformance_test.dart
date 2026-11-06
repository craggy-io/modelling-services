// The shared vectors in modelling-services/conformance, run exactly as the Go
// side runs them (conformance/conformance_test.go). Hand-written inputs are
// <area>.json; Go-generated expectations are expected/<area>.json. JSON is
// compared canonically.

import 'dart:convert';
import 'dart:io';

import 'package:modelling/modelling.dart';
import 'package:test/test.dart';

/// The conformance directory: the nearest ancestor of the working directory
/// with conformance/documents.json (the package root is clients/dart/modelling).
final Directory conformance = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    final candidate = Directory('${dir.path}${Platform.pathSeparator}conformance');
    if (File('${candidate.path}${Platform.pathSeparator}documents.json').existsSync()) return candidate;
    if (dir.parent.path == dir.path) throw StateError('no conformance/ directory above ${Directory.current.path}');
  }
}();

Object? readJson(String relative) => jsonDecode(File('${conformance.path}/$relative').readAsStringSync());

List<Map<String, Object?>> cases(String file, String list) =>
    [for (final c in (readJson(file) as Map)[list] as List) (c as Map).cast<String, Object?>()];

Map<String, Object?> expected(String area) => (readJson('expected/$area.json') as Map).cast<String, Object?>();

/// A field that may be "@fixture", "@mermaid:fixture" or "@outline:fixture"
/// (that fixture's export), or inline JSON.
Object? resolve(Object? raw) {
  if (raw is! String || !raw.startsWith('@')) return raw;
  final ref = raw.substring(1);
  final colon = ref.indexOf(':');
  if (colon >= 0) {
    final m = decode(resolve('@${ref.substring(colon + 1)}'));
    return switch (ref.substring(0, colon)) {
      'mermaid' => toMermaid(m),
      'outline' => toOutline(m),
      final f => throw StateError('unknown export $f'),
    };
  }
  return readJson('fixtures/$ref.json');
}

Model decode(Object? json) => Model.decode(json!);

/// Canonical JSON of a value (with model types converted by their toJson).
String canonical(Object? v) => canonicalJson(jsonDecode(jsonEncode(v)));

void expectJson(Object? got, Object? want, [String? reason]) => expect(canonical(got), canonical(want), reason: reason);

void main() {
  group('documents', () {
    for (final c in cases('documents.json', 'cases')) {
      test(c['name'], () {
        var limits = const Limits();
        if (c['limits'] case final Map<String, Object?> l) {
          limits = Limits(
              maxDepth: (l['maxDepth'] ?? 0) as int,
              maxNodes: (l['maxNodes'] ?? 0) as int,
              maxRefs: (l['maxRefs'] ?? 0) as int,
              maxEdges: (l['maxEdges'] ?? 0) as int);
        }
        final source = (c['raw'] as String?) ?? resolve(c['document']);
        Model m;
        try {
          m = Model.decode(source!);
        } on ModelFormatException {
          expect(c['decodeError'], isTrue, reason: 'unexpected decode error');
          return;
        }
        expect(c['decodeError'] ?? false, isFalse, reason: 'decode succeeded, want an error');
        final codes = [for (final i in m.issues(limits)) i.code];
        expect(codes, c['issues']);
        if (c['encoded'] case final String enc) expect(m.encode(), enc);
        if (codes.isEmpty) {
          final again = Model.decode(m.encode());
          expect(again, m, reason: 'encode/decode round trip changed the model');
        }
      });
    }
  });

  group('migrate', () {
    for (final c in cases('migrate.json', 'cases')) {
      test(c['name'], () {
        final got = decode(c['v1']), want = decode(c['expected']);
        got.validate();
        expect(got.encode(), want.encode());
      });
    }
  });

  group('diff', () {
    final exp = expected('diff');
    for (final c in cases('diff.json', 'cases')) {
      test(c['name'], () {
        final cs = compare(decode(resolve(c['base'])), decode(resolve(c['revision'])), views: c['views'] == true);
        if (c.containsKey('changes')) expectJson(cs.toJson(), c['changes'], 'inline changes');
        expectJson(cs.toJson(), exp[c['name']], 'expected/diff.json');
      });
    }
  });

  group('edit', () {
    final exp = expected('edit');
    for (final c in cases('edit.json', 'cases')) {
      test(c['name'], () {
        final m = decode(resolve(c['model']));
        final ops = [for (final o in c['ops'] as List) Op.fromJson(o)];
        final want = exp[c['name']] as Map;
        if (c['error'] case final Object wantErr) {
          try {
            apply(m, ops);
          } on EditException catch (e) {
            final got = {'index': e.index, 'code': e.code};
            expectJson(got, wantErr);
            expectJson({'error': got}, want);
            return;
          }
          fail('applied, want error $wantErr');
        }
        final (result, inverse) = apply(m, ops);
        final (back, _) = apply(result, inverse);
        expect(back.encode(), m.encode(), reason: 'inverse did not restore the model');
        expectJson(jsonDecode(result.encode()), want['result'], 'result');
        expectJson([for (final o in inverse) o.toJson()], want['inverse'], 'inverse');
        // The inverse also survives a JSON round trip.
        final reread = [for (final o in inverse) Op.fromJson(jsonDecode(jsonEncode(o.toJson())))];
        expect(apply(result, reread).$1.encode(), m.encode());
      });
    }
  });

  group('query', () {
    final exp = expected('query');
    for (final c in cases('query.json', 'cases')) {
      test(c['name'], () {
        final ix = decode(resolve(c['model'])).index;
        final a = (c['args'] as Map).cast<String, Object?>();
        String str(String k) => (a[k] ?? '') as String;
        int number(String k) => (a[k] ?? 0) as int;
        final Object got = switch (c['fn']) {
          'search' => search(ix, Filter.fromJson(a['filter'])),
          'neighbours' => neighbours(ix, str('id'), Direction.parse(str('direction')), number('depth')),
          'paths' => paths(ix, str('from'), str('to'), number('maxLen'), number('maxPaths')),
          'impact' => impact(ix, str('id')),
          'descendants' => ix.descendants(str('id')),
          'ancestors' => ix.ancestors(str('id')),
          final fn => throw StateError('unknown fn $fn'),
        };
        expectJson(got, exp[c['name']]);
      });
    }
  });

  group('lint', () {
    final exp = expected('lint');
    for (final c in cases('lint.json', 'cases')) {
      test(c['name'], () {
        final ix = decode(resolve(c['model'])).index;
        final profile = c.containsKey('profile') ? Profile.decode(resolve(c['profile'])!) : null;
        final got = [
          for (final f in lint(ix, profile)) {'rule': f.rule, 'element': f.element, 'severity': f.severity.wire},
        ];
        expectJson(got, exp[c['name']]);
      });
    }
  });

  group('export', () {
    final exp = expected('export');
    for (final c in cases('export.json', 'export')) {
      test(c['name'], () {
        final m = decode(resolve(c['model']));
        final want = exp['export: ${c['name']}'] as Map;
        expect(toMermaid(m), want['mermaid']);
        expect(toOutline(m), want['outline']);
      });
    }
    for (final c in cases('export.json', 'import')) {
      test('import: ${c['name']}', () {
        final src = resolve(c['source']) as String;
        final parse = c['format'] == 'mermaid' ? parseMermaid : parseOutline;
        final want = exp['import: ${c['name']}'];
        Model m;
        try {
          m = parse(src);
        } on ModelFormatException {
          expect(c['error'], isTrue, reason: 'unexpected parse error');
          expectJson({'error': true}, want);
          return;
        }
        expect(c['error'] ?? false, isFalse, reason: 'parsed, want an error');
        m.validate();
        expectJson(jsonDecode(m.encode()), want);
      });
    }
  });
}
