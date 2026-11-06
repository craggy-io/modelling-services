// samples.dart: what the app bundles: templates, profiles, and the
// gallery's diff and overlay samples built from them.

import 'package:flutter/services.dart';
import 'package:modelling/modelling.dart' hide View;
import 'package:modelling_flutter/modelling_flutter.dart';

/// Every renderer the package ships, in switcher order; blocks on the grid.
const modellerRenderers = <ModelRenderer>[
  BlocksRenderer(grid: true),
  OutlineRenderer(),
  GraphRenderer(),
  MatrixRenderer(),
  TableRenderer(),
];

/// A bundled template.
class Template {
  const Template(this.id, this.title, this.asset);

  final String id;
  final String title;
  final String asset;
}

const modellerTemplates = [
  Template('app', 'Payment app (Android)', 'assets/templates/app.json'),
  Template('system-context', 'System context', 'assets/templates/system-context.json'),
];

const _profileAssets = ['assets/profiles/android-profile.json'];

/// The bundled models and profiles, loaded once at start.
class Bundled {
  const Bundled(this.templates, this.profiles);

  /// Template models by template id.
  final Map<String, Model> templates;
  final List<Profile> profiles;

  static Future<Bundled> load(AssetBundle bundle) async => Bundled(
    {for (final t in modellerTemplates) t.id: Model.decode(await bundle.loadString(t.asset))},
    [for (final a in _profileAssets) Profile.decode(await bundle.loadString(a))],
  );

  /// The bundled profile a model names, if any.
  Profile? profileFor(Model m) => profiles.where((p) => p.ref == m.profile).firstOrNull;
}

/// The diff sample: the payment app revised (a relabel, an addition, a
/// removal), to compare against the template.
Model revisedApp(Model base) => apply(base, [
  Op.nodeSet('ui', {'label': 'Screens'}),
  Op.nodeAdd(Node(id: 'cache', label: 'Response cache', parent: 'net', kind: 'class')),
  Op.nodeRemove('server', cascade: true),
]).$1;

/// The overlay sample: open findings per area.
const findingsOverlay = ModelOverlay(
  id: 'findings',
  label: 'Open findings',
  legend: {'High': Color(0xFFFF6B6B), 'Low': Color(0xFFFFC857)},
  marks: {
    'net': OverlayMark(badge: '2 high', color: Color(0xFFFF6B6B), value: 0.8),
    'ui': OverlayMark(badge: '1 low', color: Color(0xFFFFC857), value: 0.2),
  },
);
