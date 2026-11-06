# modelcap

`modelcap` serves models as capability-services capabilities over a store the host implements.

```go
svc := modelcap.New(modelcap.Deps[Summary]{
    Store:    store,              // modelcap.Store[Summary]
    Prefix:   "models",
    Codes:    registry.Codes{ErrNotFound: registry.NotFound, ErrDenied: registry.Denied},
    Profiles: resolveProfile,     // optional: Model.Profile -> *model.Profile
    Tags:     []string{"agent", "lab-scoped"},
})
reg.Add(svc.Capabilities()...)
```

```go
type Store[S any] interface {
    List(ctx context.Context, scope string) ([]S, error)
    Read(ctx context.Context, scope, id string) (model.Model, error)
    Create(ctx context.Context, scope string, m model.Model, basedOn string) (Saved, error)
    Revise(ctx context.Context, scope, id string, m model.Model, how string) (Saved, error) // how: update | apply | attach
}
```

The host owns storage, identity and policy: what a scope is, which models are read-only (refuse in
`Revise`), what a `ref` must resolve to (check in `Create`/`Revise`), and lineage. `S` is the host's
summary type, returned unchanged by `.list`. modelcap validates every document before it reaches
the store and re-validates on read.

Every input addresses the scope through `id`, so a host middleware can confine callers to one scope.

| Capability | Input | Output |
| --- | --- | --- |
| `.list` | `id`, page | `models` (`[]S`), `next` |
| `.read` | `id`, `model`, `format` `json`\|`outline`\|`mermaid` | `id`, `model`, `document` or `text` |
| `.create` | `id`, `document` or `import` {`format` mermaid\|outline\|csv, `source`, `edges`, `title`}, `basedOn` | write output |
| `.update` | `id`, `model`, `document` | write output |
| `.apply` | `id`, `model`, `ops` | write output + `inverse` |
| `.attach` | `id`, `model`, `node`\|`edge`, `evidence` | write output (no new revision when nothing is new) |
| `.diff` | `id`, `base`, `model`, `views` | `changes` |
| `.lint` | `id`, `model`, `all` | `findings` |
| `.query` | `id`, `model`, `fn` neighbours\|paths\|impact\|search and its arguments | `nodes` or `paths` |
| `.export` | `id`, `model`, `format` mermaid\|dot\|outline\|svg\|csv | `text` (+ `edges` for csv) |

The write output is `{id, model, receipt, document, lint}`: the stored revision's id, the host's
receipt (a run id, say), the stored document and its lint errors and warnings.

Errors: `model.ErrInvalid` (validation, edit and import failures) maps to `invalid`; everything
else goes through the host's `Codes`.

## Stateless tools

`modelcap.Tools` serves the same engines over documents the caller holds: no store, scope or
profile resolver. Each takes the whole document (and, for lint, an optional profile) and returns
what it computed. `cmd/modelling-mcp` serves them to agents; see [mcp](mcp.md).

```go
tools := modelcap.NewTools(modelcap.ToolDeps{Prefix: "model", Editor: "https://models.craggy.io/"})
reg.Add(tools.Capabilities()...) // model.check, .import, .apply, .diff, .query, .export, .open
```

`modelcap.Link(editor, m)` builds the modeller link `model.open` returns.
