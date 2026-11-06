package modelcap

import (
	"context"
	"fmt"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/diff"
	"github.com/craggy-io/modelling-services/edit"
	"github.com/craggy-io/modelling-services/export"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

// Capabilities are the model capabilities, named <prefix>.<operation>.
func (s *Service[S]) Capabilities() []registry.Capability {
	p := s.d.Prefix + "."
	tags := registry.WithTags(append([]string{s.d.Prefix}, s.d.Tags...)...)
	ro := registry.WithEffects(registry.ReadOnly | registry.Idempotent)
	return []registry.Capability{
		registry.Func(p+"list", "List models",
			func(ctx context.Context, in listIn) (listOut[S], error) {
				all, err := s.d.Store.List(ctx, in.Scope)
				if err != nil {
					return listOut[S]{}, s.codes.Wrap(err)
				}
				page, err := registry.Paginate(all, in.PageIn)
				return listOut[S]{Models: page.Items, Next: page.Next}, err
			},
			registry.Describe("List model revisions, one page per call: repeat with the returned next cursor until it is empty. Read one with "+p+"read."),
			ro, tags),
		registry.Func(p+"read", "Read a model",
			func(ctx context.Context, in readIn) (readOut, error) {
				m, err := s.read(ctx, in.Scope, in.Model)
				if err != nil {
					return readOut{}, s.codes.Wrap(err)
				}
				out := readOut{Scope: in.Scope, Model: in.Model}
				switch in.Format {
				case "", "json":
					out.Document = &m
				case "outline":
					out.Text = export.Outline(m)
				case "mermaid":
					out.Text = export.Mermaid(m)
				default:
					return readOut{}, s.codes.Wrap(fmt.Errorf("%w: %w %q (want json, outline or mermaid)", model.ErrInvalid, errFormat, in.Format))
				}
				return out, nil
			},
			registry.Describe("Read one model revision. format=json (default) returns the document; format=outline returns a compact Markdown outline (areas as a nested list with `ids`, then relationships), the cheapest way to take in a large model; format=mermaid returns a Mermaid flowchart. Reading a model does not establish that its assertions are true."),
			ro, tags),
		registry.Func(p+"create", "Create a model",
			func(ctx context.Context, in createIn) (writeOut, error) {
				m, err := in.model()
				if err != nil {
					return writeOut{}, s.codes.Wrap(err)
				}
				sv, err := s.create(ctx, in.Scope, m, in.BasedOn)
				return s.saved(ctx, in.Scope, sv, m, err)
			},
			registry.Describe("Store a new model from a complete document or an import (Mermaid flowchart, Markdown outline or CSV). A document is format \"craggy.model\", version 2: title, subject, nodes (id, label, optional parent for containment, kind, notes, tags, properties of strings/numbers/bools, evidence [{caption, ref: {scheme, id, selector}}], link) and edges (id, from, to, label, optional kind, undirected, notes, tags, properties, evidence). Containment is acyclic and edges never imply it. basedOn names the model this one starts from (recorded as lineage; that model is unchanged): keep the ids that still match. The output lists lint errors and warnings worth fixing."),
			tags),
		registry.Func(p+"update", "Replace a model",
			func(ctx context.Context, in updateIn) (writeOut, error) {
				m, err := normalize(in.Document)
				if err != nil {
					return writeOut{}, s.codes.Wrap(err)
				}
				sv, err := s.revise(ctx, in.Scope, in.Model, m, "update")
				return s.saved(ctx, in.Scope, sv, m, err)
			},
			registry.Describe("Store a complete replacement document as the model's next revision. Prefer "+p+"apply for changes to part of a model: it sends only the edits."),
			tags),
		registry.Func(p+"apply", "Edit a model",
			func(ctx context.Context, in applyIn) (applyOut, error) {
				m, err := s.read(ctx, in.Scope, in.Model)
				if err != nil {
					return applyOut{}, s.codes.Wrap(err)
				}
				next, inverse, err := edit.Apply(m, in.Ops, s.d.Limits)
				if err != nil {
					return applyOut{}, s.codes.Wrap(err)
				}
				sv, err := s.d.Store.Revise(ctx, in.Scope, in.Model, next, "apply")
				out, err := s.saved(ctx, in.Scope, sv, next, err)
				return applyOut{writeOut: out, Inverse: inverse}, err
			},
			registry.Describe("Apply a list of small operations to a model and store the result as its next revision, all or nothing. Operations: node.add {node, index?}, node.remove {id, cascade?}, node.move {id, parent, index?}, node.set {id, fields: label|kind|notes|tags|link}, edge.add {edge}, edge.remove {id}, edge.set {id, fields: label|from|to|kind|undirected|notes|tags}, prop.set/prop.unset {target: node|edge, id, key, value}, evidence.add {target, id, evidence}, evidence.remove {target, id, evidenceId}, model.set {fields: title|subject|notes|profile|tags}, view.put {view}, view.remove {id}. In fields, null clears. The output carries the inverse operations, which undo the change."),
			registry.WithExample("add an area inside another and connect it", applyIn{Scope: "scope-1", Model: "model-1", Ops: []edit.Op{
				{Op: edit.NodeAdd, Node: &model.Node{ID: "token-parser", Label: "Token parser", Parent: "native"}},
				{Op: edit.EdgeAdd, Edge: &model.Edge{ID: "ui--token-parser", From: "ui", To: "token-parser", Label: "passes tokens to"}},
			}}),
			tags),
		registry.Func(p+"attach", "Attach evidence",
			func(ctx context.Context, in attachIn) (writeOut, error) {
				return s.attach(ctx, in)
			},
			registry.Describe("Cite evidence on one node or edge, stored as the model's next revision. Refs the element already cites are skipped; when nothing is new no revision is stored and the output names the given model."),
			tags),
		registry.Func(p+"diff", "Compare model revisions",
			func(ctx context.Context, in diffIn) (diffOut, error) {
				base, err := s.read(ctx, in.Scope, in.Base)
				if err != nil {
					return diffOut{}, s.codes.Wrap(err)
				}
				rev, err := s.read(ctx, in.Scope, in.Model)
				if err != nil {
					return diffOut{}, s.codes.Wrap(err)
				}
				return diffOut{Changes: diff.Compare(base, rev, diff.Options{Views: in.Views})}, nil
			},
			registry.Describe("What changed from base to model: nodes and edges added, removed or changed, with each changed field's old and new value. Element order and views are not changes unless views=true."),
			ro, tags),
		registry.Func(p+"lint", "Lint a model",
			func(ctx context.Context, in lintIn) (lintOut, error) {
				m, err := s.read(ctx, in.Scope, in.Model)
				if err != nil {
					return lintOut{}, s.codes.Wrap(err)
				}
				var findings []query.Finding
				if in.All {
					findings, err = s.lintAll(ctx, in.Scope, m)
				} else {
					findings, err = s.lint(ctx, in.Scope, m)
				}
				if findings == nil {
					findings = []query.Finding{}
				}
				return lintOut{Findings: findings}, s.codes.Wrap(err)
			},
			registry.Describe("Likely mistakes in a model: duplicate sibling labels, repeated relationships, edges to an area's own container, stale views and, when the model names a profile, kind and property violations. all=true adds informational findings such as elements without evidence."),
			ro, tags),
		registry.Func(p+"query", "Query a model",
			func(ctx context.Context, in queryIn) (queryOut, error) {
				return s.query(ctx, in)
			},
			registry.Describe("Ask a model a structural question. fn=neighbours (id, direction out|in|both, depth), paths (from, to, maxLen, maxPaths: each path as edge ids), impact (id: everything reachable forward from the area or anything inside it), search (filter: text, kinds, tags)."),
			ro, tags),
		registry.Func(p+"export", "Export a model",
			func(ctx context.Context, in exportIn) (exportOut, error) {
				return s.export(ctx, in)
			},
			registry.Describe("Write a model as text for other tools: mermaid (flowchart), dot (Graphviz), outline (Markdown), svg (static nested blocks), or csv (nodes table in text, edges table in edges)."),
			ro, tags),
	}
}

func (s *Service[S]) attach(ctx context.Context, in attachIn) (writeOut, error) {
	target, id := edit.TargetNode, in.Node
	if (in.Node == "") == (in.Edge == "") {
		return writeOut{}, s.codes.Wrap(fmt.Errorf("%w: attach names exactly one node or edge", model.ErrInvalid))
	}
	if in.Edge != "" {
		target, id = edit.TargetEdge, in.Edge
	}
	if len(in.Evidence) == 0 {
		return writeOut{}, s.codes.Wrap(fmt.Errorf("%w: attach needs at least one evidence item", model.ErrInvalid))
	}
	m, err := s.read(ctx, in.Scope, in.Model)
	if err != nil {
		return writeOut{}, s.codes.Wrap(err)
	}
	ops := make([]edit.Op, len(in.Evidence))
	for i := range in.Evidence {
		ops[i] = edit.Op{Op: edit.EvidenceAdd, Target: target, ID: id, Evidence: &in.Evidence[i]}
	}
	next, _, err := edit.Apply(m, ops, s.d.Limits)
	if err != nil {
		return writeOut{}, s.codes.Wrap(err)
	}
	if model.Equal(m, next) {
		return s.saved(ctx, in.Scope, Saved{ID: in.Model}, m, nil)
	}
	sv, err := s.d.Store.Revise(ctx, in.Scope, in.Model, next, "attach")
	return s.saved(ctx, in.Scope, sv, next, err)
}

func (s *Service[S]) query(ctx context.Context, in queryIn) (queryOut, error) {
	m, err := s.read(ctx, in.Scope, in.Model)
	if err != nil {
		return queryOut{}, s.codes.Wrap(err)
	}
	ix := model.NewIndex(m)
	need := func(ids ...string) error {
		for _, id := range ids {
			if _, ok := ix.Node(id); !ok {
				return s.codes.Wrap(fmt.Errorf("%w: model has no node %q", model.ErrInvalid, id))
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
	return queryOut{}, s.codes.Wrap(fmt.Errorf("%w: unknown fn %q (want neighbours, paths, impact or search)", model.ErrInvalid, in.Fn))
}

func (s *Service[S]) export(ctx context.Context, in exportIn) (exportOut, error) {
	m, err := s.read(ctx, in.Scope, in.Model)
	if err != nil {
		return exportOut{}, s.codes.Wrap(err)
	}
	switch in.Format {
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
		return exportOut{Text: string(nodes), Edges: string(edges)}, s.codes.Wrap(err)
	}
	return exportOut{}, s.codes.Wrap(fmt.Errorf("%w: %w %q (want mermaid, dot, outline, svg or csv)", model.ErrInvalid, errFormat, in.Format))
}
