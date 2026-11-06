// Package model is the block-model format: labelled nodes nested by
// containment, labelled edges between them, typed properties, evidence
// references and saved views, as one versioned JSON document.
//
// Containment is the Parent field and is never implied by an edge. Every
// element has a stable id, so diffs, edit operations and selections match
// elements across revisions. Provenance (who stored a revision, what it was
// based on) is not part of the document.
package model

// Format is the value of every document's format field.
const Format = "craggy.model"

// Version is the format version Encode writes. Decode also reads version 1.
const Version = 2

// Model is one complete model document.
type Model struct {
	Format  string   `json:"format"`
	Version int      `json:"version"`
	Title   string   `json:"title"`
	Subject string   `json:"subject"`
	Notes   string   `json:"notes,omitempty"`
	Profile string   `json:"profile,omitempty"`
	Tags    []string `json:"tags,omitempty"`
	Nodes   []Node   `json:"nodes"`
	Edges   []Edge   `json:"edges"`
	Views   []View   `json:"views,omitempty"`
}

// Node is one area. Parent names its containing node; "" is top level.
type Node struct {
	ID         string     `json:"id"`
	Label      string     `json:"label"`
	Parent     string     `json:"parent,omitempty"`
	Kind       string     `json:"kind,omitempty"`
	Notes      string     `json:"notes,omitempty"`
	Tags       []string   `json:"tags,omitempty"`
	Properties Properties `json:"properties,omitempty"`
	Evidence   []Evidence `json:"evidence,omitempty"`
	Link       *Link      `json:"link,omitempty"`
}

// Edge is one relationship. Edges are directed from From to To unless
// Undirected is set.
type Edge struct {
	ID         string     `json:"id"`
	From       string     `json:"from"`
	To         string     `json:"to"`
	Label      string     `json:"label"`
	Kind       string     `json:"kind,omitempty"`
	Undirected bool       `json:"undirected,omitempty"`
	Notes      string     `json:"notes,omitempty"`
	Tags       []string   `json:"tags,omitempty"`
	Properties Properties `json:"properties,omitempty"`
	Evidence   []Evidence `json:"evidence,omitempty"`
}

// Properties are an element's typed values: each a string, a number or a
// bool. Decoded numbers are float64.
type Properties map[string]any

// Evidence is one captioned reference supporting a node or edge.
type Evidence struct {
	ID      string `json:"id,omitempty"` // filled on decode when absent
	Caption string `json:"caption"`
	Ref     Ref    `json:"ref"`
}

// Ref addresses the thing cited. Scheme says how a host resolves ID
// ("artifact", "url", "file" or a host-defined scheme); Selector narrows to
// a place inside it and is descriptive, never resolved by this library.
type Ref struct {
	Scheme   string `json:"scheme"`
	ID       string `json:"id"`
	Selector string `json:"selector,omitempty"`
}

// Link makes a node stand for another model (and optionally one of its
// nodes). The host resolves Model.
type Link struct {
	Model string `json:"model"`
	Node  string `json:"node,omitempty"`
}

// View is one saved way of looking at the model. Views never change what
// the model says; renderers ignore fields they don't use.
type View struct {
	ID        string                `json:"id"`
	Title     string                `json:"title,omitempty"`
	Renderer  string                `json:"renderer"`
	Root      string                `json:"root,omitempty"`
	Collapsed []string              `json:"collapsed,omitempty"`
	Filter    *Filter               `json:"filter,omitempty"`
	Positions map[string][2]float64 `json:"positions,omitempty"`
	Sizes     map[string]Size       `json:"sizes,omitempty"`
	Options   Properties            `json:"options,omitempty"`
}

// Size is a node's box in a grid layout: W tenths of its parent's content
// width (1–10) and H fixed row units (1–20). Zero is auto.
type Size struct {
	W int `json:"w,omitempty"`
	H int `json:"h,omitempty"`
}

// Filter narrows the elements shown or searched. Empty fields match all.
type Filter struct {
	Kinds       []string `json:"kinds,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Text        string   `json:"text,omitempty"`
	ChangedOnly bool     `json:"changedOnly,omitempty"`
}

// New is an empty model with the current format and version.
func New(title, subject string) Model {
	return Model{Format: Format, Version: Version, Title: title, Subject: subject, Nodes: []Node{}, Edges: []Edge{}}
}

// NodeByID is the node with id, if any.
func (m Model) NodeByID(id string) (Node, bool) {
	for _, n := range m.Nodes {
		if n.ID == id {
			return n, true
		}
	}
	return Node{}, false
}

// EdgeByID is the edge with id, if any.
func (m Model) EdgeByID(id string) (Edge, bool) {
	for _, e := range m.Edges {
		if e.ID == id {
			return e, true
		}
	}
	return Edge{}, false
}

// Refs are the distinct evidence refs, in citation order: nodes first, then
// edges.
func (m Model) Refs() []Ref {
	var out []Ref
	seen := map[Ref]bool{}
	add := func(evidence []Evidence) {
		for _, e := range evidence {
			if !seen[e.Ref] {
				seen[e.Ref] = true
				out = append(out, e.Ref)
			}
		}
	}
	for _, n := range m.Nodes {
		add(n.Evidence)
	}
	for _, e := range m.Edges {
		add(e.Evidence)
	}
	return out
}

// Clone is a deep copy, so edits to it never reach m.
func (m Model) Clone() Model {
	out := m
	out.Tags = cloneSlice(m.Tags)
	out.Nodes = make([]Node, len(m.Nodes))
	for i, n := range m.Nodes {
		out.Nodes[i] = n.Clone()
	}
	out.Edges = make([]Edge, len(m.Edges))
	for i, e := range m.Edges {
		out.Edges[i] = e.Clone()
	}
	if m.Views != nil {
		out.Views = make([]View, len(m.Views))
		for i, v := range m.Views {
			out.Views[i] = v.Clone()
		}
	}
	return out
}

// Clone is a deep copy of n.
func (n Node) Clone() Node {
	n.Tags = cloneSlice(n.Tags)
	n.Properties = n.Properties.Clone()
	n.Evidence = cloneSlice(n.Evidence)
	if n.Link != nil {
		l := *n.Link
		n.Link = &l
	}
	return n
}

// Clone is a deep copy of e.
func (e Edge) Clone() Edge {
	e.Tags = cloneSlice(e.Tags)
	e.Properties = e.Properties.Clone()
	e.Evidence = cloneSlice(e.Evidence)
	return e
}

// Clone is a deep copy of v.
func (v View) Clone() View {
	v.Collapsed = cloneSlice(v.Collapsed)
	if v.Filter != nil {
		f := *v.Filter
		f.Kinds = cloneSlice(f.Kinds)
		f.Tags = cloneSlice(f.Tags)
		v.Filter = &f
	}
	if v.Positions != nil {
		p := make(map[string][2]float64, len(v.Positions))
		for k, xy := range v.Positions {
			p[k] = xy
		}
		v.Positions = p
	}
	if v.Sizes != nil {
		sz := make(map[string]Size, len(v.Sizes))
		for k, wh := range v.Sizes {
			sz[k] = wh
		}
		v.Sizes = sz
	}
	v.Options = v.Options.Clone()
	return v
}

// Clone is a copy of p (values are scalars, so shallow is deep).
func (p Properties) Clone() Properties {
	if p == nil {
		return nil
	}
	out := make(Properties, len(p))
	for k, v := range p {
		out[k] = v
	}
	return out
}

func cloneSlice[T any](s []T) []T {
	if s == nil {
		return nil
	}
	return append([]T(nil), s...)
}
