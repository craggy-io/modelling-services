import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

import 'fixture.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final Model _base = Model.decode(appJson);
  late final MemoryModelSource _source = MemoryModelSource({'app': _revision(_base)}, {'app': _base});
  ModelController? _controller;
  LoadedModel? _loaded;

  /// A revision of the fixture, so the workspace shows diff mode.
  static Model _revision(Model base) => apply(base, [
    Op.nodeSet('ui', {'label': 'Screens'}),
    Op.nodeAdd(Node(id: 'cache', label: 'Response cache', parent: 'net', kind: 'class')),
  ]).$1;

  @override
  void initState() {
    super.initState();
    _source.read('app').then((loaded) {
      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _controller = ModelController(loaded.model, base: loaded.base, profile: Profile.decode(profileJson))
          ..overlays = const [
            ModelOverlay(
              id: 'findings',
              label: 'Open findings',
              legend: {'High': Color(0xFFFF6B6B), 'Low': Color(0xFFFFC857)},
              marks: {
                'net': OverlayMark(badge: '2 high', color: Color(0xFFFF6B6B), value: 0.8),
                'ui': OverlayMark(badge: '1 low', color: Color(0xFFFFC857), value: 0.2),
              },
            ),
          ];
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return MaterialApp(
      title: 'modelling_flutter',
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Builder(
        builder: (context) => ModelThemeScope(
          theme: ModelTheme.fallback(Theme.of(context).brightness),
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: c == null
                    ? const Center(child: CircularProgressIndicator())
                    : ModelWorkspace(
                        controller: c,
                        renderers: const [
                          BlocksRenderer(),
                          OutlineRenderer(),
                          GraphRenderer(),
                          MatrixRenderer(),
                          TableRenderer(),
                        ],
                        onSave: (ops, result) async {
                          await _source.save(_loaded!, ops, result);
                        },
                        onEvidence: (ref) => c.notice.value = 'Would open ${ref.scheme}:${ref.id}',
                        onOpenLink: (link) => c.notice.value = 'Would open model ${link.model}',
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
