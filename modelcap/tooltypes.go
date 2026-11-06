package modelcap

import (
	"github.com/craggy-io/modelling-services/edit"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

type checkIn struct {
	Document model.Model    `json:"document" jsonschema:"the model document"`
	Profile  *model.Profile `json:"profile,omitempty" jsonschema:"a profile to check kinds, containment and typed properties against"`
	All      bool           `json:"all,omitempty" jsonschema:"include informational lint findings"`
}

type checkOut struct {
	Valid    bool            `json:"valid"`
	Issues   []model.Issue   `json:"issues" jsonschema:"validation issues; the model is valid when there are none"`
	Lint     []query.Finding `json:"lint" jsonschema:"lint findings of a valid model"`
	Document *model.Model    `json:"document,omitempty" jsonschema:"the valid document, normalized"`
}

type toolImportIn struct {
	importIn
	Profile *model.Profile `json:"profile,omitempty" jsonschema:"a profile to lint against"`
}

type docOut struct {
	Document model.Model     `json:"document" jsonschema:"the model document"`
	Lint     []query.Finding `json:"lint" jsonschema:"lint errors and warnings, worth fixing"`
}

type toolApplyIn struct {
	Document model.Model    `json:"document" jsonschema:"the model document to edit"`
	Ops      []edit.Op      `json:"ops" jsonschema:"operations, applied in order, all or nothing"`
	Profile  *model.Profile `json:"profile,omitempty" jsonschema:"a profile to lint the result against"`
}

type toolApplyOut struct {
	docOut
	Inverse []edit.Op `json:"inverse" jsonschema:"operations that undo this change"`
}

type toolDiffIn struct {
	Base     model.Model `json:"base" jsonschema:"the earlier model document"`
	Document model.Model `json:"document" jsonschema:"the later model document"`
	Views    bool        `json:"views,omitempty" jsonschema:"count saved-view changes too"`
}

type toolQueryIn struct {
	Document model.Model `json:"document" jsonschema:"the model document"`
	queryArgs
}

type toolExportIn struct {
	Document model.Model `json:"document" jsonschema:"the model document"`
	Format   string      `json:"format" jsonschema:"outline, mermaid, dot, svg or csv"`
}

type openIn struct {
	Document model.Model `json:"document" jsonschema:"the model document to open"`
}

type openOut struct {
	URL string `json:"url" jsonschema:"a link that opens the model in the modeller"`
}
