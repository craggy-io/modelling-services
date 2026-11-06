// model_controller.dart: one controller per open model, shared by every
// renderer, the inspector and the workspace (design §7.1). Renderers read
// it and send intents to it; they hold no model state of their own, so
// switching renderer keeps the user's place.

import 'package:flutter/foundation.dart';
import 'package:modelling/modelling.dart';
import 'package:modelling/modelling.dart' as modelling show lint;

import '../shared/model_diff.dart';
import '../shared/relationship_colours.dart';
import '../shared/visibility.dart';
import 'model_types.dart';

/// The open model, its edit history, its diff against a base, and the
/// view state (selection, trail, collapsed areas, search, pins) kept by id.
class ModelController extends ChangeNotifier {
  ModelController(
    Model model, {
    Model? base,
    Profile? profile,
    bool readOnly = false,
    this.limits = const Limits(),
    String renderer = 'blocks',
    bool saved = true,
  }) : _history = EditHistory(model, limits: limits, saved: saved),
       _base = base,
       _profile = profile,
       _readOnly = readOnly,
       _renderer = renderer;

  final Limits limits;
  EditHistory _history;
  Model? _base;
  Profile? _profile;
  bool _readOnly;

  /// The relationship the pointer is over (an edge id), for connector
  /// previews. Separate from [notifyListeners] so hovering never rebuilds.
  final hovered = ValueNotifier<String?>(null);

  /// The last refused gesture or failed edit, for the workspace to show.
  final notice = ValueNotifier<String?>(null);

  /// An area a renderer should start renaming in place (set by
  /// [ModelEditing.addArea]); the renderer that handles it clears it.
  final renameRequest = ValueNotifier<String?>(null);

  // ---- Model, base, history ----

  Model get model => _history.model;
  Model? get base => _base;
  EditHistory get history => _history;

  /// The profile used for lint and typed editors, if any.
  Profile? get profile => _profile;
  set profile(Profile? p) {
    _profile = p;
    _lint = null;
    _slots = null;
    notifyListeners();
  }

  /// Hides every editing control (the model is shown, not edited).
  bool get readOnly => _readOnly;
  set readOnly(bool v) {
    if (v == _readOnly) return;
    _readOnly = v;
    notifyListeners();
  }

  /// Compares against a new base (null leaves diff mode).
  set base(Model? b) {
    _base = b;
    _invalidate();
    if (diff.isEmpty) _changedOnly = false;
    notifyListeners();
  }

  ModelIndex? _index;
  ModelDiff? _diff;
  List<Finding>? _lint;
  Map<String, int>? _slots;
  ModelVisibility? _visibility;

  ModelIndex get index => _index ??= model.index;

  /// Changes against [base], with removed elements for ghosts.
  ModelDiff get diff => _diff ??= ModelDiff(model, index, _base);

  /// The change set against [base], or null without one.
  ChangeSet? get changes => diff.changes;

  /// Lint findings for the model and [profile].
  List<Finding> get lint => _lint ??= modelling.lint(index, _profile);

  /// Findings about one element.
  List<Finding> lintFor(String id) => [
    for (final f in lint)
      if (f.element == id) f,
  ];

  /// The areas the current search, filter and "Changed only" show.
  ModelVisibility get visibility => _visibility ??= ModelVisibility.compute(
    index,
    diff,
    text: _search,
    kinds: _kinds,
    tags: _tags,
    changedOnly: _changedOnly && !diff.isEmpty,
  );

  /// The palette slot of a relationship (current or removed).
  int slotOf(String edgeId) =>
      (_slots ??= relationshipSlots([...model.edges, ...diff.removedEdges.values], profile: _profile))[edgeId] ?? 0;

  void _invalidate() {
    _index = null;
    _diff = null;
    _lint = null;
    _slots = null;
    _visibility = null;
  }

  /// Runs [ops] as one undoable step. Throws [EditException] (and changes
  /// nothing) when an operation or the result is invalid. Typing into one
  /// field merges into one step unless [merge] is false (a discrete edit,
  /// such as adding a tag).
  Model apply(List<Op> ops, {bool merge = true}) {
    _history.apply(ops, merge: merge);
    _changed();
    return model;
  }

  /// [apply], reporting a failure through [notice] instead of throwing.
  /// Returns whether the ops applied.
  bool tryApply(List<Op> ops, {bool merge = true}) {
    try {
      apply(ops, merge: merge);
      return true;
    } on EditException catch (e) {
      notice.value = e.issues.isEmpty ? e.message : e.issues.first.message;
      return false;
    }
  }

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  void undo() {
    if (!canUndo) return;
    _history.undo();
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _history.redo();
    _changed();
  }

  /// Whether there are edits since the last [markSaved], or no save yet.
  bool get dirty => _history.isDirty;

  /// The operations that turn the last saved model into this one.
  List<Op> get pendingOps => _history.pendingOps;

  /// Records the current model as saved (after the host's save succeeds).
  void markSaved() {
    _history.markSaved();
    notifyListeners();
  }

  /// A new revision from the host (live refresh, or the saved result).
  /// Keeps selection, trail, collapsed and expanded areas, search and pins
  /// for ids that still exist; starts a fresh edit history. [base] replaces
  /// the current base when given.
  void replace(Model next, {Model? base}) {
    _history = EditHistory(next, limits: limits);
    if (base != null) _base = base;
    _changed();
  }

  void _changed() {
    _invalidate();
    _retain();
    if (diff.isEmpty) _changedOnly = false;
    notifyListeners();
  }

  bool _hasNode(String id) => index.node(id) != null;
  bool _hasEdge(String id) => index.edge(id) != null;

  /// Drops view state naming elements that no longer exist.
  void _retain() {
    final sel = _selection;
    if (sel != null && !exists(sel)) _selection = null;
    if (_focused != null && !_hasNode(_focused!) && !diff.removedNodes.containsKey(_focused)) _focused = null;
    final cut = _trail.indexWhere((id) => !_hasNode(id));
    if (cut >= 0) _trail.removeRange(cut, _trail.length);
    _collapsed.removeWhere((id) => id != '' && !_hasNode(id));
    _expanded.removeWhere((id) => !_hasNode(id));
    _pinned.removeWhere((id) => !_hasEdge(id) && !diff.removedEdges.containsKey(id));
    final h = hovered.value;
    if (h != null && !_hasEdge(h) && !diff.removedEdges.containsKey(h)) hovered.value = null;
  }

  /// Whether [ref] names an element of the model or a removed one.
  bool exists(ModelElementRef ref) => ref.isNode
      ? _hasNode(ref.id) || diff.removedNodes.containsKey(ref.id)
      : _hasEdge(ref.id) || diff.removedEdges.containsKey(ref.id);

  /// The node with [id], or the removed one from the base.
  Node? nodeOrGhost(String id) => index.node(id) ?? diff.removedNodes[id];

  /// The edge with [id], or the removed one from the base.
  Edge? edgeOrGhost(String id) => index.edge(id) ?? diff.removedEdges[id];

  /// An area's label (a removed one's from the base), else its id.
  String labelOf(String id) => nodeOrGhost(id)?.label ?? id;

  /// The containing area of a node or ghost ('' at the top level).
  String parentOf(String id) => _hasNode(id) ? index.parent(id) : diff.ghostParent(id);

  // ---- View state ----

  ModelElementRef? _selection;
  String? _focused;
  final _pinned = <String>{};
  final _trail = <String>[];
  final _collapsed = <String>{};
  final _expanded = <String>{};
  String _search = '';
  List<String> _kinds = const [];
  List<String> _tags = const [];
  bool _changedOnly = false;
  int? _limit;
  String _renderer;
  String? _activeView;
  List<ModelOverlay> _overlays = const [];
  String? _activeOverlay;

  /// The selected node or edge.
  ModelElementRef? get selection => _selection;
  void select(ModelElementRef? ref) {
    if (ref == _selection) return;
    _selection = ref;
    notifyListeners();
  }

  /// The area with keyboard focus in the active renderer.
  String? get focused => _focused;
  void focus(String? id) {
    if (id == _focused) return;
    _focused = id;
    notifyListeners();
  }

  /// Previews a relationship's connector (null clears).
  void hover(String? edgeId) => hovered.value = edgeId;

  /// Relationships whose connectors stay drawn.
  Set<String> get pinned => Set.unmodifiable(_pinned);
  bool isPinned(String edgeId) => _pinned.contains(edgeId);
  void togglePin(String edgeId) {
    if (!_pinned.remove(edgeId)) _pinned.add(edgeId);
    notifyListeners();
  }

  /// The drill-in path; its last area is the local root.
  List<String> get trail => List.unmodifiable(_trail);
  String? get region => _trail.isEmpty ? null : _trail.last;

  void drillIn(String id) {
    if (!_hasNode(id) || region == id) return;
    _trail.add(id);
    _limit = null;
    notifyListeners();
  }

  /// Back to the parent area.
  void back() {
    if (_trail.isEmpty) return;
    _trail.removeLast();
    _limit = null;
    notifyListeners();
  }

  /// Explicitly collapsed areas ('' is the root).
  Set<String> get collapsed => Set.unmodifiable(_collapsed);

  /// Areas opened past [openDepth]-based auto-collapse.
  Set<String> get expanded => Set.unmodifiable(_expanded);

  /// Whether area [id] (null: the root), [depth] levels below the drawn
  /// root, is folded given the theme's [openDepth].
  bool isFolded(String? id, int depth, int openDepth) =>
      id == null ? _collapsed.contains('') : _collapsed.contains(id) || (depth >= openDepth && !_expanded.contains(id));

  /// Folds or unfolds [id] (null: the root); [folded] is its state now.
  void toggleFolded(String? id, {required bool folded}) {
    final key = id ?? '';
    if (folded) {
      _collapsed.remove(key);
      if (id != null) _expanded.add(id);
    } else {
      _collapsed.add(key);
      if (id != null) _expanded.remove(id);
    }
    notifyListeners();
  }

  /// Unfolds [id] and every area containing it.
  void reveal(String id) {
    for (final p in [id, ...index.ancestors(id)]) {
      _collapsed.remove(p);
      _expanded.add(p);
    }
    _collapsed.remove('');
    notifyListeners();
  }

  /// The search text; changing it leaves drill-in and resets paging.
  String get search => _search;
  set search(String text) {
    if (text == _search) return;
    _search = text;
    _trail.clear();
    _limit = null;
    _visibility = null;
    notifyListeners();
  }

  /// The kind/tag filter (its text is [search]).
  Filter get filter => Filter(kinds: _kinds, tags: _tags, text: _search, changedOnly: _changedOnly);
  set filter(Filter f) {
    _kinds = f.kinds;
    _tags = f.tags;
    _search = f.text;
    _changedOnly = f.changedOnly && !diff.isEmpty;
    _trail.clear();
    _limit = null;
    _visibility = null;
    notifyListeners();
  }

  /// Narrows the model to what changed from [base].
  bool get changedOnly => _changedOnly;
  set changedOnly(bool v) {
    if (v == _changedOnly || (v && diff.isEmpty)) return;
    _changedOnly = v;
    _trail.clear();
    _limit = null;
    _visibility = null;
    notifyListeners();
  }

  /// Areas drawn before "Show more areas"; null is the theme's page size.
  int? get limit => _limit;
  void showMore(int pageSize) {
    _limit = (_limit ?? pageSize) + pageSize;
    notifyListeners();
  }

  /// The active renderer's id.
  String get renderer => _renderer;
  set renderer(String id) {
    if (id == _renderer) return;
    _renderer = id;
    renameRequest.value = null; // a rename the old renderer never took up
    notifyListeners();
  }

  /// The saved view last applied or saved.
  String? get activeView => _activeView;

  /// Shows the model as [view] says: renderer, drill-in root, collapsed
  /// areas and filter.
  void applyView(View view) {
    _renderer = view.renderer;
    _trail
      ..clear()
      ..addAll([if (view.root != '' && _hasNode(view.root)) view.root]);
    _collapsed
      ..clear()
      ..addAll(view.collapsed.where(_hasNode));
    _expanded.clear();
    final f = view.filter;
    _search = f?.text ?? '';
    _kinds = f?.kinds ?? const [];
    _tags = f?.tags ?? const [];
    _changedOnly = (f?.changedOnly ?? false) && !diff.isEmpty;
    _limit = null;
    _visibility = null;
    _activeView = view.id;
    notifyListeners();
  }

  View? _saved(String id) => model.views.where((v) => v.id == id).firstOrNull;

  /// The current view state as a saved view. Graph positions, grid sizes and options
  /// carry over from the saved view with [id].
  View currentView(String id, {String title = ''}) {
    final f = filter;
    final hasFilter = f.text.isNotEmpty || f.kinds.isNotEmpty || f.tags.isNotEmpty || f.changedOnly;
    final saved = _saved(id);
    return View(
      id: id,
      title: title,
      renderer: _renderer,
      positions: saved?.positions ?? const {},
      sizes: saved?.sizes ?? const {},
      options: saved?.options ?? const {},
      root: region ?? '',
      collapsed: [
        for (final n in model.nodes)
          if (_collapsed.contains(n.id)) n.id,
      ],
      filter: hasFilter ? f : null,
    );
  }

  /// Saves the current view state into the model (a `view.put` op, so it
  /// is undoable and saved with the model).
  void saveView(String id, {String title = ''}) {
    apply([Op.viewPut(currentView(id, title: title))]);
    _activeView = id;
    notifyListeners();
  }

  /// The active view's graph positions by node id (empty: auto layout).
  Map<String, Position> get positions => _saved(_activeView ?? '')?.positions ?? const {};

  /// Saves node positions into the active view (or a new "layout" view),
  /// as one undoable `view.put`. [replace] drops the other positions, so
  /// `setPositions({}, replace: true)` returns to auto layout.
  bool setPositions(Map<String, Position> moved, {bool replace = false}) =>
      _putActiveView((v) => v.copyWith(positions: replace ? moved : {...v.positions, ...moved}));

  /// The active view's grid sizes by node id (absent: auto).
  Map<String, NodeSize> get sizes => _saved(_activeView ?? '')?.sizes ?? const {};

  /// Saves grid sizes into the active view (or a new "layout" view), as one
  /// undoable `view.put`; a null size returns that area to auto.
  bool setSizes(Map<String, NodeSize?> changed) => _putActiveView(
    (v) => v.copyWith(
      sizes: {
        for (final e in {...v.sizes, ...changed}.entries)
          if (e.value case final NodeSize size) e.key: size,
      },
    ),
  );

  /// Writes [change] of the active view (a new "layout" view when none is
  /// active) as one `view.put`, then makes it the active view.
  bool _putActiveView(View Function(View saved) change) {
    final id = _activeView ?? 'layout';
    if (!tryApply([Op.viewPut(change(_saved(id) ?? currentView(id)))])) return false;
    _activeView = id;
    notifyListeners();
    return true;
  }

  /// The blocks board's zoom (1 is 100%), shown in the editor's status bar.
  final zoom = ValueNotifier<double>(1);

  /// Host overlays the workspace can show.
  List<ModelOverlay> get overlays => _overlays;
  set overlays(List<ModelOverlay> v) {
    _overlays = List.unmodifiable(v);
    if (_activeOverlay != null && !_overlays.any((o) => o.id == _activeOverlay)) _activeOverlay = null;
    notifyListeners();
  }

  /// The shown overlay's id (null: none).
  String? get activeOverlay => _activeOverlay;
  set activeOverlay(String? id) {
    if (id == _activeOverlay) return;
    _activeOverlay = id;
    notifyListeners();
  }

  /// The shown overlay, if any.
  ModelOverlay? get overlay {
    for (final o in _overlays) {
      if (o.id == _activeOverlay) return o;
    }
    return null;
  }

  @override
  void dispose() {
    hovered.dispose();
    notice.dispose();
    renameRequest.dispose();
    zoom.dispose();
    super.dispose();
  }
}
