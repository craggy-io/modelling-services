// Package query answers questions about one model: search, neighbours,
// paths, impact, and lint findings (lint.go). Every function takes a
// model.Index and returns ids in a deterministic order, so Go and Dart agree.
package query

import (
	"fmt"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// Direction says which way Neighbours follows edges. Undirected edges are
// followed both ways whatever the direction.
type Direction string

const (
	Out  Direction = "out"
	In   Direction = "in"
	Both Direction = "both"
)

// Search is the ids of nodes matching f, in document order. Text matches
// case-insensitively against id, label, notes, tags and property values;
// Kinds and Tags match any listed value. ChangedOnly is ignored here (it
// needs a base; callers filter with a diff).
func Search(ix *model.Index, f model.Filter) []string {
	text := strings.ToLower(strings.TrimSpace(f.Text))
	var out []string
	for _, n := range ix.Model().Nodes {
		if len(f.Kinds) > 0 && !contains(f.Kinds, n.Kind) {
			continue
		}
		if len(f.Tags) > 0 && !anyIn(f.Tags, n.Tags) {
			continue
		}
		if text != "" && !strings.Contains(Haystack(n), text) {
			continue
		}
		out = append(out, n.ID)
	}
	return out
}

// Haystack is the lower-cased text Search matches a node against.
func Haystack(n model.Node) string {
	parts := []string{n.ID, n.Label, n.Notes}
	parts = append(parts, n.Tags...)
	for _, k := range model.SortedKeys(n.Properties) {
		parts = append(parts, fmt.Sprint(n.Properties[k]))
	}
	return strings.ToLower(strings.Join(parts, "\n"))
}

// Neighbours are the nodes within depth edges of id (depth < 1 means 1),
// breadth first, each level in edge document order. id itself is excluded.
func Neighbours(ix *model.Index, id string, dir Direction, depth int) []string {
	if depth < 1 {
		depth = 1
	}
	seen := map[string]bool{id: true}
	var out []string
	frontier := []string{id}
	for level := 0; level < depth && len(frontier) > 0; level++ {
		var next []string
		for _, n := range frontier {
			for _, other := range step(ix, n, dir) {
				if !seen[other] {
					seen[other] = true
					out = append(out, other)
					next = append(next, other)
				}
			}
		}
		frontier = next
	}
	return out
}

// step is the nodes one edge away from id, in edge document order.
func step(ix *model.Index, id string, dir Direction) []string {
	var out []string
	for _, eid := range ix.Touching(id) {
		e, _ := ix.Edge(eid)
		if e.From == id && (dir != In || e.Undirected) {
			out = append(out, e.To)
		}
		if e.To == id && e.From != id && (dir != Out || e.Undirected) {
			out = append(out, e.From)
		}
	}
	return out
}

// Paths are the simple paths from one node to another, each as the edge ids
// it follows, following edges forward (undirected edges either way), at most
// maxLen edges long and at most maxPaths of them, depth first in edge
// document order.
func Paths(ix *model.Index, from, to string, maxLen, maxPaths int) [][]string {
	var out [][]string
	visited := map[string]bool{from: true}
	var path []string
	var walk func(at string)
	walk = func(at string) {
		for _, eid := range ix.Touching(at) {
			if len(out) >= maxPaths {
				return
			}
			e, _ := ix.Edge(eid)
			next := ""
			switch {
			case e.From == at:
				next = e.To
			case e.Undirected && e.To == at:
				next = e.From
			default:
				continue
			}
			if next == to {
				out = append(out, append(append([]string(nil), path...), eid))
				continue
			}
			if visited[next] || len(path)+1 >= maxLen {
				continue
			}
			visited[next] = true
			path = append(path, eid)
			walk(next)
			path = path[:len(path)-1]
			visited[next] = false
		}
	}
	if maxLen > 0 && maxPaths > 0 {
		walk(from)
	}
	return out
}

// Impact is every node reachable forward from id or anything inside it,
// in document order, excluding id and its descendants. It answers "what
// could a change here affect?".
func Impact(ix *model.Index, id string) []string {
	inside := map[string]bool{id: true}
	for _, d := range ix.Descendants(id) {
		inside[d] = true
	}
	reached := map[string]bool{}
	var frontier []string
	for n := range inside {
		frontier = append(frontier, n)
	}
	for len(frontier) > 0 {
		var next []string
		for _, n := range frontier {
			for _, other := range step(ix, n, Out) {
				if !inside[other] && !reached[other] {
					reached[other] = true
					next = append(next, other)
				}
			}
		}
		frontier = next
	}
	var out []string
	for _, n := range ix.Model().Nodes {
		if reached[n.ID] {
			out = append(out, n.ID)
		}
	}
	return out
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func anyIn(want, have []string) bool {
	for _, w := range want {
		if contains(have, w) {
			return true
		}
	}
	return false
}
