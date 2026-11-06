# Diff

`diff.Compare(base, revision, diff.Options{Views: false})` (Dart `compare`) returns a `ChangeSet`:

```json
{
  "model": [{"field": "title", "from": "T", "to": "T2"}],
  "nodes": [
    {"id": "b", "change": "changed", "fields": [{"field": "label", "from": "B", "to": "B!"},
                                                {"field": "properties.p", "to": 1}]},
    {"id": "gone", "change": "removed"},
    {"id": "new", "change": "added"}
  ],
  "edges": [{"id": "e1", "change": "changed", "fields": [{"field": "to", "from": "b", "to": "new"}]}]
}
```

- Elements match by id. Nodes and edges are sorted by id; fields come in a fixed order: for nodes
  `label`, `parent`, `kind`, `notes`, `tags`, `link`, `properties.<key>` (keys sorted),
  `evidence`; for edges `label`, `from`, `to`, `kind`, `undirected`, `notes`, `tags`,
  `properties.<key>`, `evidence`; for the model `title`, `subject`, `notes`, `profile`, `tags`,
  and `views` when `Views` is set.
- `from` is omitted for a value that was absent (a new property, a new link), `to` for one that was
  removed. Empty strings, `false` and empty lists are values, not absences.
- Element order is not a change. Views are not a change unless asked for.

Renderers use a change set for diff mode: added and changed elements are marked, removed ones are
drawn as ghosts from the base, and the inspector lists each field's old and new value.
