# modelling_flutter

Flutter renderers, editor, theming and file sources for block models ([docs/format.md](../../../docs/format.md)),
on Flutter desktop and web. Built on the pure-Dart [`modelling`](../../dart/modelling) package; imports Flutter
and `modelling` only (plus `file_selector` and `package:web` for files). Design: [docs/design.md](../../../docs/design.md) §7.

```dart
final controller = ModelController(model, base: previousRevision, profile: profile);

ModelWorkspace(
  controller: controller,
  theme: myModelTheme,              // optional: else the inherited ModelThemeScope, else ModelTheme.fallback
  chrome: myChrome,                 // optional: else the inherited ModelChromeScope, else ModelChrome.material()
  renderers: const [BlocksRenderer(), OutlineRenderer()],
  onEvidence: (ref) => openArtifact(ref.id),
  onAttachEvidence: (element) async => controller.attachEvidence(element, await pickEvidence()),
  onOpenLink: (link) => openModel(link.model),
  onSave: (ops, result) => source.save(loaded, ops, result).then((_) {}),
  openLabel: 'Open',
);
```

For a full design tool rather than an embedded board, `ModelEditor` takes the same controller and hooks and
lays the model out as an editor: a one-row top bar, a component palette and Layers tree on the left, a docked
inspector on the right and a status bar. It defaults to grid blocks and the outline:

```dart
ModelEditor(
  controller: controller,
  renderers: const [BlocksRenderer(grid: true), OutlineRenderer(), GraphRenderer()],
  profiles: [androidProfile],        // offered by the model overview's profile picker
  onSave: (ops, result) => source.save(loaded, ops, result).then((_) {}),
  leading: myMenuBar,                // optional: before the title
  actions: [ModelEditorAction(label: 'Gallery', icon: Icons.grid_view_rounded, onPressed: openGallery)],
);
```

## Pieces

| Piece | What it is |
| --- | --- |
| `ModelController` | One per open model (a `ChangeNotifier`). `model`, `base` (diff: `diff`, `changes`), `profile`, `lint`, `history`; `apply(ops)` / `tryApply`, `undo`, `redo`, `canUndo`, `canRedo`, `dirty`, `pendingOps`, `markSaved`; `readOnly`. View state by id: `selection`, `focused`, `hovered` (a `ValueNotifier`), `pinned`, `trail` (`drillIn`, `back`), `collapsed`/`expanded` (`toggleFolded`, `isFolded`, `reveal`), `search`, `filter`, `changedOnly`, `limit` (`showMore`), `renderer`, `applyView` / `saveView` (a `view.put` op), `positions` / `setPositions` (graph positions in the active view, a `view.put`), `sizes` / `setSizes` (grid sizes in the active view, a `view.put`; `null` returns an area to auto), `zoom` (a `ValueNotifier` the grid board and status bar share), `overlays` / `activeOverlay`, `notice` (refusals and failures). `replace(next, {base})` takes a new revision and keeps view state for ids that still exist. |
| `ModelEditing` (extension) | Gestures as ops: `addChild`, `addSibling`, `rename`, `deleteNode`/`deleteEdge` (`removalOf` says what a delete takes), `reparent` (`reparentRefusal` explains cycles and profile `children` violations; `childRefusal` the profile part alone), `addKind` (a child of a given kind, refused with a notice when the profile forbids it, then renamed in place), `moveBeside` (reorder next to a sibling, moving parents when needed), `indent`, `outdent`, `reorder`, `addRelationship` (`edgeKindsFor` lists the profile's allowed kinds), `setFields`, `setProperty`, `attachEvidence`, `removeEvidence`, `useProfile` (sets `profile` and the model's `profile` field). |
| `ModelWorkspace` | "Find area" search, "Changed only", renderer switcher, overlay picker, Add area (inside the selected area, else at the top level; blocks and outline then rename it in place), undo/redo/Save (when editable), export menu (Mermaid/outline copy or save, model JSON, PNG), status line (also `WorkspaceStatus` on its own, for a renderer shown without the toolbar), active renderer. Ctrl+Z / Ctrl+Y / Ctrl+S. |
| `BlocksRenderer` | Nested area blocks (labs' board, theme.md §5.17): columns, depth fills, collapse/expand, open-depth auto-collapse, drill-in, paging, relationship dots with hover-preview and click-to-pin connectors, relationships list, change marks, removed ghosts, lint/overlay/link badges. Keys: Up/Down move, Enter inspects, Right drills in, Left/Backspace back, Space folds, F2 renames, Delete deletes. Edit mode: area menu (add inside/beside, rename, delete), double-click rename, drag the ⠿ handle onto an area to reparent, drag the ◎ handle onto an area to draw a relationship. |
| `BlocksRenderer(grid: true)` | The editor's blocks layout (off by default; `const BlocksRenderer()` is unchanged). Top-level areas sit on a dotted canvas with no root card. Each parent lays its children on a 10-column grid: an area's `sizes` entry gives its width in tenths and its height in rows of `gridRow`; without one it takes an auto span (`packGrid`, `autoSpan`) and rows end flush. Edit mode: drag the right edge, bottom edge or corner to resize (snaps to tenths and rows, live readout, one undoable `view.put`; double-click resets to auto), drag the ⠿ handle onto the edge of a sibling to reorder (drop indicator) or onto its middle to move inside, drop a palette kind to add. |
| `OutlineRenderer` | Indented lazy tree with relationships under each area; diff marks and ghosts; narrow-screen friendly. Keys: Up/Down, Left/Right fold or move, Space folds, Ctrl+I (or Enter when read-only) inspects; editing: Enter new sibling, Tab / Shift+Tab reparent, F2, Delete, Alt+Up/Down reorder. |
| `GraphRenderer` | Node-link canvas (`CustomPainter`, culled to the viewport): compound boxes for containment, relationship lines in palette colours with arrowheads and labels, pan/zoom and zoom to fit, deterministic layered auto layout (`layoutGraph`), removed ghosts dashed, marks on areas and labels. Tap selects, double-tap inspects; editing: drag an area to save its position in the active view (`positions`, top-left in drawing coordinates; contents move with it), "Auto layout" forgets them. |
| `MatrixRenderer` | Dependency structure matrix (`layoutMatrix`): a row and column per area in containment order, containment blocks on the diagonal, relationship counts per cell (row → column; undirected both ways), split by kind colour when the profile declares edge kinds, change corners, the selected area's row and column. Tap a cell to list its relationships; each opens the inspector. |
| `TableRenderer` | Areas or relationships as rows: id, label, kind, parent (or from/to), tags, then the profile's declared properties and any others in use. Sort by a column header (ascending, descending, model order), filter rows, inline edit of label, kind, tags and properties through `ModelEditing` (undoable); removed rows struck through; read-only shows values only. |
| `ModelEditor` | The editor shell. Top bar (never wraps; search and actions fold into menus when narrow): side-panel toggles, `leading`, title (click to rename), unsaved dot, renderer switcher (`ViewSwitcher`), search, undo/redo, export, `actions` (`ModelEditorAction`), Save. Left panel: `ComponentPalette` (the profile's kinds, else generic ones; drag onto the board or Layers, or click to add inside the selection) and `LayersTree` (select, drag to move or reorder). Right panel: `DockedInspector` for the selection, else `ModelOverview` (title, subject, notes, profile, summary, checks). Status bar: counts, lint, notices, overlay, zoom, saved state. Panels resize by their edge, collapse, and keep their width for the session; below `ModelEditor.drawerWidth` (900) they become drawers. Ctrl+Z / Ctrl+Y / Ctrl+S (`ModelShortcuts`). |
| `inspectElement` | The shared inspector for an area or relationship (current or removed): values, typed property editors from the profile, evidence, relationships, link, changes from the base (old → new), lint. Edits go through ops. When `ModelHooks.onInspect` is set (the editor sets it), it hands the element to the host instead of opening a dialog. |
| `ModelSource` | `list()`, `read(id)` → `LoadedModel{model, summary, editable, base}`, `save(at, ops, result)` → `ModelSummary`. `MemoryModelSource` (tests, gallery), `FileModelSource` (`open()` for `.model.json`, `.mmd`, `.md`; saves in place on desktop, downloads on the web; `saveAs` always asks; recents in `localStorage` on the web). |

Overlays are host data drawn on the model without being stored in it:

```dart
controller.overlays = [
  ModelOverlay(id: 'findings', label: 'Open findings', legend: {'High': red},
      marks: {'net': OverlayMark(badge: '2 high', color: red, value: 0.8)}),
];
controller.activeOverlay = 'findings';
```

## Theming: `ModelTheme` and `ModelChrome`

Renderers draw only with `ModelTheme` tokens and `ModelChrome` widgets; nothing is hard-coded.

- `ModelTheme` holds labs' `ModelSpec` fields (area fills by depth, borders, radius, padding, gap, label chip,
  min area width, max columns, dot size, max dots, connector width, arrow size, page size, open depth), text
  styles (`heading`, `standard`, `small`, `overline`), `spacing`, the categorical `palette`, colours (`text`,
  `surface`, `raised`, `hover`, `muted`, `focus`, `added`, `changed`, `removed`, `lintError/Warning/Info`) and a
  `motion` hook for reduced motion. Editor tokens: `canvas`, `canvasDot`, `panel`, `divider`, `shadow` (each
  falls back to a value derived from the others when a host leaves it unset), `gridRow`, `gridAutoColumns`,
  `gridMinWidth`, `panelWidth`, `inspectorWidth`, `barHeight`, `motionQuick` (drop previews and reflow; through
  `quickDuration`, so the `motion` hook applies) and `innerRadius` (concentric corners inside a frame). `ModelTheme.fallback(Brightness)` looks right in light and dark (dark matches
  labs' theme.yaml). Provide with `ModelThemeScope` or `ModelWorkspace(theme:)`; `copyWith` adjusts.
- `ModelChrome` is the small set of host-styled pieces: `button`, `iconButton`, `filterChip`, `searchField`,
  `textField`, `select`, `menuButton`, `menu` (a labelled menu of `ModelMenuItem`s with icons and `ModelKeys`
  shortcut hints, `ModelSubmenu`s and `ModelMenuDivider`s, e.g. a host's File menu), `tagChip`, `fieldFrame`,
  `statusDot`, `tooltip`, `showInspector`, `confirm`. Subclass
  `MaterialModelChrome` to replace a few, or implement `ModelChrome` fully. Implementations must keep the
  abstract defaults (Dart takes defaults from the implementation).

Dialogs are built under the Navigator, outside the workspace: use `captureModelScopes(context)` to carry the
theme, chrome and hooks into dialog contents.

## Adding a renderer

```dart
class TimelineRenderer extends ModelRenderer {
  const TimelineRenderer();
  @override String get id => 'timeline';          // also a saved view's `renderer`
  @override String get label => 'Timeline';
  @override IconData get icon => Icons.timeline;
  @override Widget build(BuildContext context, ModelController c) => TimelineView(controller: c);
  @override int shownAreas(ModelController c, ModelTheme t) => c.visibility.included.length; // optional
}
```

Read the controller and send intents to it; keep no model state. Shared helpers keep renderers consistent:
`controller.visibility` (search/filter/changed-only inclusion), `shownNodes` / `shownEdges` (what a flat
renderer draws, in containment order with ghosts), `ModelCanvas` (pan/zoom/zoom-to-fit with the visible rect for
culling), `controller.diff` (change lookup, removed
ghosts, `edgesAt`), `controller.slotOf(edgeId)` + `ModelTheme.paletteAt` (relationship colours, by edge id or by
profile kind), `elementMarks` (change, link, lint, overlay badges), `RelationshipRow`, `inspectElement`,
`promptRelationship`, `confirmDeleteNode`, `InlineRenameState`/`InlineRenameField`, `TagsField` (tags as
removable chips), and the `ModelEditing` gestures. In `ModelEditor` a renderer fills the whole board; apply
`BoardInsets.maybeOf(context)` inside your scrollables to keep content off its edges.
Put the whole drawing in `RepaintBoundary(key: ModelHooks.of(context).captureKey)` for PNG export.

## Checks

```bash
flutter pub get && flutter analyze && dart format --set-exit-if-changed lib test example && flutter test
cd example && flutter analyze && flutter build web
```

`example/` is a minimal app: `ModelWorkspace` with every renderer over the conformance fixture from a
`MemoryModelSource`, with a base revision (diff mode) and an overlay. `apps/modeller` is the full standalone app.
