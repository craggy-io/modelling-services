# The model format

A model is one JSON document: `format` `"craggy.model"`, `version` `2`. The schema is
[schema/model.v2.schema.json](../schema/model.v2.schema.json); this page explains it. Go:
`model`. Dart: `package:modelling`.

```jsonc
{
  "format": "craggy.model", "version": 2,
  "title": "Payment app", "subject": "com.example.pay 4.2.1",
  "notes": "optional", "profile": "android-app@1", "tags": ["android"],
  "nodes": [
    {"id": "app", "label": "Application", "kind": "app"},
    {"id": "net", "label": "Network layer", "parent": "app", "kind": "component",
     "notes": "OkHttp with pinning.", "tags": ["attack-surface"],
     "properties": {"language": "kotlin", "exported": false},
     "evidence": [{"id": "ev1", "caption": "Pinner config",
                   "ref": {"scheme": "artifact", "id": "a1", "selector": "/res/xml/nsc.xml"}}],
     "link": {"model": "m-net", "node": "root"}}
  ],
  "edges": [
    {"id": "e1", "from": "ui", "to": "net", "label": "calls", "kind": "calls",
     "undirected": false, "notes": "", "properties": {}, "evidence": []}
  ],
  "views": [{"id": "overview", "title": "Overview", "renderer": "blocks", "collapsed": ["net"]}]
}
```

## Elements

| Field | Rule |
| --- | --- |
| ids (node, edge, evidence, view, kind) | `^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`; node ids unique, edge ids unique, evidence ids unique within their element, view ids unique |
| `label` | required, not blank |
| `parent` | another node's id, or absent for top level. Containment is acyclic and is never implied by an edge |
| `kind` | optional; a profile's node or edge kind |
| `tags` | non-empty strings, no repeats |
| `properties` | up to 32 per element; keys `^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$`; values string (≤ 1 KiB), number or bool only |
| `evidence` | `caption` and `ref`; `id` is filled on decode when absent (`ev1`, `ev2`, … skipping used ids) |
| `ref.scheme` | how the host resolves `ref.id`: `artifact`, `url`, `file`, or a host scheme (`^[a-z][a-z0-9+.-]{0,31}$`) |
| `ref.selector` | a place inside the cited thing; descriptive, never resolved |
| `link` | the node stands for another model (`model`, resolved by the host) and optionally one of its nodes |
| `undirected` | edges are directed from `from` to `to` unless set |

## Views

A view is a saved way of looking at the model: `renderer` (`blocks`, `graph`, `outline`,
`matrix`, `table`, or a host renderer), optional `root` (drill-in area), `collapsed` area ids,
`filter` (`kinds`, `tags`, `text`, `changedOnly`), `positions` (graph renderer: node id →
`[x, y]`) and renderer `options`. Views never change what the model says: diff ignores them unless
asked, and they may name nodes that no longer exist (lint reports `view.stale`).

## Bounds

| Limit | Default |
| --- | --- |
| Encoded size | 512 KiB |
| Nodes / edges | 1,000 / 2,000 |
| Distinct evidence refs | 128 |
| Containment depth | 32 |
| Properties per element / string value | 32 / 1 KiB |
| Views | 32 |

`model.Limits` (Go) and `Limits` (Dart) tighten them; zero fields take the default.

## Validation issue codes

`Validate` reports every issue, in document order, each with a stable code:

`format`, `version`, `title`, `subject`, `size`, `bounds.nodes`, `bounds.edges`, `bounds.refs`,
`bounds.depth`, `bounds.properties`, `bounds.views`, `id.invalid`, `id.duplicate`, `label.empty`,
`kind.invalid`, `tag.invalid`, `property.key`, `property.value`, `evidence.id`,
`evidence.caption`, `evidence.ref`, `link.model`, `parent.self`, `parent.missing`,
`parent.cycle`, `edge.endpoint`, `view.id`, `view.renderer`.

## Encoding and decoding

- `Decode` is strict: unknown fields, trailing content and unknown versions are errors. Missing
  `nodes`/`edges` decode as empty. Version 1 is upgraded (see [migration.md](migration.md)).
- `Encode` writes canonical JSON (foundation-kit `canonjson`: sorted keys, exact decimals, Go's
  string escaping), so equal models encode to equal bytes and `Equal` compares encodings. Dart's
  encoder produces the same bytes.

## Profiles

A profile ([schema](../schema/profile.v1.schema.json)) declares node kinds (with the kinds
allowed directly inside each), edge kinds (with allowed end kinds) and typed properties
(`string`, `number`, `bool`, optional `enum`, `required`), and whether every element needs a kind.
A model names its profile as `<id>@<version>`; the host resolves it (in a bundle, kind
`craggy.model-profile@1`). Profile violations are lint findings, not decode errors, so a model
being built is never refused for a missing kind.
