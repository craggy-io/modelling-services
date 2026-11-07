package modelcap

import (
	"bytes"
	"compress/flate"
	"context"
	"encoding/base64"
	"errors"
	"strings"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/diff"
	"github.com/craggy-io/modelling-services/edit"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

// ToolDeps configures the stateless model tools.
type ToolDeps struct {
	Prefix string // capability name prefix, e.g. "model"
	Limits model.Limits
	// Editor is the modeller's address, which <prefix>.open links to, e.g.
	// "https://models.craggy.io/".
	Editor string
}

// Tools are capabilities over model documents the caller holds: nothing is
// stored. Each takes the whole document and returns what it computed, so a
// host can serve them to anyone without accounts or storage. Use them with
// Service when the host keeps the models instead.
type Tools struct {
	d     ToolDeps
	codes registry.Codes
}

// NewTools builds the stateless tools.
func NewTools(d ToolDeps) *Tools {
	return &Tools{d: d, codes: registry.Codes{model.ErrInvalid: registry.Invalid}}
}

// Group is the capability group to register with the capabilities.
func (t *Tools) Group() registry.Group {
	return registry.Group{Name: t.d.Prefix, Description: "Block models as JSON documents you keep: nested areas, relationships and cited evidence. Check, import, edit, compare, lint, query, export and open in the modeller. Nothing is stored."}
}

// Link is the address that opens m in the modeller at editor: the canonical
// document, raw-deflated and base64url-encoded, in the "m" fragment
// parameter. Browsers never send a fragment to the server.
func Link(editor string, m model.Model) (string, error) {
	raw, err := model.Encode(m)
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	w, _ := flate.NewWriter(&buf, flate.BestCompression)
	w.Write(raw)
	w.Close()
	return strings.SplitN(editor, "#", 2)[0] + "#m=" + base64.RawURLEncoding.EncodeToString(buf.Bytes()), nil
}

// doc is a caller's document, normalized and validated.
func (t *Tools) doc(m model.Model) (model.Model, error) {
	m, err := normalize(m)
	if err != nil {
		return m, err
	}
	return m, m.Validate(t.d.Limits)
}

// lint is m's findings worth fixing, against profile when given.
func (t *Tools) lint(m model.Model, profile *model.Profile, all bool) ([]query.Finding, error) {
	if profile != nil {
		if err := profile.Check(); err != nil {
			return nil, err
		}
	}
	return lintWith(m, profile, all), nil
}

// result is a tool's new document with its lint findings.
func (t *Tools) result(m model.Model, profile *model.Profile) (docOut, error) {
	if err := m.Validate(t.d.Limits); err != nil {
		return docOut{}, t.codes.Wrap(err)
	}
	findings, err := t.lint(m, profile, false)
	return docOut{Document: m, Lint: findings}, t.codes.Wrap(err)
}

// Capabilities are the stateless tools, named <prefix>.<operation>.
func (t *Tools) Capabilities() []registry.Capability {
	p := t.d.Prefix + "."
	tags := registry.WithTags(t.d.Prefix)
	ro := registry.WithEffects(registry.ReadOnly | registry.Idempotent)
	return []registry.Capability{
		registry.Func(p+"check", "Check a model",
			func(ctx context.Context, in checkIn) (checkOut, error) {
				m, err := normalize(in.Document)
				if err != nil {
					return checkOut{}, t.codes.Wrap(err)
				}
				if issues := m.Issues(t.d.Limits); len(issues) > 0 {
					return checkOut{Valid: false, Issues: issues, Lint: []query.Finding{}}, nil
				}
				findings, err := t.lint(m, in.Profile, in.All)
				return checkOut{Valid: true, Issues: []model.Issue{}, Lint: findings, Document: &m}, t.codes.Wrap(err)
			},
			registry.Describe("Validate a model document and lint it. Returns valid, the validation issues (stable codes, the element concerned and a message) and, for a valid model, lint findings and the document normalized (format, version and evidence ids filled in). "+formatGuide+" Give profile to check kinds, containment and typed properties against it; all=true adds informational findings such as elements without evidence."),
			ro, tags),
		registry.Func(p+"import", "Import a model from text",
			func(ctx context.Context, in toolImportIn) (docOut, error) {
				m, err := in.parse()
				if err != nil {
					return docOut{}, t.codes.Wrap(err)
				}
				return t.result(m, in.Profile)
			},
			registry.Describe("Build a model document from text: a Mermaid flowchart (subgraphs nest), a Markdown outline (\"# Title\", a subject line, then nested list items \"- **Label** `id`: notes\" as areas, then \"## Relationships\" with \"- `from` -> `to`: label `id`\" lines) or CSV (a nodes table with a header naming id, label and optionally parent, kind, notes, tags, properties; an optional edges table naming id, from, to, label). Writing an outline is the quickest way to sketch a model; edit it afterwards with "+p+"apply."),
			ro, tags),
		registry.Func(p+"apply", "Edit a model",
			func(ctx context.Context, in toolApplyIn) (toolApplyOut, error) {
				m, err := t.doc(in.Document)
				if err != nil {
					return toolApplyOut{}, t.codes.Wrap(err)
				}
				next, inverse, err := edit.Apply(m, in.Ops, t.d.Limits)
				if err != nil {
					return toolApplyOut{}, t.codes.Wrap(err)
				}
				out, err := t.result(next, in.Profile)
				return toolApplyOut{docOut: out, Inverse: inverse}, err
			},
			registry.Describe("Apply small operations to a model document, all or nothing, and return the new document, its lint findings and the inverse operations that undo the change. "+opsGuide),
			registry.WithExample("add an area inside another and connect it", toolApplyIn{
				Document: exampleModel(),
				Ops: []edit.Op{
					{Op: edit.NodeAdd, Node: &model.Node{ID: "parser", Label: "Parser", Parent: "core"}},
					{Op: edit.EdgeAdd, Edge: &model.Edge{ID: "ui--parser", From: "ui", To: "parser", Label: "sends text to"}},
				},
			}),
			ro, tags),
		registry.Func(p+"diff", "Compare two models",
			func(ctx context.Context, in toolDiffIn) (diffOut, error) {
				base, err := t.doc(in.Base)
				if err != nil {
					return diffOut{}, t.codes.Wrap(err)
				}
				rev, err := t.doc(in.Document)
				if err != nil {
					return diffOut{}, t.codes.Wrap(err)
				}
				return diffOut{Changes: diff.Compare(base, rev, diff.Options{Views: in.Views})}, nil
			},
			registry.Describe("What changed from base to document: nodes and edges added, removed or changed, with each changed field's old and new value. Element order and views are not changes unless views=true."),
			ro, tags),
		registry.Func(p+"query", "Query a model",
			func(ctx context.Context, in toolQueryIn) (queryOut, error) {
				m, err := t.doc(in.Document)
				if err != nil {
					return queryOut{}, t.codes.Wrap(err)
				}
				out, err := ask(m, in.queryArgs)
				return out, t.codes.Wrap(err)
			},
			registry.Describe("Ask a model a structural question. fn=neighbours (node, direction out|in|both, depth), paths (from, to, maxLen, maxPaths: each path as edge ids), impact (node: everything reachable forward from the area or anything inside it), search (filter: text, kinds, tags)."),
			ro, tags),
		registry.Func(p+"export", "Export a model",
			func(ctx context.Context, in toolExportIn) (exportOut, error) {
				m, err := t.doc(in.Document)
				if err != nil {
					return exportOut{}, t.codes.Wrap(err)
				}
				out, err := exportAs(m, in.Format)
				return out, t.codes.Wrap(err)
			},
			registry.Describe("Write a model as text: outline (compact Markdown, the cheapest way to read a large model back), mermaid (flowchart), dot (Graphviz), svg (static nested blocks) or csv (nodes table in text, edges table in edges)."),
			ro, tags),
		registry.Func(p+"open", "Open a model in the modeller",
			func(ctx context.Context, in openIn) (openOut, error) {
				if t.d.Editor == "" {
					return openOut{}, t.codes.Wrap(errNoEditor)
				}
				m, err := t.doc(in.Document)
				if err != nil {
					return openOut{}, t.codes.Wrap(err)
				}
				url, err := Link(t.d.Editor, m)
				return openOut{URL: url}, t.codes.Wrap(err)
			},
			registry.Describe("A link that opens the model in Craggy Modelling, a visual editor in the browser, for a person to view and edit. The model travels inside the link's fragment, which browsers never send to a server. Give the link to the user; they can save the model from the modeller as a .json file."),
			ro, tags),
	}
}

var errNoEditor = errors.New("this server has no modeller address to link to")

// exampleModel is the document the apply example edits.
func exampleModel() model.Model {
	m := model.New("Notes app", "")
	m.Nodes = []model.Node{{ID: "ui", Label: "UI"}, {ID: "core", Label: "Core"}}
	return m
}

const formatGuide = `A document is {"format": "craggy.model", "version": 2, "title", "subject" (what the model describes), "notes"?, "tags"?, "nodes": [{"id", "label", "parent"? (the containing node's id), "kind"?, "notes"?, "tags"?, "properties"? (string, number or bool values), "evidence"? [{"caption", "ref": {"scheme", "id", "selector"?}}], "link"?}], "edges": [{"id", "from", "to", "label", "kind"?, "undirected"?, "notes"?, "tags"?, "properties"?, "evidence"?}], "views"?}. Ids are short slugs. Containment (parent) is acyclic; edges never imply it.`

const opsGuide = "Operations: node.add {node, index?}, node.remove {id, cascade?}, node.move {id, parent, index?}, node.set {id, fields: label|kind|notes|tags|link}, edge.add {edge}, edge.remove {id}, edge.set {id, fields: label|from|to|kind|undirected|notes|tags}, prop.set/prop.unset {target: node|edge, id, key, value}, evidence.add {target, id, evidence}, evidence.remove {target, id, evidenceId}, model.set {fields: title|subject|notes|profile|tags}, view.put {view}, view.remove {id}. In fields, null clears."
