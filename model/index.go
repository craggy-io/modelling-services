package model

import "sort"

// Index answers structural questions about one model without rescanning it.
// Build it with NewIndex after validating; it is read-only and does not
// follow later changes to the model.
type Index struct {
	model    Model
	nodes    map[string]int
	edges    map[string]int
	children map[string][]string // parent id ("" for top level) -> child ids, document order
	touching map[string][]string // node id -> ids of edges with it as either end, document order
}

// NewIndex indexes m. Nodes whose parent is missing count as top level.
func NewIndex(m Model) *Index {
	ix := &Index{
		model: m, nodes: map[string]int{}, edges: map[string]int{},
		children: map[string][]string{}, touching: map[string][]string{},
	}
	for i, n := range m.Nodes {
		ix.nodes[n.ID] = i
	}
	for _, n := range m.Nodes {
		p := n.Parent
		if _, ok := ix.nodes[p]; !ok {
			p = ""
		}
		ix.children[p] = append(ix.children[p], n.ID)
	}
	for i, e := range m.Edges {
		ix.edges[e.ID] = i
		ix.touching[e.From] = append(ix.touching[e.From], e.ID)
		if e.To != e.From {
			ix.touching[e.To] = append(ix.touching[e.To], e.ID)
		}
	}
	return ix
}

// Model is the indexed model.
func (ix *Index) Model() Model { return ix.model }

// Node is the node with id.
func (ix *Index) Node(id string) (Node, bool) {
	i, ok := ix.nodes[id]
	if !ok {
		return Node{}, false
	}
	return ix.model.Nodes[i], true
}

// Edge is the edge with id.
func (ix *Index) Edge(id string) (Edge, bool) {
	i, ok := ix.edges[id]
	if !ok {
		return Edge{}, false
	}
	return ix.model.Edges[i], true
}

// NodeIndex is the node's position in Model.Nodes, or -1.
func (ix *Index) NodeIndex(id string) int {
	if i, ok := ix.nodes[id]; ok {
		return i
	}
	return -1
}

// EdgeIndex is the edge's position in Model.Edges, or -1.
func (ix *Index) EdgeIndex(id string) int {
	if i, ok := ix.edges[id]; ok {
		return i
	}
	return -1
}

// Children are the ids of parent's direct children ("" for top level).
func (ix *Index) Children(parent string) []string { return ix.children[parent] }

// Parent is the containing node's id, or "" at top level.
func (ix *Index) Parent(id string) string {
	n, _ := ix.Node(id)
	if _, ok := ix.nodes[n.Parent]; !ok {
		return ""
	}
	return n.Parent
}

// Ancestors are id's containing nodes, nearest first. It stops at a cycle.
func (ix *Index) Ancestors(id string) []string {
	var out []string
	seen := map[string]bool{id: true}
	for p := ix.Parent(id); p != "" && !seen[p]; p = ix.Parent(p) {
		seen[p] = true
		out = append(out, p)
	}
	return out
}

// Descendants are every node inside id, depth first in document order.
func (ix *Index) Descendants(id string) []string {
	var out []string
	seen := map[string]bool{id: true}
	var walk func(string)
	walk = func(p string) {
		for _, c := range ix.children[p] {
			if !seen[c] {
				seen[c] = true
				out = append(out, c)
				walk(c)
			}
		}
	}
	walk(id)
	return out
}

// Touching are the ids of edges with node id at either end.
func (ix *Index) Touching(id string) []string { return ix.touching[id] }

// Depth is id's containment depth: 1 at top level.
func (ix *Index) Depth(id string) int { return len(ix.Ancestors(id)) + 1 }

// SortedKeys are m's keys in byte order.
func SortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
