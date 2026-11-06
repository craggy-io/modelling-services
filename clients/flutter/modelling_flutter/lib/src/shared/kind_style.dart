// kind_style.dart: how a node kind looks in the editor: its label, an icon
// and an accent colour from the theme's palette. Profile kinds take palette
// colours in profile order; without a profile, a few generic kinds are
// offered by the palette and any other kind gets a stable colour.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../theme/model_theme.dart';

/// A node kind's label, icon and accent colour.
@immutable
class KindStyle {
  const KindStyle({required this.kind, required this.label, required this.icon, required this.colour});

  /// The kind id ('' for none).
  final String kind;
  final String label;
  final IconData icon;
  final Color colour;
}

/// The kinds offered when the model has no profile: (kind, label).
const genericKinds = [
  ('', 'Area'),
  ('group', 'Group'),
  ('component', 'Component'),
  ('service', 'Service'),
  ('datastore', 'Data store'),
  ('external', 'External'),
];

const _icons = <String, IconData>{
  '': Icons.crop_square_rounded,
  'app': Icons.apps_rounded,
  'application': Icons.apps_rounded,
  'system': Icons.hub_outlined,
  'group': Icons.folder_outlined,
  'component': Icons.widgets_outlined,
  'container': Icons.inventory_2_outlined,
  'class': Icons.data_object_rounded,
  'module': Icons.view_module_outlined,
  'service': Icons.dns_outlined,
  'api': Icons.api_rounded,
  'datastore': Icons.storage_rounded,
  'database': Icons.storage_rounded,
  'db': Icons.storage_rounded,
  'queue': Icons.view_stream_outlined,
  'external': Icons.public_rounded,
  'person': Icons.person_outline_rounded,
  'actor': Icons.person_outline_rounded,
  'user': Icons.person_outline_rounded,
  'device': Icons.devices_other_outlined,
  'library': Icons.local_library_outlined,
};

/// The kinds the palette offers for [profile]: its node kinds in order,
/// else [genericKinds].
List<(String, String)> paletteKinds(Profile? profile) => profile == null || profile.nodeKinds.isEmpty
    ? genericKinds
    : [for (final e in profile.nodeKinds.entries) (e.key, e.value.label)];

/// How [kind] looks under [profile] with [t]'s palette.
KindStyle kindStyle(ModelTheme t, Profile? profile, String kind) {
  final kinds = paletteKinds(profile);
  final at = kinds.indexWhere((k) => k.$1 == kind);
  final label = at >= 0 ? kinds[at].$2 : (kind.isEmpty ? 'Area' : _titleCase(kind));
  final icon = _icons[kind.toLowerCase()] ?? Icons.category_outlined;
  if (kind.isEmpty) return KindStyle(kind: kind, label: label, icon: icon, colour: t.muted);
  return KindStyle(kind: kind, label: label, icon: icon, colour: t.paletteAt(at >= 0 ? at : _stable(kind)));
}

int _stable(String s) => s.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x7fffffff);

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll(RegExp('[-_]'), ' ');

/// A rounded square with [style]'s icon on a tint of its colour.
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.style, this.size = 26});

  final KindStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: style.colour.withValues(alpha: 0.28), width: t.borderWidth),
      ),
      child: Icon(style.icon, size: size * 0.6, color: style.colour),
    );
  }
}
