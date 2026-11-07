# modelling-services: design

Status: **implemented**, 2026-11-06. Where the build departed from the proposal, §11 says how and why.

modelling-services is the library for **block models**: labelled areas nested by containment,
labelled relationships between them, and evidence cited on both. It takes over the code
craggy-labs grew for this (the Go `intel.Graph` core and the Flutter `CraggyModelView`), makes
the model a versioned data format with one schema, and adds editing, diffing, querying,
import/export and several renderers. craggy-labs then becomes a consumer, the same way it already
consumes artifact-services, script-services and agent-sdk.

---

## 1. What exists today

| Piece | Where | What it does | Problem |
| --- | --- | --- | --- |
| Graph core | `craggy-labs/features/intel/model.go` (238 lines) | `Graph`/`Node`/`Edge`/`ModelEvidence`, `Validate`, `Citations`, `Attach`, `DecodeGraph` | Generic code inside a domain unit; bounds and the "lab artifact" citation are hard-wired |
| Storage + caps | `features/intel/models.go`, `intelcap/caps_models.go` | `models.create/update/attach/read/list`; each revision is a lab blob artifact, run inputs record the base and the cited evidence | Update takes the whole graph: an agent must resend 500 KiB to rename one area |
| Template boards | `features/intel/pack.go`, `board.go` | A topic's expected `Board` is seeded as a read-only system model | A second, evidence-less copy of the node/edge shape |
| Dart types | `ui/lib/client/models.dart` (`ModelBoard*`) | Hand-written mirror of the Go types | Drift between Go and Dart is caught only by UI tests |
| Diff | `ui/lib/models/model_board_view.dart` | Marks elements `added`/`changed` against a template, by string comparison in the widget | No `removed`; diff logic lives in a view adapter; Go can't diff |
| Renderer | `ui/lib/design_system/model_view.dart` (1,139 lines) | Nested area blocks, search, collapse, drill-in, relationship dots, hover connectors, relationships list, inspector dialogs, "Changed only" | Read-only; one view; over the 500-line rule; resets all view state when a new revision arrives; tied to labs' `ThemeScope` and Craggy widgets |

The current behaviour is good and worth keeping. The block view's interaction model (dots per area,
hover to draw the connector, drill into a region, inspector with evidence) is the baseline the
library must match before it adds anything.

## 2. Goals and non-goals

**Goals**

1. One **model format**: a JSON document with a published JSON Schema, a version number and a
   migration from today's v1 graphs.
2. **Create, load, edit and save** models: from scratch, from a template, from a file, from a host
   store, in Go (for agents and capabilities) and in Dart (for the editor).
3. **Render several ways.** Flutter first, on desktop and the web, with the block view as the first
   renderer and more to follow. Text exports (Mermaid, DOT, Markdown, SVG) for everything else.
4. **Same semantics in Go and Dart**: validation, diff and edit operations proven equal by one set
   of shared conformance vectors.
5. **Labs gets simpler**: `intel/model.go`, the Dart `ModelBoard*` types, `model_board_view.dart`
   and `design_system/model_view.dart` are deleted, not wrapped.

**Non-goals**

- Storage. The library never owns a database or a CAS. Hosts store documents; artifact-services
  already owns storage, artifacts and lineage.
- Authentication, caller policy, lab membership. Those stay in the host.
- A general diagramming tool (free shapes, arrows to nowhere, styling per element). This is a
  *model*: every pixel is derived from semantic data plus a view.
- Real-time multi-user co-editing (CRDTs). Edit operations make it possible later (§6.3); not now.

## 3. Repository layout

Same conventions as the other craggy-io repos: a Go module at the root, nested modules for heavy
adapters, Dart packages under `clients/`, an `AGENTS.md`, `docs/` with one page per package, an
`arch_test.go` enforcing layers.

```
modelling-services/
  AGENTS.md  README.md  LICENSE  go.mod
  arch_test.go
  schema/
    model.v2.schema.json        # the format: the source of truth for both languages
    model.v1.schema.json        # today's intel graph, read-only (migration input)
  conformance/
    documents/{valid,invalid}/*.json   # decode + validate vectors
    diff/*.json                         # base, revision -> expected change set
    ops/*.json                          # document + ops -> expected document or error
    migrate/*.json                      # v1 -> v2
    export/*.{json,mmd,dot,md}          # document -> expected text export
  model/          # Go: types, codec, validate, limits, migrate v1
  edit/           # Go: operations, apply, invert (undo), diff -> ops
  diff/           # Go: structural change set between two documents
  query/          # Go: subtree, ancestors, neighbours, paths, impact, search, lint
  export/         # Go: Mermaid, DOT, Markdown outline, static SVG; import Mermaid/outline
  modelcap/       # Go: capability-services registrations over a Store port
  kinds/          # Go: foundation-kit kind "craggy.model" so bundles can ship templates
  clients/
    dart/modelling/            # pure Dart: types, codec, validate, diff, edit, query (no Flutter)
    flutter/modelling_flutter/ # renderers, controller, editor, theme, file sources
  apps/
    modeller/                  # standalone Flutter app (desktop + web): gallery, editor, test bed
  docs/
    design.md (this)  format.md  edit.md  diff.md  query.md  export.md  modelcap.md
    flutter.md  migration.md
```

### Layers

| Layer | Go | Dart | May import |
| --- | --- | --- | --- |
| Format | `model` | `modelling` (`model.dart`, `codec.dart`) | standard library, `foundation-kit/canonjson` |
| Engines | `edit`, `diff`, `query`, `export` | `modelling` (`edit.dart`, `diff.dart`, `query.dart`) | format |
| Host adapters | `modelcap`, `kinds` | — | engines, capability-services, foundation-kit `kind` |
| Presentation | — | `modelling_flutter` | `modelling`, Flutter |
| App | — | `apps/modeller` | everything |

Engines don't import each other except `edit` → `diff` (to turn a change set into operations).
`modelling_flutter` never imports anything from craggy-labs: it is themed and wired by its host
(§7.4).

### Why both Go and Dart

The Flutter editor must validate, diff and apply edits offline and per keystroke, without a
round trip; agents and capabilities need the same operations server-side, where the canonical
document is stored. Implementing the *format and engines* twice is cheap (they're small and pure)
and the conformance vectors keep them identical, the same way auth-services keeps its Dart client
in step with Go. **Layout and rendering are not duplicated**: interactive rendering is Dart-only;
Go has only text exports and a simple static SVG.

## 4. The model format (v2)

### 4.1 Principles

- **Semantics and presentation are separate.** Nodes, edges, properties and evidence are the
  model. Positions, collapsed areas, filters and which renderer to use are *views* (§4.4), stored
  alongside but never required to understand the model. Two people can look at one model in two
  ways without creating two models.
- **Containment is the parent field, never an edge.** Kept from v1: relationships never imply
  nesting, nesting is acyclic.
- **Stable ids everywhere.** Every element, view and evidence item has an id, so diffs, edit
  operations, selections and live refresh can match by id across revisions.
- **Provenance stays outside.** Who wrote a revision, what it was based on and which run stored it
  are lineage (artifact-services), not document fields. The document says what the model *is*.
- **Bounded.** Limits are part of validation, with defaults; a host may tighten them.

### 4.2 Shape

```jsonc
{
  "format": "craggy.model",
  "version": 2,
  "title": "Payment service",
  "subject": "com.example.pay 4.2.1",
  "notes": "Seeded from the android-app topic board.",
  "profile": "craggy.profile/android-app@1",      // optional: element kinds and rules (§4.3)
  "tags": ["android"],

  "nodes": [
    {
      "id": "net",
      "label": "Network layer",
      "parent": "app",                 // containing node; "" or absent = top level
      "kind": "component",             // optional, from the profile
      "notes": "OkHttp with a custom pinning interceptor.",
      "tags": ["attack-surface"],
      "properties": { "language": "kotlin", "exported": false, "risk": 3 },
      "evidence": [
        { "id": "ev1", "caption": "Pinner config",
          "ref": { "scheme": "artifact", "id": "a_91f…", "selector": "/res/xml/nsc.xml" } }
      ],
      "link": { "model": "a_77c…", "node": "" }   // optional: drill into another model (§4.5)
    }
  ],

  "edges": [
    {
      "id": "e1", "from": "ui", "to": "net",
      "label": "calls", "kind": "calls", "directed": true,
      "notes": "", "properties": {}, "evidence": []
    }
  ],

  "views": [ /* §4.4 */ ]
}
```

Changes from v1:

| v1 | v2 | Why |
| --- | --- | --- |
| `version: 1` | `format` + `version: 2` | Self-identifying files; a loader can refuse non-models cheaply |
| `evidence[].citation.{artifactId, selector}` | `evidence[].{id, caption, ref: {scheme, id, selector}}` | The library is not lab-specific: `artifact`, `url`, `file` and host-defined schemes. Labs uses `artifact`. Evidence gets an id so it can be removed or edited by an operation |
| — | `kind`, `tags`, `properties` on nodes and edges | Typed modelling, filtering, overlays, the table renderer |
| — | `directed` on edges (default `true`) | "Shares data with" is not "calls" |
| — | `link` on nodes | Replaces the host-side `openable` set: a node can open a sub-model |
| — | `profile` | Optional rules for kinds and properties |
| — | `views` | Saved perspectives and layouts |
| Template diff computed in the widget | `diff` package, both languages | Adds `removed`, field-level changes, and works server-side |

`properties` values are JSON scalars only (string, number, bool). Nested objects are refused:
they would make diff, the table view and profile validation much harder for little gain.

### 4.3 Profiles (optional metamodel)

A profile declares the vocabulary a model may use, so a "threat model" and an "app architecture"
can each be checked for shape:

```yaml
id: craggy.profile/android-app
version: 1
nodeKinds:
  app:        { label: Application, children: [component, process] }
  component:  { label: Component, children: [component, class] , properties: { language: { type: string, enum: [java, kotlin, native] }, exported: { type: bool } } }
edgeKinds:
  calls:      { label: calls, from: [component, class], to: [component, class] }
  exposes:    { label: exposes, directed: true }
rules:
  requireKinds: true          # every node and edge must declare a kind
```

- A model without `profile` is free-form and validates as v1 did.
- Profiles are bundle content (foundation-kit kind `craggy.model-profile`, declared in `kinds/`),
  resolved by the host and passed to validation. The document only names one.
- Profile violations are **lint findings**, not decode errors, unless the host asks for strict
  validation. An agent mid-way through building a model shouldn't be refused for a missing kind.
- The editor uses the profile to offer kinds, allowed children and property editors.

### 4.4 Views

```jsonc
"views": [
  {
    "id": "overview",
    "title": "Overview",
    "renderer": "blocks",                 // blocks | graph | outline | matrix | table
    "root": "",                           // drill-in region; "" = whole model
    "collapsed": ["vendor"],
    "filter": { "kinds": ["component"], "tags": [], "text": "", "changedOnly": false },
    "positions": { "net": [420, 180] },    // graph renderer only; absent = auto layout
    "options": { "openDepth": 2 }          // renderer-specific, ignored by others
  }
]
```

- Views are optional. A model with none opens in the host's default view.
- A view edit is an operation like any other (§6), so it's versioned and undoable, but **diff
  ignores views by default**: moving a box is not a change to the model.
- Renderers ignore view fields they don't understand, so adding a renderer never breaks a document.

### 4.5 Cross-model links

`link: {model, node}` lets an area stand for a whole other model (an app's "Native libraries" area
opens the native-library model). The library only carries the reference and offers an "Open" action;
the **host resolves** the id (a lab artifact id in labs, a file path in the standalone app). This
generalises today's `openable` + `onOpen`, which only intel boards use.

### 4.6 Limits

Defaults match today's labs bounds, and the host can tighten them:

| Limit | Default |
| --- | --- |
| Document size | 512 KiB |
| Nodes / edges | 1,000 / 2,000 |
| Distinct evidence refs | 128 |
| Containment depth | 32 |
| Properties per element / value length | 32 / 1 KiB |
| Views | 32 |

### 4.7 Versioning and migration

- `model.Decode` accepts v1 and v2. A v1 document is **upgraded on read**: `citation` becomes
  `ref{scheme: "artifact"}`, evidence ids are generated deterministically (`ev` + index), and
  `format` is added. Encoding always writes v2.
- Labs model revisions are immutable artifacts, so the stored v1 files can't be rewritten in place.
  Upgrade-on-read is the data migration, not a compatibility shim: once a v1 model is revised it is
  stored as v2. The `migrate/` conformance vectors pin the upgrade.
- Future versions follow the same rule: decode N-1 and N, write N.
- Encoding is canonical (`foundation-kit/canonjson`), so equal models hash equally and "did
  anything change?" is a digest comparison.

## 5. Go packages

### 5.1 `model`

```go
type Model struct { Format string; Version int; Title, Subject, Notes, Profile string; Tags []string;
    Nodes []Node; Edges []Edge; Views []View }

func Decode(raw []byte) (Model, error)          // strict; upgrades v1
func Encode(m Model) ([]byte, error)            // canonical v2
func (m Model) Validate(l Limits) error         // structural: ids, labels, parents, acyclic, endpoints, bounds
func (m Model) Index() *Index                   // children, ancestors, edges by node; built once, read-only
func (m Model) Refs() []Ref                     // distinct evidence refs (today's Citations)
func New(title, subject string) Model
```

`Validate` returns all structural errors as one joined error with element ids, not just the
first: an agent fixing a model needs the whole list.

### 5.2 `edit`: operations

Every change, from a UI drag to an agent tool call, is a list of small operations:

| Op | Fields |
| --- | --- |
| `node.add` | node (full), `index` (sibling order) |
| `node.remove` | `id`, `cascade` (remove descendants and their edges) or refuse if not empty |
| `node.move` | `id`, `parent`, `index` |
| `node.set` | `id`, any of label, kind, notes, tags, link |
| `edge.add` / `edge.remove` / `edge.set` | as above; `edge.set` may change ends |
| `prop.set` / `prop.unset` | element id, key, value |
| `evidence.add` / `evidence.remove` | element id, evidence (dedupe by ref, as `Attach` does today) |
| `model.set` | title, subject, notes, profile, tags |
| `view.put` / `view.remove` | view |

```go
func Apply(m Model, ops []Op, l Limits) (Model, []Op /*inverse*/, error) // atomic: all or nothing, result validated
```

- `Apply` returns the inverse operations, which is undo/redo for the editor and the basis of
  later merge.
- Operations name elements by id, never by index, so a batch is meaningful against a revision it
  wasn't computed from, as long as the ids exist. That gives a simple **optimistic concurrency**
  rule for hosts: apply to the latest revision, and refuse only when an op's target has gone.
- Today's `Graph.Attach` becomes one `evidence.add` op per citation.

### 5.3 `diff`

```go
type ChangeSet struct { Nodes, Edges []Change; Model []FieldChange }
type Change struct { ID string; Kind Added|Removed|Changed; Fields []FieldChange /* label, parent, notes, kind, props.x, evidence */ }
func Compare(base, rev model.Model, o Options) ChangeSet  // o.Views to include view changes
```

This replaces the widget's string comparison, adds **removed** elements (which the block view can
show as ghosts), says *which field* changed (the inspector can show "label: Network → Network
layer"), and lets labs answer "what did the agent change in this revision?" server-side.

### 5.4 `query`

Pure functions over `model.Index`:

- `Subtree`, `Ancestors`, `Siblings`, `Region(id)` (what the block view shows when drilled in).
- `Neighbours(id, direction, depth)`, `Paths(from, to, maxLen)`, `Impact(id)` (everything that
  can reach or be reached through directed edges, including via containment).
- `Search(text, filter)` across labels, notes, tags and properties; the same filter type views use.
- `Lint(m, profile)`: orphans in deep models, edges between an area and its own ancestor, nodes
  with no evidence, duplicate labels among siblings, profile violations. Each finding has a rule id,
  element id and message, so the UI can mark it and an agent can fix it.

### 5.5 `export`

| Format | Direction | Use |
| --- | --- | --- |
| Mermaid `flowchart` with `subgraph` per area | export + import | Markdown reports, GitHub, chat answers |
| Graphviz DOT with clusters | export | High-quality static layout by an external tool |
| Markdown outline (nested bullets + relationships table) | export + import | Reports, agents reading a model cheaply, quick authoring from an outline |
| Static SVG (nested blocks, no connectors or straight ones) | export | Certificates, website, thumbnails; text widths estimated |
| CSV (nodes, edges) | export + import | Spreadsheets, bulk authoring |

Imports produce a `Model` that is then validated like any other; ids are derived from labels
(slugged, de-duplicated) when the source has none.

### 5.6 `modelcap`

The other services ship a `<x>cap` package (agentcap, envcap, starlarkcap). modelling-services
does the same: generic capability registrations over a small port the host implements.

```go
type Store interface {
    List(ctx context.Context, scope string) ([]Summary, error)
    Read(ctx context.Context, scope, id string) (model.Model, Summary, error)
    Save(ctx context.Context, scope string, m model.Model, base string, how string) (Summary, error) // how: create|update|apply|attach
}
type Deps struct { Store Store; Limits model.Limits; Profiles ProfileResolver; Prefix string }
func Capabilities(d Deps) []registry.Capability
```

| Capability | Does |
| --- | --- |
| `<prefix>.list`, `.read` | As today; `read` takes `format: json|outline|mermaid` so an agent can read a large model as a compact outline |
| `.create` | From a document, an import (`mermaid`, `outline`, `csv`), or `basedOn` another model |
| `.apply` | **New.** A list of operations against a revision; returns the new revision, inverse ops and lint findings. Replaces whole-graph `update` for agents |
| `.update` | Whole-document replace (kept: the editor saves this way when it has many ops) |
| `.diff` | Change set between two revisions, or a revision and its base |
| `.lint`, `.query` | Lint findings; neighbours/paths/impact for an agent's reasoning |
| `.export` | Mermaid/DOT/Markdown/SVG/CSV |

The scope string is opaque to the library (a lab id in labs). Errors map through
`registry.Codes` with one table (`ErrInvalid`, `ErrNotFound`, `ErrReadOnly`, `ErrConflict`).
The *host's* store decides what "read-only" means (labs: system models).

## 6. Dart: `modelling` (pure Dart)

Same API shape as Go, idiomatic Dart, no Flutter dependency so it runs in `dart test`, on the web
and in a CLI:

```dart
final model = Model.decode(json);           // upgrades v1
final errors = model.validate(limits);
final (next, inverse) = apply(model, [NodeAdd(...), EdgeAdd(...)]);
final changes = compare(base, next);
final hits = Query(model.index).search('pinning', Filter(kinds: {'component'}));
```

- Immutable value types with `==`/`hashCode`, so Flutter can rebuild cheaply and compare
  revisions.
- Both test suites run every file under `conformance/`. A behaviour change lands as a new vector
  first, then in both languages, in one commit.

### 6.1 Edit history

`EditHistory` holds `(ops, inverse)` pairs: undo/redo, "squash typing into one step" (consecutive
`node.set` on one field merge), and the pending op list a host sends on save (`.apply`), so saves
are small even for big models.

### 6.2 Sources: create and load

```dart
abstract interface class ModelSource {
  Future<List<ModelSummary>> list();
  Future<LoadedModel> read(String id);                        // model + summary (editable? base?)
  Future<ModelSummary> save(LoadedModel at, List<Op> ops, Model result);
}
```

| Source | Package | Platform |
| --- | --- | --- |
| `FileModelSource` | `modelling_flutter` | Desktop: `dart:io` + file picker. Web: upload/download through conditional imports, plus browser local storage for recents |
| `MemoryModelSource` | `modelling` | Tests, the gallery |
| `LabsModelSource` | **craggy-labs** `ui/` | Over the labs client (`models.*`); lives in labs, not the library |

"New model" offers: blank, from a template (any model, or a profile's starter), from Mermaid or an
outline pasted in, from a CSV.

### 6.3 Later: concurrent edits

Because ops are id-addressed and invertible, a later three-way merge is "rebase my pending ops onto
the new revision, drop ones whose target is gone, report them". Not in scope now; the design
doesn't block it.

## 7. Flutter: `modelling_flutter`

### 7.1 Controller

One `ModelController` (a `ChangeNotifier`) per open model, shared by every renderer and the
chrome:

- `model`, `base` (for diff), `changes`, `lint`, `history`, `profile`.
- **View state**: selection, hover, focus, drill-in trail, collapsed set, search, filter, active
  view. Kept by element id.
- `replace(Model next)`: a new revision from the host (live refresh). **Keeps** selection, trail
  and collapsed areas whose ids still exist. Today's widget throws all of it away on every
  revision, which is what makes live updates jarring.
- `apply(ops)`, `undo()`, `redo()`, `dirty`, `pendingOps`.

Renderers read the controller and send intents to it. They hold no model state of their own, so
switching renderer keeps the user's place.

### 7.2 Renderers

| Renderer | For | Notes |
| --- | --- | --- |
| **Blocks** (port of today's view) | The default: nested areas with relationship dots | Same interaction as now. Adds: removed-element ghosts in diff mode, keyboard navigation (arrows move between areas, Enter inspects, `→` drills in), lint and overlay badges, "pin connector" (click a dot to keep its connector drawn), zoom to fit |
| **Graph** | Seeing relationships at a glance | Node-link canvas with compound (containment) boxes, pan/zoom, auto layout (layered for directed edges) with manual positions saved in the view. Edge bundling by kind when dense |
| **Outline** | Narrow screens, screen readers, quick editing | Indented tree, relationships listed under each node, fully keyboard-editable (Tab/Shift-Tab reparents). Also the accessible fallback for the other two |
| **Matrix** (DSM) | Large models, spotting cycles and layering | Node × node grid grouped by containment; cells show edge counts by kind; click a cell to list its edges |
| **Table** | Bulk editing of properties | Nodes or edges as rows, profile properties as columns, sort/filter, inline edit |
| **Diff** | Any of the above with `base` set | Not a separate widget: a mode every renderer supports, using `ChangeSet` (added, changed, removed ghost) |

All renderers share: the inspector, search and filter bar, the change marker, the colour assignment
for relationships (by edge id, as now, or by kind when a profile declares kinds), and the overlay
API (§7.5).

### 7.3 Editing

Built on the controller's ops, so every gesture is undoable and saves as `.apply`:

- Add child / sibling area; inline rename (double-click or F2); delete with cascade confirm.
- Drag an area onto another to reparent (refused with a reason if it would create a cycle or break
  the profile); drag within a parent to reorder.
- Draw a relationship by dragging from an area's connection handle to another area; pick its kind
  from the profile.
- Inspector edits notes, kind, tags, properties (typed editors from the profile) and evidence. The
  "Attach evidence" action calls back to the host's picker, as today.
- Editing can be switched off per model (`readOnly`, e.g. labs system models) and the controls
  disappear, not grey out.

### 7.4 Theming and chrome: no dependency on craggy-labs

Labs reads its tokens at run time from `assets/theme.yaml` through `ThemeScope`, governed by
`ui/theme.md`; craggy-code uses compile-time constants. The library can't import either. So:

- `ModelTheme` holds every token the renderers need: today's `ModelSpec` (area fills by depth,
  borders, radii, padding, gap, label chip, min area width, max columns, dot size, max dots,
  connector width, arrow size, page size, open depth), plus text styles, a categorical palette for
  relationships, and colours for added/changed/removed/lint. Provided with `ModelThemeScope`.
  `ModelTheme.fallback(Brightness)` makes the standalone app and tests work with no host.
- `ModelChrome` is a small set of builders for the pieces a host renders in its own design system:
  button, icon button, chip, search field, dialog/inspector shell, tooltip. The library ships
  `ModelChrome.material()`. Labs supplies `ModelChrome` built from `CraggyButton`,
  `CraggySearchField`, `showCraggyContentDialog` and so on, and builds `ModelTheme` from its
  `theme.model` spec, so the board keeps looking exactly as theme.md §5.17 specifies.
- Motion respects the host's reduced-motion setting, through a duration callback in `ModelTheme`
  (labs passes `craggyDuration`).

### 7.5 Host hooks

```dart
ModelWorkspace(
  controller: c,
  theme: modelTheme, chrome: craggyChrome,
  renderers: const [BlocksRenderer(), OutlineRenderer(), GraphRenderer()],
  onEvidence: (ref) => openArtifact(ref.id),          // as today
  onAttachEvidence: (element) => pickArtifacts(...),  // as today's onAttach
  onOpenLink: (link) => openModel(link.model),         // replaces openable/onOpen
  overlays: [findingsOverlay],                         // §7.5
  onSave: (ops, result) => source.save(...),
)
```

**Overlays** are host data drawn on the model without being stored in it: a badge, a colour band
or a heat value per node id, with a legend. Labs uses them for things the model doesn't own, such
as open findings per area, gate verdicts, or coverage from the latest run. This is the main new
feature for labs: the model becomes the map that the rest of the lab's data is shown on.

### 7.6 Web and desktop

- No `dart:io` outside `FileModelSource`'s IO half (conditional import); the package builds for
  web with `flutter build web` in CI.
- Large models: the blocks renderer keeps today's paging ("Show more areas"); graph and matrix
  draw with `CustomPainter` and cull to the viewport; outline uses lazy lists.
- Export from the UI: PNG via `RepaintBoundary`, plus the Dart-side Mermaid/Markdown exports (or
  the host's `.export` capability for SVG/DOT).

### 7.7 `apps/modeller`

A small Flutter app for desktop and the web that uses only the library: open/save files, new from
template or import, every renderer, the editor, a profile picker. It is the gallery, the manual
test bed and the screenshot source for docs, and it gives the library a second real consumer.
It is deliberately thin; if it starts growing features, they belong in the package.

## 8. Moving craggy-labs onto it

| Labs today | After |
| --- | --- |
| `features/intel/model.go` | **Deleted.** `intel` imports `modelling-services/model` |
| `features/intel/models.go` | Becomes the labs `modelcap.Store`: lab-run storage, producer identity, system-model read-only rule, evidence refs must be lab artifacts. Keeps its lineage behaviour |
| `intelcap/caps_models.go` | **Deleted.** `assemble.go` registers `modelcap.Capabilities(...)` with the labs store and the existing `models` prefix, so cap names don't change. New: `models.apply`, `models.diff`, `models.lint`, `models.export` |
| `pack.go` `Board` | Becomes a `model.Model` (template without evidence); no second shape |
| `ui/lib/client/models.dart` `ModelBoard*` | **Deleted.** The client returns `modelling` `Model`s |
| `ui/lib/models/model_board_view.dart` | **Deleted.** Diff comes from the controller's `base` |
| `ui/lib/design_system/model_view.dart` | **Deleted.** Labs adds `ui/lib/models/model_chrome.dart` (`ModelChrome` + `ModelTheme` from `ThemeSpec`) and `labs_model_source.dart` |
| `ModelSpec` in `theme_spec.dart` | Stays as labs' token source (theme.yaml), mapped into `ModelTheme` |
| Dev actions `models.*`, `intel.board`, `intel.attach` | Kept, and `models.view` (`renderer`), `models.edit` (ops JSON) added; the dump publishes controller state |

The labs cutover is behaviour-preserving first (same caps, same board, same tests:
`models_page_test`, `intel_page_test`, `cmd/labsd/models_test.go`, `features/intel/models_test.go`),
then new features land behind it.

### Dependencies

- Go: `go.work` above `C:\Code\Craggy` gains `./modelling-services` while developing; labs requires
  a tagged version for `GOWORK=off` checks, as with every other service.
- Dart: labs' `pubspec.yaml` depends on `modelling_flutter` by git URL and tag; an **uncommitted**
  `pubspec_overrides.yaml` points at the local path while developing. That mirrors the uncommitted
  `go.work` rule.

## 9. Phases

Each phase ends with its checks run and passing; later phases don't start early.

| Phase | Delivers | Exit |
| --- | --- | --- |
| **0. Scaffold** | Repo, AGENTS.md, README, `arch_test.go`, `schema/` v1 + v2, first conformance vectors (from today's labs test cases) | `go test ./...`, schema validates every vector |
| **1. Go core** | `model`, `diff`, `edit`, `query.Lint` | All vectors pass; labs `intel` uses `model` and deletes `model.go`; labs checks pass with v1 artifacts still readable |
| **2. Dart core** | `modelling` package | Same vectors pass under `dart test`; labs client returns `Model` and deletes `ModelBoard*` |
| **3. Blocks renderer** | Controller, `ModelTheme`, `ModelChrome`, blocks renderer at parity, diff mode with removed ghosts, state kept across revisions | Labs deletes `model_view.dart` and `model_board_view.dart`; `flutter test` and in-process screenshots match theme.md §9; `flutter build web` succeeds for the package |
| **4. modelcap** | Store port, `apply`/`diff`/`lint`/`export` (Mermaid, outline), labs store | Labs registers modelcap; agent edit via `models.apply` covered by a labsd test |
| **5. Editor + Modelling app** | Editing ops in blocks + outline, inspector editing, undo/redo, file source (desktop + web), new-from-template/import | Modelling app runs on Windows and Chrome; widget tests drive every edit gesture |
| **6. More renderers** | Graph, matrix, table; DOT/SVG/CSV export | Each renderer has widget tests and a gallery page |
| **7. Typed models** | Profiles as a bundle kind, profile-aware lint and editor, overlays in labs (findings per area), cross-model links | A profile ships with an intel pack; labs shows findings on a board |

Phases 1–3 are the extraction (labs gets simpler, nothing new for users except removed-element
ghosts and stable view state). Phases 4–7 are the new features, in the order that gives labs the
most: agents editing cheaply (4), people editing at all (5), seeing models differently (6), and
modelling with types and overlays (7).

## 10. Decisions to confirm

1. **Both Go and Dart cores**, kept equal by shared vectors (recommended), rather than a Go-only
   core with a thin Dart client. Dart-only server ops would mean a round trip per keystroke.
2. **Upgrade v1 on read** for immutable stored revisions (recommended), rather than a one-off job
   that writes a v2 revision of every existing model.
3. **Evidence `ref` with a scheme**, so the library isn't lab-specific. Labs only uses `artifact`.
4. **Views live in the document** (shared and versioned), rather than per-user host settings.
   Per-user state (current selection, scroll) stays in the controller and is never stored.
5. **Profiles in phase 7**, not earlier. Free-form models cover everything labs does now.
6. **Name and visibility**: `github.com/craggy-io/modelling-services`, public like the other
   services (labs stays private). The British spelling matches the folder name.

## 11. As built

The decisions in §10 were taken as recommended. Changes from the proposal:

- **`undirected` instead of `directed`.** Edges carry `undirected: true` when they have no
  direction, so the default (directed) is the omitted value and a pointer-to-bool is not needed.
- **No `edit.FromDiff`.** Nothing needed operations from a change set: the editor sends the ops it
  recorded, and agents send ops or a whole document.
- **Operation indexes are positions in the `nodes`/`edges`/`views` lists**, not sibling indexes,
  so every inverse is exact (canonical bytes) and undo restores order too.
- **Evidence ids are optional on input** and filled on decode, so agents can cite without inventing
  ids.
- **Dart has no DOT, CSV or SVG export**; the modeller app writes Mermaid and outline text and a
  PNG from the renderer, and hosts with a backend call `<prefix>.export`.
- **The Flutter package lives at `clients/flutter/modelling_flutter`** beside the pure-Dart
  `clients/dart/modelling`.
- **Intel pack boards keep their authoring shape** (`Board` in pack YAML, with per-node topics and
  derived edge ids). They are converted to a version 2 model when seeded; a node that drills into a
  topic gets `link: {model: "intel-topic:<path>"}`.
- **Graph positions are a box's top-left in drawing coordinates.** Dragging writes the active view (a new
  `layout` view when none is active) through `ModelController.setPositions`; a positioned area's contents
  move with it and containing boxes grow to enclose it. No edge bundling by kind yet.
- **Graph and matrix PNG export captures what is in view**, since both cull to the viewport.
- **The modeller app's dirty prompt covers New, templates, Import and Open**, not closing the window or
  tab (that needs a window plugin on desktop and `beforeunload` on the web).
- **Area sizes are view data.** A view's `sizes` maps a node id to `{w, h}`: `w` in tenths of the
  parent's content width (1–10), `h` in fixed rows (1–20), either omitted for auto. They are layout, not
  content, so they live beside `positions` and change through `view.put` (`ModelController.setSizes`).
  `Validate` checks the key is an id and the values are in range (`view.size`); a size for an id that no
  longer exists is a `view.stale` lint finding, as positions are, so deleting a sized area leaves the
  model valid.
- **The grid layout is a blocks mode, off by default** (`BlocksRenderer(grid: true)`), so craggy-labs'
  board is unchanged. `ModelEditor` is a new shell beside `ModelWorkspace`, which labs keeps using.
