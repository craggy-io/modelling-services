package export

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// Outline writes m as Markdown: the title, subject and notes, a nested list
// of areas, then the relationships. It is the cheapest form for a reader
// (or an agent) to take in a large model.
//
//	# Title
//
//	Subject
//
//	- **Label** `id`: notes
//	  - **Child** `child`
//
//	## Relationships
//
//	- `from` -> `to`: label `id`
func Outline(m model.Model) string {
	ix := model.NewIndex(m)
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n%s\n", oneLine(m.Title), oneLine(m.Subject))
	if notes := oneLine(m.Notes); notes != "" {
		fmt.Fprintf(&b, "\n%s\n", notes)
	}
	if len(m.Nodes) > 0 {
		b.WriteString("\n")
	}
	var walk func(parent string, depth int)
	walk = func(parent string, depth int) {
		for _, id := range ix.Children(parent) {
			n, _ := ix.Node(id)
			fmt.Fprintf(&b, "%s- **%s** `%s`", strings.Repeat("  ", depth), oneLine(n.Label), n.ID)
			if notes := oneLine(n.Notes); notes != "" {
				fmt.Fprintf(&b, ": %s", notes)
			}
			b.WriteString("\n")
			walk(id, depth+1)
		}
	}
	walk("", 0)
	if len(m.Edges) > 0 {
		b.WriteString("\n## Relationships\n\n")
		for _, e := range m.Edges {
			arrow := "->"
			if e.Undirected {
				arrow = "--"
			}
			fmt.Fprintf(&b, "- `%s` %s `%s`: %s `%s`\n", e.From, arrow, e.To, oneLine(e.Label), e.ID)
		}
	}
	return b.String()
}

var (
	olItem = regexp.MustCompile("^( *)[-*] +(?:\\*\\*(.+?)\\*\\*|([^`:]+?))(?: +`([^`]+)`)?(?: *: *(.*))?$")
	olEdge = regexp.MustCompile("^[-*] +(?:`([^`]+)`|([^`]+?)) +(->|--) +(?:`([^`]+)`|([^`:]+?)) *: *(.+?)(?: +`([^`]+)`)?$")
)

// ParseOutline reads the Markdown Outline writes, and hand-written outlines
// like it: "# Title", the first paragraph as the subject and the next as
// notes, list items as areas (two spaces of indent per level; "**label**"
// or a plain label, an optional `id`, and ": notes"), and under a
// "## Relationships" heading, items "`from` -> `to`: label `id`" ("--" for
// undirected; ends may be ids or labels). The result is not validated.
func ParseOutline(src string) (model.Model, error) {
	m := model.New("Untitled model", "Imported outline")
	ids := newIDs()
	var paragraphs []string
	var stack []string // ancestor ids by depth
	relationships := false
	type pending struct {
		line            int
		from, to, label string
		id              string
		undirected      bool
	}
	var edges []pending
	lines := strings.Split(strings.ReplaceAll(src, "\r\n", "\n"), "\n")
	for i, raw := range lines {
		line := strings.TrimRight(raw, " \t")
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
			continue
		case strings.HasPrefix(trimmed, "## "):
			relationships = strings.EqualFold(strings.TrimSpace(trimmed[3:]), "relationships")
			continue
		case strings.HasPrefix(trimmed, "# "):
			m.Title = strings.TrimSpace(trimmed[2:])
			continue
		}
		if relationships {
			g := olEdge.FindStringSubmatch(trimmed)
			if g == nil {
				return m, fmt.Errorf("%w: outline line %d: cannot read relationship %q", model.ErrInvalid, i+1, trimmed)
			}
			edges = append(edges, pending{line: i + 1, from: g[1] + g[2], to: g[4] + g[5], label: strings.TrimSpace(g[6]), id: g[7], undirected: g[3] == "--"})
			continue
		}
		g := olItem.FindStringSubmatch(line)
		if g == nil {
			if len(m.Nodes) == 0 {
				paragraphs = append(paragraphs, trimmed)
				continue
			}
			return m, fmt.Errorf("%w: outline line %d: cannot read %q", model.ErrInvalid, i+1, trimmed)
		}
		depth := len(g[1]) / 2
		if depth > len(stack) {
			return m, fmt.Errorf("%w: outline line %d: indented more than one level past its parent", model.ErrInvalid, i+1)
		}
		stack = stack[:depth]
		label := strings.TrimSpace(g[2] + g[3])
		id := g[4]
		if id == "" || !ids.claim(id) {
			id = ids.fresh(label)
		}
		parent := ""
		if depth > 0 {
			parent = stack[depth-1]
		}
		m.Nodes = append(m.Nodes, model.Node{ID: id, Label: label, Parent: parent, Notes: strings.TrimSpace(g[5])})
		stack = append(stack, id)
	}
	if len(paragraphs) > 0 {
		m.Subject = paragraphs[0]
	}
	if len(paragraphs) > 1 {
		m.Notes = strings.Join(paragraphs[1:], " ")
	}
	resolve := func(name string) string {
		for _, n := range m.Nodes {
			if n.ID == name {
				return n.ID
			}
		}
		for _, n := range m.Nodes {
			if strings.EqualFold(n.Label, strings.TrimSpace(name)) {
				return n.ID
			}
		}
		return ""
	}
	for _, e := range edges {
		from, to := resolve(e.from), resolve(e.to)
		if from == "" || to == "" {
			return m, fmt.Errorf("%w: outline line %d: relationship names an unknown area", model.ErrInvalid, e.line)
		}
		id := e.id
		if id == "" || !model.ValidID(id) || ids.edges[id] {
			id = ids.edge(from, to)
		} else {
			ids.edges[id] = true
		}
		m.Edges = append(m.Edges, model.Edge{ID: id, From: from, To: to, Label: e.label, Undirected: e.undirected})
	}
	return m, nil
}
