# Import and export

| Format | Go | Dart | Direction |
| --- | --- | --- | --- |
| Mermaid flowchart | `export.Mermaid`, `export.ParseMermaid` | `toMermaid`, `parseMermaid` | both |
| Markdown outline | `export.Outline`, `export.ParseOutline` | `toOutline`, `parseOutline` | both |
| CSV (nodes table, edges table) | `export.CSV`, `export.ParseCSV` | — | both |
| Graphviz DOT | `export.DOT` | — | out |
| Static SVG (nested blocks) | `export.SVG` | — | out |

Mermaid and outline output is byte-identical between Go and Dart (pinned by
`conformance/export.json`). Imports are not validated; validate the result. Imported ids come
from the source when they are valid, else from `Slug(label)` (lower case, runs of other characters
as `-`, at most 64 characters, `node` when empty), made unique with `-2`, `-3`, …. Edge ids
default to `<from>--<to>`.

## Mermaid

Output:

```text
---
title: Payment app
---
flowchart LR
  subgraph n_app["Application"]
    n_ui["UI layer"]
  end
  n_server["Payment server"]
  n_ui -->|"calls"| n_server
  n_a ---|"shares data with"| n_b
```

Areas with children are subgraphs, leaves are nodes, ids get an `n_` prefix (so none collides with
a Mermaid keyword), `"` in text is `#quot;`, whitespace runs collapse to one space.

Input: front-matter `title:`; `flowchart`/`graph` headers; `subgraph id`, `subgraph id[label]` or
`subgraph id["label"]` … `end`; nodes `id`, `id[label]`, `id["label"]`, `id(label)`,
`id((label))`, `id[[label]]`, `id[(label)]`, `id{label}`; single edges `-->`, `---` (undirected),
`-.->`, `==>`, `-- label -->`, with an optional `|label|`. A bare node listed inside a subgraph
moves into it. `classDef`, `class`, `style`, `click`, `linkStyle`, `direction` and `%%` lines
are ignored. Anything else is an error naming the line. An `n_` prefix is stripped. Edges without
a label are labelled `relates to`.

## Outline

```markdown
# Payment app

com.example.pay 4.2.1

Notes paragraph.

- **Application** `app`
  - **Network layer** `net`: OkHttp with pinning.
- **Payment server** `server`

## Relationships

- `net` -> `server`: talks to `e2`
- `ui` -- `native`: shares data with `e4`
```

Input reads the same shape, and hand-written variants: the first paragraph after the title is the
subject and the rest are notes; list items may be plain labels (`- Front end`) with an optional
`` `id` `` and `: notes`; two spaces of indent per level; under `## Relationships`, ends may be
ids in backticks or labels (matched case-insensitively), `->` directed or `--` undirected, with
an optional trailing `` `id` ``.

## CSV

Nodes columns `id,label,parent,kind,notes,tags,properties`; edges columns
`id,from,to,label,kind,undirected,notes,tags,properties`. Tags join with `;`; properties are one
canonical JSON object. Columns are found by header name; evidence, links and views are not written.
