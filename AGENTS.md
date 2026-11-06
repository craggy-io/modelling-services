# Modelling Services: coding-agent guide

Use this guide when editing this repository or integrating its Go module,
`github.com/craggy-io/modelling-services`, or its Dart packages. Consumers should give this guide
to their coding agent explicitly; installing a dependency doesn't mean its AGENTS.md gets read.

Design authority: [docs/design.md](docs/design.md). Use foundation-kit's ADR-0001 vocabulary
(bundle, kind, contribution, definition, catalog, capability).

## Choose the owning package

| Need | Go | Dart |
| --- | --- | --- |
| Read, write, validate a model; index it; profiles | `model` | `modelling` (`model`, `codec`, `validate`, `index`, `profile`) |
| Change a model | `edit` (`Apply`, `Op`) | `modelling` (`apply`, `Op`, `EditHistory`) |
| Compare revisions | `diff` | `modelling` (`compare`) |
| Search, neighbours, paths, impact, lint | `query` | `modelling` |
| Mermaid / outline text | `export` | `modelling` |
| DOT, CSV, SVG | `export` | — (call the host's `<prefix>.export`) |
| Serve models as capabilities | `modelcap` | — |
| Ship profiles and templates in bundles | `kinds` | — |
| Render, edit, theme, load and save in Flutter | — | `modelling_flutter` |

## Layers

Imports point down only (enforced by `arch_test.go`):

| Layer | Go | May import |
| --- | --- | --- |
| Format | `model` | standard library, `foundation-kit/canonjson` |
| Engines | `diff`, `edit`, `query`, `export` | `model` |
| Host adapters | `modelcap` (capability-services), `kinds` (foundation-kit bundle/kind) | format and engines |

Engines are transport-free and never import each other. Only `modelcap` imports
capability-services; only `kinds` imports foundation-kit's bundle packages. Nothing here imports
craggy-labs or any other application.

In Dart, `modelling` has no Flutter dependency and no runtime dependencies; `modelling_flutter`
imports `modelling` and Flutter only, never a host's design system: hosts theme it with
`ModelTheme` and supply widgets through `ModelChrome`.

## Rules

- **The conformance vectors are the contract.** Go and Dart must give identical results for every
  case in `conformance/`. A behaviour change lands as a vector first, then in both languages, in
  one change. Regenerate `conformance/expected/` with `go test ./conformance -update` and review
  the diff; never update expectations to hide a regression.
- **Format changes are versioned.** Decoders read version N-1 and N and write N. Add the old
  schema to `schema/` and a `migrate` vector. Never write an old version.
- **Semantics vs presentation.** Views, positions and collapsed state are views; diff ignores them
  by default. Don't put presentation in nodes or edges.
- **Provenance stays outside the document.** Who stored a revision and what it was based on are the
  host's lineage.
- **Error codes are stable.** Validation issue codes, op error codes and lint rule ids are shared
  with Dart and with callers; add new ones, don't rename.
- **Simple and linear.** No speculative options or interfaces; delete, don't deprecate; non-test
  files stay under 500 lines.
- **Text output is byte-exact.** Mermaid and outline output must not change without updating the
  vectors, because Dart and saved files depend on it.

## Checks

```bash
gofmt -l . && go vet ./... && go test ./...
cd clients/dart/modelling && dart format --set-exit-if-changed . && dart analyze && dart test
cd clients/flutter/modelling_flutter && flutter analyze && flutter test
cd apps/modeller && flutter analyze && flutter test && flutter build web
```

Report exactly what you ran. An unrun check is not a pass.
