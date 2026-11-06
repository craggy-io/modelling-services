# Dart and Flutter

Two packages and one app. The API reference for each lives in its own README; this page is how a host
puts them together.

| Path | What | Imports |
| --- | --- | --- |
| `clients/dart/modelling` | Pure Dart: format types, codec, validation, index, diff, edit ops + `EditHistory`, query, lint, Mermaid/outline text | Dart only |
| `clients/flutter/modelling_flutter` | `ModelController`, `ModelWorkspace`, renderers, inspector and editor, `ModelTheme`/`ModelChrome`, model sources ([README](../clients/flutter/modelling_flutter/README.md)) | Flutter, `modelling`, `file_selector`, `package:web` |
| `apps/modeller` | Standalone editor, gallery and test bed for Windows and the web | both packages |

The Dart core passes the same conformance vectors as Go (`conformance/`), so a document, diff, edit or
Mermaid/outline export is byte-identical on either side. DOT, SVG and CSV are Go only; a Flutter host
asks its server's `.export` capability for those.

## Depending on it

```yaml
# pubspec.yaml
dependencies:
  modelling:
    git: {url: https://github.com/craggy-io/modelling-services.git, path: clients/dart/modelling, ref: <tag>}
  modelling_flutter:
    git: {url: https://github.com/craggy-io/modelling-services.git, path: clients/flutter/modelling_flutter, ref: <tag>}
```

While developing against a local checkout, add an **uncommitted** `pubspec_overrides.yaml` with `path:`
dependencies, as with the uncommitted `go.work` on the Go side.

## Hosting a model

1. **Load** a model through a `ModelSource`. `read(id)` gives `LoadedModel{model, summary, editable, base}`.
   The `base` (the previous revision, say) turns on diff mode in every renderer. `MemoryModelSource` and
   `FileModelSource` (desktop files, web download/upload) ship with the package; a server-backed host
   writes its own and saves through `.apply` with the controller's `pendingOps`.
2. **Control**: one `ModelController(model, base:, profile:, readOnly:)` per open model. It owns the
   document, the edit history and all view state (selection, drill trail, folds, search, renderer).
   Renderers keep none, so switching renderer keeps the user's place. A new revision from elsewhere
   goes through `controller.replace(next, base:)`.
3. **Show**: `ModelWorkspace(controller:, renderers:, onEvidence:, onAttachEvidence:, onOpenLink:, onSave:)`.
   The hooks are the host's: open an evidence ref, pick evidence to cite, follow a `link` to another model,
   persist edits.
4. **Overlay** host data that the model doesn't own (findings, coverage, verdicts) with
   `controller.overlays`: a badge, colour and value per node id plus a legend. It is never saved into the
   document.

## Renderers

| Id | Renderer | Best for |
| --- | --- | --- |
| `blocks` | `BlocksRenderer` | The default: nested areas with relationship dots and connectors |
| `outline` | `OutlineRenderer` | Narrow screens, screen readers, keyboard editing |
| `graph` | `GraphRenderer` | Seeing relationships: node-link canvas, containment boxes, layered auto layout, dragged positions saved in the view |
| `matrix` | `MatrixRenderer` | Large models, cycles and layering: node × node grid of edge counts |
| `table` | `TableRenderer` | Bulk edits of labels, kinds, tags and properties |

A saved view's `renderer` names one of these ids. A host passes only the renderers it wants. To write
another one, see "Adding a renderer" in the package README.

## Theming without a dependency on the host

The package never imports its host. The host maps its own design system in two objects:

- **`ModelTheme`**: tokens (area fills by depth, borders, radii, spacing, dots, connectors, text styles,
  relationship palette, change and lint colours, a reduced-motion hook). Build it from the host's theme;
  `ModelTheme.fallback(Brightness)` serves apps and tests with no host theme.
- **`ModelChrome`**: the few widgets that should look native to the host (buttons, chips, search field,
  menus, inspector shell, confirm dialog). Subclass `MaterialModelChrome` to swap a few, or implement
  the whole interface. Dart takes default argument values from the implementation, so restate the
  abstract defaults.

craggy-labs does this in `ui/lib/models/model_chrome.dart`. It builds `ModelTheme` from the `model:`
block of `assets/theme.yaml` (`ThemeSpec.model`) and `ModelChrome` from Craggy widgets, so the board
looks exactly as `ui/theme.md` §5.17 specifies. It sets `added` and `changed` to the same info colour
to keep a single change marker.

## Web and desktop

- `dart:io` appears only in `FileModelSource`'s IO half (a conditional import), so both packages and
  the app build with `flutter build web`.
- PNG export captures the renderer's `RepaintBoundary`. Graph and matrix cull to the viewport, so their
  PNG is what is on screen. The Mermaid, outline and JSON exports are Dart.
- On the web, `FileModelSource` saves by downloading and keeps recent files in `localStorage`. A recent
  file has to be re-opened through the picker in a new session.

## Checks

```bash
cd clients/dart/modelling && dart pub get && dart analyze && dart test
cd clients/flutter/modelling_flutter && flutter pub get && flutter analyze && flutter test
cd apps/modeller && flutter analyze && flutter test && flutter build web
```
