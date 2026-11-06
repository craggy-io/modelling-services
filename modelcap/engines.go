package modelcap

import (
	"fmt"

	"github.com/craggy-io/modelling-services/export"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

// The engine calls both capability sets share: they take a model, never a
// store.

// parse is the imported text as a model.
func (in importIn) parse() (model.Model, error) {
	switch in.Format {
	case "mermaid":
		return export.ParseMermaid(in.Source)
	case "outline":
		return export.ParseOutline(in.Source)
	case "csv":
		title := in.Title
		if title == "" {
			title = "Imported model"
		}
		return export.ParseCSV(title, []byte(in.Source), []byte(in.Edges))
	}
	return model.Model{}, fmt.Errorf("%w: %w %q (want mermaid, outline or csv)", model.ErrInvalid, errFormat, in.Format)
}

// exportAs writes m in format.
func exportAs(m model.Model, format string) (exportOut, error) {
	switch format {
	case "mermaid":
		return exportOut{Text: export.Mermaid(m)}, nil
	case "dot":
		return exportOut{Text: export.DOT(m)}, nil
	case "outline":
		return exportOut{Text: export.Outline(m)}, nil
	case "svg":
		return exportOut{Text: export.SVG(m, export.SVGOptions{})}, nil
	case "csv":
		nodes, edges, err := export.CSV(m)
		return exportOut{Text: string(nodes), Edges: string(edges)}, err
	}
	return exportOut{}, fmt.Errorf("%w: %w %q (want mermaid, dot, outline, svg or csv)", model.ErrInvalid, errFormat, format)
}

// ask answers one structural question about m.
func ask(m model.Model, in queryArgs) (queryOut, error) {
	ix := model.NewIndex(m)
	need := func(ids ...string) error {
		for _, id := range ids {
			if _, ok := ix.Node(id); !ok {
				return fmt.Errorf("%w: model has no node %q", model.ErrInvalid, id)
			}
		}
		return nil
	}
	switch in.Fn {
	case "neighbours":
		dir := in.Direction
		if dir == "" {
			dir = query.Both
		}
		return queryOut{Nodes: query.Neighbours(ix, in.ID, dir, in.Depth)}, need(in.ID)
	case "paths":
		maxLen, maxPaths := in.MaxLen, in.MaxPaths
		if maxLen <= 0 {
			maxLen = 6
		}
		if maxPaths <= 0 {
			maxPaths = 20
		}
		return queryOut{Paths: query.Paths(ix, in.From, in.To, maxLen, maxPaths)}, need(in.From, in.To)
	case "impact":
		return queryOut{Nodes: query.Impact(ix, in.ID)}, need(in.ID)
	case "search":
		var f model.Filter
		if in.Filter != nil {
			f = *in.Filter
		}
		return queryOut{Nodes: query.Search(ix, f)}, nil
	}
	return queryOut{}, fmt.Errorf("%w: unknown fn %q (want neighbours, paths, impact or search)", model.ErrInvalid, in.Fn)
}

// lintWith is m's lint findings against profile (nil skips profile rules).
// Without all, informational findings are dropped. Never nil.
func lintWith(m model.Model, profile *model.Profile, all bool) []query.Finding {
	out := []query.Finding{}
	for _, f := range query.Lint(model.NewIndex(m), profile) {
		if all || f.Severity != query.Info {
			out = append(out, f)
		}
	}
	return out
}

// normalize fills what a decoded document always has: format, version and
// evidence ids.
func normalize(m model.Model) (model.Model, error) {
	raw, err := model.Encode(m)
	if err != nil {
		return m, err
	}
	return model.Decode(raw)
}
