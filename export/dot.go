package export

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// DOT writes m for Graphviz: each node with children is a cluster holding an
// anchor node (so edges can reach the area itself) and its children; leaves
// are boxes; undirected edges have no arrowhead.
func DOT(m model.Model) string {
	ix := model.NewIndex(m)
	var b strings.Builder
	fmt.Fprintf(&b, "digraph model {\n  graph [label=%s, labelloc=t, compound=true, rankdir=LR, fontname=\"Helvetica\"];\n", dotString(m.Title))
	b.WriteString("  node [shape=box, style=rounded, fontname=\"Helvetica\"];\n  edge [fontname=\"Helvetica\", fontsize=10];\n")
	var walk func(parent string, depth int)
	walk = func(parent string, depth int) {
		pad := strings.Repeat("  ", depth)
		for _, id := range ix.Children(parent) {
			n, _ := ix.Node(id)
			if len(ix.Children(id)) == 0 {
				fmt.Fprintf(&b, "%s%s [label=%s];\n", pad, dotString(id), dotString(n.Label))
				continue
			}
			fmt.Fprintf(&b, "%ssubgraph %s {\n%s  label=%s;\n", pad, dotString("cluster_"+id), pad, dotString(n.Label))
			fmt.Fprintf(&b, "%s  %s [label=%s, shape=folder];\n", pad, dotString(id), dotString(n.Label))
			walk(id, depth+1)
			fmt.Fprintf(&b, "%s}\n", pad)
		}
	}
	walk("", 1)
	for _, e := range m.Edges {
		attrs := "label=" + dotString(e.Label)
		if e.Undirected {
			attrs += ", dir=none"
		}
		fmt.Fprintf(&b, "  %s -> %s [%s];\n", dotString(e.From), dotString(e.To), attrs)
	}
	b.WriteString("}\n")
	return b.String()
}

func dotString(s string) string { return strconv.Quote(oneLine(s)) }
