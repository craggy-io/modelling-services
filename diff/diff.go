// Package diff compares two revisions of a model: which nodes and edges were
// added, removed or changed, and which fields changed. Element order and,
// unless asked for, views are not changes.
package diff

import (
	"bytes"
	"encoding/json"
	"sort"

	"github.com/craggy-io/foundation-kit/canonjson"

	"github.com/craggy-io/modelling-services/model"
)

// Kind says how an element differs between base and revision.
type Kind string

const (
	Added   Kind = "added"
	Removed Kind = "removed"
	Changed Kind = "changed"
)

// FieldChange is one field's old and new value. From is absent for a value
// that was not set, To for one that was cleared. Fields are named as in the
// document; one property is "properties.<key>".
type FieldChange struct {
	Field string `json:"field"`
	From  any    `json:"from,omitempty"`
	To    any    `json:"to,omitempty"`
}

// Change is one element that differs. Fields are set only for Changed.
type Change struct {
	ID     string        `json:"id"`
	Kind   Kind          `json:"change"`
	Fields []FieldChange `json:"fields,omitempty"`
}

// ChangeSet is everything that differs, elements sorted by id.
type ChangeSet struct {
	Model []FieldChange `json:"model,omitempty"`
	Nodes []Change      `json:"nodes,omitempty"`
	Edges []Change      `json:"edges,omitempty"`
}

// Options tune Compare.
type Options struct {
	// Views counts changes to saved views as a model change ("views").
	Views bool
}

// Compare is the change set from base to rev.
func Compare(base, rev model.Model, o Options) ChangeSet {
	var cs ChangeSet
	f := fields{}
	f.add("title", base.Title, rev.Title)
	f.add("subject", base.Subject, rev.Subject)
	f.add("notes", base.Notes, rev.Notes)
	f.add("profile", base.Profile, rev.Profile)
	f.add("tags", list(base.Tags), list(rev.Tags))
	if o.Views {
		f.add("views", list(base.Views), list(rev.Views))
	}
	cs.Model = f

	baseNodes := map[string]model.Node{}
	for _, n := range base.Nodes {
		baseNodes[n.ID] = n
	}
	revNodes := map[string]model.Node{}
	for _, n := range rev.Nodes {
		revNodes[n.ID] = n
		b, ok := baseNodes[n.ID]
		if !ok {
			cs.Nodes = append(cs.Nodes, Change{ID: n.ID, Kind: Added})
		} else if fs := nodeFields(b, n); len(fs) > 0 {
			cs.Nodes = append(cs.Nodes, Change{ID: n.ID, Kind: Changed, Fields: fs})
		}
	}
	for _, n := range base.Nodes {
		if _, ok := revNodes[n.ID]; !ok {
			cs.Nodes = append(cs.Nodes, Change{ID: n.ID, Kind: Removed})
		}
	}

	baseEdges := map[string]model.Edge{}
	for _, e := range base.Edges {
		baseEdges[e.ID] = e
	}
	revEdges := map[string]model.Edge{}
	for _, e := range rev.Edges {
		revEdges[e.ID] = e
		b, ok := baseEdges[e.ID]
		if !ok {
			cs.Edges = append(cs.Edges, Change{ID: e.ID, Kind: Added})
		} else if fs := edgeFields(b, e); len(fs) > 0 {
			cs.Edges = append(cs.Edges, Change{ID: e.ID, Kind: Changed, Fields: fs})
		}
	}
	for _, e := range base.Edges {
		if _, ok := revEdges[e.ID]; !ok {
			cs.Edges = append(cs.Edges, Change{ID: e.ID, Kind: Removed})
		}
	}
	byID := func(c []Change) {
		sort.Slice(c, func(i, j int) bool { return c[i].ID < c[j].ID })
	}
	byID(cs.Nodes)
	byID(cs.Edges)
	return cs
}

// Empty reports whether nothing differs.
func (cs ChangeSet) Empty() bool {
	return len(cs.Model) == 0 && len(cs.Nodes) == 0 && len(cs.Edges) == 0
}

// Node is the change to node id, if it differs.
func (cs ChangeSet) Node(id string) (Change, bool) { return find(cs.Nodes, id) }

// Edge is the change to edge id, if it differs.
func (cs ChangeSet) Edge(id string) (Change, bool) { return find(cs.Edges, id) }

// Count is the number of changed elements (nodes and edges).
func (cs ChangeSet) Count() int { return len(cs.Nodes) + len(cs.Edges) }

func find(changes []Change, id string) (Change, bool) {
	i := sort.Search(len(changes), func(i int) bool { return changes[i].ID >= id })
	if i < len(changes) && changes[i].ID == id {
		return changes[i], true
	}
	return Change{}, false
}

func nodeFields(a, b model.Node) []FieldChange {
	f := fields{}
	f.add("label", a.Label, b.Label)
	f.add("parent", a.Parent, b.Parent)
	f.add("kind", a.Kind, b.Kind)
	f.add("notes", a.Notes, b.Notes)
	f.add("tags", list(a.Tags), list(b.Tags))
	f.add("link", a.Link, b.Link)
	f.properties(a.Properties, b.Properties)
	f.add("evidence", list(a.Evidence), list(b.Evidence))
	return f
}

func edgeFields(a, b model.Edge) []FieldChange {
	f := fields{}
	f.add("label", a.Label, b.Label)
	f.add("from", a.From, b.From)
	f.add("to", a.To, b.To)
	f.add("kind", a.Kind, b.Kind)
	f.add("undirected", a.Undirected, b.Undirected)
	f.add("notes", a.Notes, b.Notes)
	f.add("tags", list(a.Tags), list(b.Tags))
	f.properties(a.Properties, b.Properties)
	f.add("evidence", list(a.Evidence), list(b.Evidence))
	return f
}

type fields []FieldChange

// add records name when from and to encode differently. Nil pointers are
// recorded as absent.
func (f *fields) add(name string, from, to any) {
	if same(from, to) {
		return
	}
	*f = append(*f, FieldChange{Field: name, From: absentNil(from), To: absentNil(to)})
}

func (f *fields) properties(a, b model.Properties) {
	keys := map[string]bool{}
	for k := range a {
		keys[k] = true
	}
	for k := range b {
		keys[k] = true
	}
	for _, k := range model.SortedKeys(keys) {
		f.add("properties."+k, a[k], b[k])
	}
}

func list[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

func absentNil(v any) any {
	if l, ok := v.(*model.Link); ok && l == nil {
		return nil
	}
	return v
}

func same(a, b any) bool {
	x, err1 := canonical(absentNil(a))
	y, err2 := canonical(absentNil(b))
	return err1 == nil && err2 == nil && bytes.Equal(x, y)
}

func canonical(v any) ([]byte, error) {
	if v == nil {
		return []byte("null"), nil
	}
	raw, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return canonjson.Normalize(raw)
}
