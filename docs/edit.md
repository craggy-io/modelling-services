# Edit operations

Every change, from a UI gesture to an agent's tool call, is a list of operations. Go:
`edit.Apply(m, ops, limits) (result, inverse, error)`. Dart: `apply(model, ops)`.

- **Atomic.** Operations run in order on a copy; any failure leaves the model unchanged. The result
  is validated once, after the last operation, so intermediate states may be invalid (add a node,
  then the edge to it, in either order).
- **Invertible.** The returned inverse, applied to the result, gives back the original exactly
  (canonical bytes), including element order. Undo/redo is applying inverses.
- **Id-addressed.** Operations name elements by id, never by position, so a batch still means the
  same thing against a newer revision as long as its targets exist.

## Operations

| `op` | Fields | Notes |
| --- | --- | --- |
| `node.add` | `node`, `index?` | `index` is the position in `nodes`; absent appends |
| `node.remove` | `id`, `cascade?` | refused (`op.not-empty`) when the node has children or edges, unless `cascade` removes them too |
| `node.move` | `id`, `parent`, `index?` | `parent` absent or `""` is top level; absent `index` keeps the position |
| `node.set` | `id`, `fields` | `label`, `kind`, `notes`, `tags`, `link`; JSON `null` clears |
| `edge.add` | `edge`, `index?` | |
| `edge.remove` | `id` | |
| `edge.set` | `id`, `fields` | `label`, `from`, `to`, `kind`, `undirected`, `notes`, `tags` |
| `prop.set` | `target` (`node`/`edge`), `id`, `key`, `value` | value is a string, number or bool |
| `prop.unset` | `target`, `id`, `key` | a missing key is a no-op |
| `evidence.add` | `target`, `id`, `evidence`, `index?` | a ref the element already cites is skipped; a missing evidence id is filled |
| `evidence.remove` | `target`, `id`, `evidenceId` | |
| `model.set` | `fields` | `title`, `subject`, `notes`, `profile`, `tags` |
| `view.put` | `view`, `index?` | replaces the view with the same id in place, else inserts |
| `view.remove` | `id` | |

Op JSON omits empty strings, `false` and absent values; `index` is written whenever it is set,
including `0`.

## Errors

`*edit.Error` (Dart `EditException`) carries `index` (the failing operation, or `-1` when the
result failed validation), a stable `code` and, for `-1`, the validation `issues`:

`op.unknown`, `op.missing` (target id not found), `op.exists` (id already used), `op.not-empty`,
`op.field` (missing or bad argument, unknown or bad field), `op.index` (out of range), or the first
validation issue code (e.g. `parent.cycle`, `edge.endpoint`).

## Edit history (Dart)

`EditHistory` records each applied step and its inverse: `undo`, `redo`, `canUndo`, `canRedo`,
`pendingOps` (what changed since `markSaved`, for a host save through `<prefix>.apply`), and merges
consecutive single-field `node.set`/`edge.set` steps on the same element, so typing a label is one
undo step.
