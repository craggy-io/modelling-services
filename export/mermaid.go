// Package export writes models as text other tools read (Mermaid, Graphviz
// DOT, a Markdown outline, CSV, static SVG) and reads Mermaid, outlines and
// CSV back. Mermaid and outline output is byte-identical to the Dart
// implementation's; docs/export.md specifies both grammars.
package export

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// Mermaid writes m as a Mermaid flowchart: one subgraph per node with
// children, one node per leaf, then every edge. Ids are prefixed "n_" so no
// id collides with a Mermaid keyword.
func Mermaid(m model.Model) string {
	ix := model.NewIndex(m)
	var b strings.Builder
	fmt.Fprintf(&b, "---\ntitle: %s\n---\nflowchart LR\n", oneLine(m.Title))
	var walk func(parent string, depth int)
	walk = func(parent string, depth int) {
		pad := strings.Repeat("  ", depth)
		for _, id := range ix.Children(parent) {
			n, _ := ix.Node(id)
			if len(ix.Children(id)) > 0 {
				fmt.Fprintf(&b, "%ssubgraph n_%s[\"%s\"]\n", pad, id, mermaidText(n.Label))
				walk(id, depth+1)
				fmt.Fprintf(&b, "%send\n", pad)
			} else {
				fmt.Fprintf(&b, "%sn_%s[\"%s\"]\n", pad, id, mermaidText(n.Label))
			}
		}
	}
	walk("", 1)
	for _, e := range m.Edges {
		arrow := "-->"
		if e.Undirected {
			arrow = "---"
		}
		fmt.Fprintf(&b, "  n_%s %s|\"%s\"| n_%s\n", e.From, arrow, mermaidText(e.Label), e.To)
	}
	return b.String()
}

func mermaidText(s string) string { return strings.ReplaceAll(oneLine(s), `"`, "#quot;") }

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }

var (
	mmNode     = `([A-Za-z0-9_-]+)(?:\s*(?:\[\[|\[\(|\[|\(\(|\(|\{)\s*("[^"]*"|[^\]\)\}]*?)\s*(?:\]\]|\)\]|\]|\)\)|\)|\}))?`
	mmSubgraph = regexp.MustCompile(`^subgraph\s+` + mmNode + `\s*$`)
	mmEdge     = regexp.MustCompile(`^` + mmNode + `\s*(-->|---|-\.->|==>|--\s*[^-|>][^>]*?\s*-->)\s*(?:\|\s*("[^"]*"|[^|]*?)\s*\|)?\s*` + mmNode + `\s*;?$`)
	mmLone     = regexp.MustCompile(`^` + mmNode + `\s*;?$`)
)

// ParseMermaid reads a Mermaid flowchart: front-matter title, subgraphs
// (nested areas), node declarations and single edges (-->, ---, -.->, ==>,
// "-- label -->", with an optional |label|). Styling, class and click lines
// are ignored; anything else is an error naming the line. The result is not
// validated.
func ParseMermaid(src string) (model.Model, error) {
	m := model.New("Untitled model", "Imported from Mermaid")
	ids := newIDs()
	labels := map[string]string{}
	parents := map[string]string{}
	var order []string
	declare := func(raw, label, parent string, explicit bool) string {
		id := ids.node(raw)
		if _, ok := labels[id]; !ok {
			order = append(order, id)
			labels[id] = id
			parents[id] = parent
		}
		if explicit {
			labels[id] = label
		}
		return id
	}
	var stack []string
	parent := func() string {
		if len(stack) == 0 {
			return ""
		}
		return stack[len(stack)-1]
	}
	lines := strings.Split(strings.ReplaceAll(src, "\r\n", "\n"), "\n")
	inFront := false
	for i, line := range lines {
		line = strings.TrimSpace(line)
		switch {
		case line == "---" && (i == 0 || inFront):
			inFront = !inFront
			continue
		case inFront:
			if t, ok := strings.CutPrefix(line, "title:"); ok {
				m.Title = strings.TrimSpace(t)
			}
			continue
		case line == "" || strings.HasPrefix(line, "%%"):
			continue
		case strings.HasPrefix(line, "flowchart") || strings.HasPrefix(line, "graph"):
			continue
		case hasAnyPrefix(line, "classDef ", "class ", "style ", "click ", "linkStyle ", "direction "):
			continue
		case line == "end":
			if len(stack) == 0 {
				return m, fmt.Errorf("%w: mermaid line %d: end without subgraph", model.ErrInvalid, i+1)
			}
			stack = stack[:len(stack)-1]
			continue
		}
		if g := mmSubgraph.FindStringSubmatch(line); g != nil {
			id := declare(g[1], unquote(g[2]), parent(), g[2] != "")
			parents[id] = parent()
			stack = append(stack, id)
			continue
		}
		if g := mmEdge.FindStringSubmatch(line); g != nil {
			from := declare(g[1], unquote(g[2]), parent(), g[2] != "")
			to := declare(g[5], unquote(g[6]), parent(), g[6] != "")
			label := unquote(g[4])
			if label == "" {
				if l, ok := strings.CutPrefix(g[3], "--"); ok && strings.HasSuffix(l, "-->") {
					label = strings.TrimSpace(strings.TrimSuffix(l, "-->"))
				}
			}
			if label == "" {
				label = "relates to"
			}
			m.Edges = append(m.Edges, model.Edge{ID: ids.edge(from, to), From: from, To: to, Label: label, Undirected: g[3] == "---"})
			continue
		}
		if g := mmLone.FindStringSubmatch(line); g != nil {
			// Listing a node inside a subgraph moves it there, as in Mermaid.
			id := declare(g[1], unquote(g[2]), parent(), g[2] != "")
			if p := parent(); p != "" && p != id {
				parents[id] = p
			}
			continue
		}
		return m, fmt.Errorf("%w: mermaid line %d: cannot read %q", model.ErrInvalid, i+1, line)
	}
	if len(stack) > 0 {
		return m, fmt.Errorf("%w: mermaid: subgraph %q is not closed", model.ErrInvalid, stack[len(stack)-1])
	}
	for _, id := range order {
		m.Nodes = append(m.Nodes, model.Node{ID: id, Label: labels[id], Parent: parents[id]})
	}
	return m, nil
}

func unquote(s string) string {
	s = strings.TrimSpace(s)
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		s = s[1 : len(s)-1]
	}
	return strings.TrimSpace(strings.ReplaceAll(s, "#quot;", `"`))
}

func hasAnyPrefix(s string, prefixes ...string) bool {
	for _, p := range prefixes {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}
