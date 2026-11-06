<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/craggy-wordmark-on-dark.svg">
  <img src="docs/assets/craggy-wordmark-on-light.svg" alt="Craggy" width="300">
</picture>

# Modelling Services

Block models as data: labelled areas nested by containment, labelled relationships between them,
typed properties, cited evidence and saved views, in one versioned JSON format. Go and Dart
implement the same format and engines, proven equal by shared conformance vectors, and a Flutter
package renders and edits models on desktop and the web.

## Features

- **One format** ([format](docs/format.md)): `craggy.model` version 2, with a [JSON Schema](schema/model.v2.schema.json), canonical encoding, strict decoding, bounds, and an upgrade from the version 1 graphs craggy-labs stored.
- **Small, invertible edits** ([edit](docs/edit.md)): fourteen id-addressed operations applied all or nothing; every apply returns the operations that undo it.
- **Revision diffs** ([diff](docs/diff.md)): nodes and edges added, removed or changed, with each field's old and new value.
- **Queries and lint** ([query](docs/query.md)): search, neighbours, paths, impact, and lint rules, including checks against an optional profile (node and edge kinds, containment rules, typed properties).
- **Import and export** ([export](docs/export.md)): Mermaid and Markdown outline both ways (byte-identical in Go and Dart), CSV both ways, Graphviz DOT and static SVG out.
- **Capabilities** ([modelcap](docs/modelcap.md)): `<prefix>.list/read/create/update/apply/attach/diff/lint/query/export` over a storage port the host implements.
- **Bundle kinds** (`kinds`): ship profiles (`craggy.model-profile@1`) and template models (`craggy.model@1`) as foundation-kit bundle content.
- **Dart and Flutter** ([flutter](docs/flutter.md)): `clients/dart/modelling` (pure Dart: format, engines, edit history) and `clients/flutter/modelling_flutter` (controller, renderers, editor, theme, file sources), plus the standalone `apps/modeller`.

## Layout

| Path | What |
| --- | --- |
| `model` | Types, codec, validation, index, profiles |
| `diff`, `edit`, `query`, `export` | Engines over `model` |
| `modelcap` | capability-services registrations over a `Store` |
| `kinds` | foundation-kit bundle kinds and compilers |
| `schema/` | JSON Schemas: model v2, model v1 (read only), profile v1 |
| `conformance/` | Shared vectors; Go runs them in `conformance/`, Dart in `clients/dart/modelling/test` |
| `clients/dart/modelling` | The Dart twin of the Go engines |
| `clients/flutter/modelling_flutter` | Flutter renderers and editor |
| `apps/modeller` | Standalone Flutter app (desktop and web) |

## Quick start (Go)

```go
m, err := model.Decode(raw)                 // v1 graphs are upgraded
if err := m.Validate(model.Limits{}); err != nil { … }
next, undo, err := edit.Apply(m, []edit.Op{
    {Op: edit.NodeAdd, Node: &model.Node{ID: "db", Label: "Database"}},
}, model.Limits{})
changes := diff.Compare(m, next, diff.Options{})
fmt.Print(export.Outline(next))
```

## Checks

```bash
go vet ./... && go test ./...                         # Go, including the conformance vectors and schemas
(cd clients/dart/modelling && dart analyze && dart test)
(cd clients/flutter/modelling_flutter && flutter analyze && flutter test)
(cd apps/modeller && flutter analyze && flutter test)
```

Read [AGENTS.md](AGENTS.md) before changing anything.
