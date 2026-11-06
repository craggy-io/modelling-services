package modelcap

import (
	"fmt"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/diff"
	"github.com/craggy-io/modelling-services/edit"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

type listIn struct {
	Scope string `json:"id" jsonschema:"the scope the models live in (the host's id, e.g. a lab id)"`
	registry.PageIn
}

type listOut[S any] struct {
	Models []S    `json:"models" jsonschema:"one page of model revisions"`
	Next   string `json:"next,omitempty" jsonschema:"cursor for the next page; empty on the last"`
}

type readIn struct {
	Scope  string `json:"id" jsonschema:"the scope the models live in"`
	Model  string `json:"model" jsonschema:"model revision id"`
	Format string `json:"format,omitempty" jsonschema:"json (default), outline or mermaid"`
}

type readOut struct {
	Scope    string       `json:"id"`
	Model    string       `json:"model"`
	Document *model.Model `json:"document,omitempty" jsonschema:"the model document (format json)"`
	Text     string       `json:"text,omitempty" jsonschema:"the model as text (format outline or mermaid)"`
}

type importIn struct {
	Format string `json:"format" jsonschema:"mermaid, outline or csv"`
	Source string `json:"source" jsonschema:"the text to import (for csv, the nodes table)"`
	Edges  string `json:"edges,omitempty" jsonschema:"for csv, the edges table"`
	Title  string `json:"title,omitempty" jsonschema:"title for a csv import"`
}

type createIn struct {
	Scope    string       `json:"id" jsonschema:"the scope the models live in"`
	Document *model.Model `json:"document,omitempty" jsonschema:"the complete model document; give document or import"`
	Import   *importIn    `json:"import,omitempty" jsonschema:"text to import instead of a document"`
	BasedOn  string       `json:"basedOn,omitempty" jsonschema:"model revision this model starts from, recorded as lineage and left unchanged"`
}

// model is the document to create: the given one, or the import parsed.
func (in createIn) model() (model.Model, error) {
	if (in.Document == nil) == (in.Import == nil) {
		return model.Model{}, fmt.Errorf("%w: give a document or an import, not both or neither", model.ErrInvalid)
	}
	if in.Document != nil {
		return normalize(*in.Document)
	}
	return in.Import.parse()
}

type updateIn struct {
	Scope    string      `json:"id" jsonschema:"the scope the models live in"`
	Model    string      `json:"model" jsonschema:"model revision this document replaces (read it first)"`
	Document model.Model `json:"document" jsonschema:"the complete replacement document; keep what you do not mean to change"`
}

type applyIn struct {
	Scope string    `json:"id" jsonschema:"the scope the models live in"`
	Model string    `json:"model" jsonschema:"model revision to edit"`
	Ops   []edit.Op `json:"ops" jsonschema:"operations, applied in order, all or nothing"`
}

type attachIn struct {
	Scope    string           `json:"id" jsonschema:"the scope the models live in"`
	Model    string           `json:"model" jsonschema:"model revision to extend"`
	Node     string           `json:"node,omitempty" jsonschema:"node to cite on; give node or edge, not both"`
	Edge     string           `json:"edge,omitempty" jsonschema:"edge to cite on"`
	Evidence []model.Evidence `json:"evidence" jsonschema:"evidence to add: caption and ref {scheme, id, selector?}; id is optional"`
}

type writeOut struct {
	Scope string `json:"id"`
	Saved
	Document model.Model     `json:"document" jsonschema:"the stored document"`
	Lint     []query.Finding `json:"lint,omitempty" jsonschema:"lint errors and warnings in the stored model, worth fixing"`
}

type applyOut struct {
	writeOut
	Inverse []edit.Op `json:"inverse" jsonschema:"operations that undo this change"`
}

type diffIn struct {
	Scope string `json:"id" jsonschema:"the scope the models live in"`
	Base  string `json:"base" jsonschema:"the earlier model revision"`
	Model string `json:"model" jsonschema:"the later model revision"`
	Views bool   `json:"views,omitempty" jsonschema:"count saved-view changes too"`
}

type diffOut struct {
	Changes diff.ChangeSet `json:"changes"`
}

type lintIn struct {
	Scope string `json:"id" jsonschema:"the scope the models live in"`
	Model string `json:"model" jsonschema:"model revision"`
	All   bool   `json:"all,omitempty" jsonschema:"include informational findings"`
}

type lintOut struct {
	Findings []query.Finding `json:"findings"`
}

type queryIn struct {
	Scope string `json:"id" jsonschema:"the scope the models live in"`
	Model string `json:"model" jsonschema:"model revision"`
	queryArgs
}

// queryArgs is the question a query asks.
type queryArgs struct {
	Fn        string          `json:"fn" jsonschema:"neighbours, paths, impact or search"`
	ID        string          `json:"node,omitempty" jsonschema:"node for neighbours and impact"`
	Direction query.Direction `json:"direction,omitempty" jsonschema:"out, in or both (default)"`
	Depth     int             `json:"depth,omitempty" jsonschema:"neighbours: how many edges away (default 1)"`
	From      string          `json:"from,omitempty" jsonschema:"paths: start node"`
	To        string          `json:"to,omitempty" jsonschema:"paths: end node"`
	MaxLen    int             `json:"maxLen,omitempty" jsonschema:"paths: longest path in edges (default 6)"`
	MaxPaths  int             `json:"maxPaths,omitempty" jsonschema:"paths: most paths returned (default 20)"`
	Filter    *model.Filter   `json:"filter,omitempty" jsonschema:"search: text, kinds and tags"`
}

type queryOut struct {
	Nodes []string   `json:"nodes,omitempty" jsonschema:"node ids, in a stable order"`
	Paths [][]string `json:"paths,omitempty" jsonschema:"paths, each as the edge ids it follows"`
}

type exportIn struct {
	Scope  string `json:"id" jsonschema:"the scope the models live in"`
	Model  string `json:"model" jsonschema:"model revision"`
	Format string `json:"format" jsonschema:"mermaid, dot, outline, svg or csv"`
}

type exportOut struct {
	Text  string `json:"text"`
	Edges string `json:"edges,omitempty" jsonschema:"csv only: the edges table"`
}
