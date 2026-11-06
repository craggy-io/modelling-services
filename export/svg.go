package export

import (
	"fmt"
	"html"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// SVGOptions size a static rendering. Zero fields take the defaults.
type SVGOptions struct {
	Width      float64 // default 960
	MaxColumns int     // default 3
}

// SVG renders m as static nested blocks, the shape of the interactive block
// view, with straight relationship lines between area labels. Text widths
// are estimated, so long labels are cut with an ellipsis.
func SVG(m model.Model, o SVGOptions) string {
	if o.Width <= 0 {
		o.Width = 960
	}
	if o.MaxColumns <= 0 {
		o.MaxColumns = 3
	}
	l := &svgLayout{ix: model.NewIndex(m), o: o, anchors: map[string][2]float64{}}
	var body strings.Builder
	height := l.place(&body, "", m.Title, 0, 0, o.Width, 0)
	var lines strings.Builder
	for _, e := range m.Edges {
		a, okA := l.anchors[e.From]
		b, okB := l.anchors[e.To]
		if !okA || !okB || e.From == e.To {
			continue
		}
		marker := ` marker-end="url(#arrow)"`
		if e.Undirected {
			marker = ""
		}
		fmt.Fprintf(&lines, `<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#5b6b8c" stroke-opacity="0.55" stroke-width="1.5"%s><title>%s</title></line>`+"\n",
			a[0], a[1], b[0], b[1], marker, html.EscapeString(e.Label))
	}
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f" font-family="Helvetica, Arial, sans-serif">
<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#5b6b8c"/></marker></defs>
%s%s</svg>
`, o.Width, height, o.Width, height, body.String(), lines.String())
}

const (
	svgPad    = 12.0
	svgGap    = 10.0
	svgHeader = 28.0
	svgChar   = 7.0 // estimated width of one 13px character
)

type svgLayout struct {
	ix      *model.Index
	o       SVGOptions
	anchors map[string][2]float64
}

// place draws the area (id "" is the root, titled title) at x, y with width
// w and returns its height. Children are laid out in rows of up to
// MaxColumns equal columns.
func (l *svgLayout) place(b *strings.Builder, id, title string, x, y, w float64, depth int) float64 {
	children := l.ix.Children(id)
	label := title
	if id != "" {
		n, _ := l.ix.Node(id)
		label = n.Label
	}
	inner := y + svgPad + svgHeader
	var rows strings.Builder
	if len(children) > 0 {
		cols := min(l.o.MaxColumns, len(children))
		cw := (w - 2*svgPad - float64(cols-1)*svgGap) / float64(cols)
		for start := 0; start < len(children); start += cols {
			rowHeight := 0.0
			for c, child := range children[start:min(start+cols, len(children))] {
				h := l.place(&rows, child, "", x+svgPad+float64(c)*(cw+svgGap), inner, cw, depth+1)
				rowHeight = max(rowHeight, h)
			}
			inner += rowHeight + svgGap
		}
		inner -= svgGap
	}
	height := inner - y + svgPad
	shade := 250 - min(depth, 6)*8
	fill := fmt.Sprintf("rgb(%d,%d,%d)", shade, shade, min(255, shade+4))
	fmt.Fprintf(b, `<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8" fill="%s" stroke="#c9d1e0"/>`+"\n", x, y, w, height, fill)
	weight, size := "600", 13
	if id == "" {
		weight, size = "700", 15
	}
	fmt.Fprintf(b, `<text x="%.1f" y="%.1f" font-size="%d" font-weight="%s" fill="#1d2433">%s</text>`+"\n",
		x+svgPad, y+svgPad+16, size, weight, html.EscapeString(fit(label, w-2*svgPad)))
	if id != "" {
		l.anchors[id] = [2]float64{x + w/2, y + svgPad + 10}
	}
	b.WriteString(rows.String())
	return height
}

// fit cuts s with an ellipsis to fit width at the estimated character width.
func fit(s string, width float64) string {
	limit := int(width / svgChar)
	r := []rune(oneLine(s))
	if limit < 2 || len(r) <= limit {
		return string(r)
	}
	return string(r[:limit-1]) + "…"
}
