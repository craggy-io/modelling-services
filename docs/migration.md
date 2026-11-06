# Migration from version 1

Version 1 is the graph craggy-labs stored before this library
([schema](../schema/model.v1.schema.json)): `version: 1`, nodes and edges with evidence as
`{citation: {artifactId, selector}, caption}`.

`Decode` upgrades a version 1 document on read:

| v1 | v2 |
| --- | --- |
| `version: 1` | `format: "craggy.model"`, `version: 2` |
| `evidence[].citation.artifactId` | `evidence[].ref.id`, with `ref.scheme` `"artifact"` |
| `evidence[].citation.selector` | `evidence[].ref.selector` |
| — | `evidence[].id`: `ev1`, `ev2`, … in order |

Everything else carries over unchanged. Nothing writes version 1.

Stored revisions are immutable artifacts, so they are not rewritten: upgrade-on-read is the
migration, and the next revision of a model is stored as version 2. `conformance/migrate.json`
pins the upgrade in both languages.

## craggy-labs

The labs host moved from its own graph code to this library:

- `features/intel/model.go`, the `models.*` capability file, the Dart `ModelBoard*` client types,
  `ui/lib/models/model_board_view.dart` and `ui/lib/design_system/model_view.dart` were deleted.
- The `models.*` capabilities are `modelcap` over the labs store. Their wire contract changed: inputs
  name the lab `id` and the revision `model`; `create` takes `document`/`import`; outputs are
  `{id, model, receipt, document, lint}`. New: `models.apply`, `.diff`, `.lint`, `.query`,
  `.export`.
- Intel expected boards are seeded as version 2 models; nodes that drill into a topic carry
  `link: {model: "intel-topic:<path>"}`.
