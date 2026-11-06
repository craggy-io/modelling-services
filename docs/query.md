# Query and lint

Everything takes a `model.Index` (Dart `ModelIndex`) and returns ids in a deterministic order.

| Function | Returns |
| --- | --- |
| `Search(ix, filter)` | node ids in document order whose id, label, notes, tags or property values contain `filter.text` (case-insensitive), with any of `filter.kinds` and any of `filter.tags` |
| `Neighbours(ix, id, out\|in\|both, depth)` | nodes within `depth` edges, breadth first, each level in edge order; undirected edges count both ways |
| `Paths(ix, from, to, maxLen, maxPaths)` | simple paths as edge-id lists, following edges forward (undirected either way), depth first in edge order |
| `Impact(ix, id)` | every node reachable forward from the area or anything inside it, excluding the area and its contents, in document order |
| `ix.Ancestors`, `ix.Descendants`, `ix.Children`, `ix.Touching`, `ix.Depth` | containment and edge lookups |

## Lint

`Lint(ix, profile)` returns findings `{rule, element, severity, message}` in document order:
nodes, then edges, then views; per element in the order below. Lint never fails.

| Rule | Severity | When |
| --- | --- | --- |
| `label.duplicate-sibling` | warning | two areas in the same parent share a label (case and spacing ignored); reported on the later one |
| `evidence.missing` | info | a node or edge cites no evidence |
| `edge.duplicate` | warning | an edge repeats an earlier one's ends, label and kind |
| `edge.ancestor` | warning | an edge joins an area to one that contains it |
| `profile.kind-required` | error | the profile requires kinds and the element has none |
| `profile.kind-unknown` | error | the element's kind is not in the profile |
| `profile.child` | error | the parent's kind does not allow this kind inside it |
| `profile.edge-ends` | error | the edge kind does not allow these end kinds |
| `profile.property-required` | error | a required property is missing |
| `profile.property-unknown` | warning | a property the kind does not declare |
| `profile.property-type` | error | a property has the wrong type |
| `profile.property-enum` | error | a property is not one of the allowed values |
| `view.stale` | info | a view names nodes that no longer exist |
