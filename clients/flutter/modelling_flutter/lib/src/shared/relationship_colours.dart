// relationship_colours.dart: one palette slot per relationship, shared by
// every renderer so a relationship keeps its colour everywhere (theme.md
// §5.17, §3.4 categorical palette applied in order).

import 'package:modelling/modelling.dart' hide View;

/// Palette slots by edge id, for [edges] (current and removed together).
///
/// Slots go in edge-id order. When [profile] declares edge kinds, edges of
/// one kind share a slot (in the order the kind is first met); edges
/// without a kind still get their own.
Map<String, int> relationshipSlots(Iterable<Edge> edges, {Profile? profile}) {
  final byKind = profile != null && profile.edgeKinds.isNotEmpty;
  final sorted = [...edges]..sort((a, b) => a.id.compareTo(b.id));
  final keys = <String, int>{};
  return {
    for (final e in sorted)
      e.id: keys.putIfAbsent(byKind && e.kind.isNotEmpty ? 'kind:${e.kind}' : 'id:${e.id}', () => keys.length),
  };
}
