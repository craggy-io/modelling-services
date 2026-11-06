// visibility.dart: which areas a renderer shows for the current search,
// filter and "Changed only" setting (the inclusion rules of today's board,
// shared so every renderer agrees).

import 'package:modelling/modelling.dart' hide View;

import 'model_diff.dart';

/// The areas to show and the top-level ones to start from.
class ModelVisibility {
  ModelVisibility._(this.included, this.roots, this.matched, this.queryActive, this._filter);

  /// Applies [text], [kinds] and [tags] (search) and [changedOnly] to the
  /// model behind [ix].
  ///
  /// - Changed only: the areas [diff] involves that match the search, with
  ///   their containing areas for context.
  /// - A search: the matching areas not inside another match, with all
  ///   their contents.
  /// - Otherwise: everything.
  factory ModelVisibility.compute(
    ModelIndex ix,
    ModelDiff diff, {
    String text = '',
    List<String> kinds = const [],
    List<String> tags = const [],
    bool changedOnly = false,
  }) {
    final model = ix.model;
    final filter = Filter(text: text, kinds: kinds, tags: tags);
    final active = text.trim().isNotEmpty || kinds.isNotEmpty || tags.isNotEmpty;
    final matched = active ? search(ix, filter).toSet() : {for (final n in model.nodes) n.id};
    final included = <String>{};
    List<String> roots;
    if (changedOnly && !diff.isEmpty) {
      for (final id in diff.involved) {
        if (!matched.contains(id)) continue;
        for (var p = id; ix.node(p) != null; p = ix.parent(p)) {
          if (!included.add(p)) break;
        }
      }
      roots = [
        for (final n in model.nodes)
          if (included.contains(n.id) && !included.contains(ix.parent(n.id))) n.id,
      ];
    } else if (!active) {
      included.addAll(matched);
      roots = ix.children('');
    } else {
      bool underMatch(String id) => ix.ancestors(id).any(matched.contains);
      roots = [
        for (final n in model.nodes)
          if (matched.contains(n.id) && !underMatch(n.id)) n.id,
      ];
      final pending = [...roots];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (included.add(id)) pending.addAll(ix.children(id));
      }
    }
    return ModelVisibility._(included, roots, matched, active, filter);
  }

  /// Areas to draw.
  final Set<String> included;

  /// Included areas whose parent is not included, in document order.
  final List<String> roots;

  /// Areas that match the search (every area when there is none).
  final Set<String> matched;

  /// Whether a search or kind/tag filter is narrowing the model.
  final bool queryActive;
  final Filter _filter;

  /// Whether a removed (ghost) area matches the search.
  bool ghostMatches(Node n) {
    if (!queryActive) return true;
    final text = _filter.text.trim().toLowerCase();
    return (_filter.kinds.isEmpty || _filter.kinds.contains(n.kind)) &&
        (_filter.tags.isEmpty || _filter.tags.any(n.tags.contains)) &&
        (text.isEmpty || haystack(n).contains(text));
  }
}
