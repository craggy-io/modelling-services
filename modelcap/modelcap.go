// Package modelcap serves models as capability-services capabilities over a
// Store the host implements: <prefix>.list, .read, .create, .update, .apply,
// .attach, .diff, .lint, .query and .export.
//
// The host owns storage, identity and policy: what a scope is (a lab, a
// workspace), which models are read-only, what a ref must resolve to. Every
// capability addresses one scope through its "id" input, so a host can confine
// callers to a scope with one middleware.
package modelcap

import (
	"context"
	"errors"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

// Store keeps model revisions. S is the host's summary of one revision, as
// <prefix>.list returns it.
type Store[S any] interface {
	// List is every model revision in scope, in the host's order.
	List(ctx context.Context, scope string) ([]S, error)
	// Read is one stored revision.
	Read(ctx context.Context, scope, id string) (model.Model, error)
	// Create stores m as a new model. basedOn, when set, names the model it
	// was built from (the host records it; Create need not read it).
	Create(ctx context.Context, scope string, m model.Model, basedOn string) (Saved, error)
	// Revise stores m as the next revision of model id. how says which
	// capability asked: "update", "apply" or "attach". The host refuses
	// read-only models here.
	Revise(ctx context.Context, scope, id string, m model.Model, how string) (Saved, error)
}

// Saved is one stored revision. Receipt is the host's record of the write
// (a run id, say), opaque to this package.
type Saved struct {
	ID      string `json:"model" jsonschema:"id of the stored model revision"`
	Receipt string `json:"receipt,omitempty" jsonschema:"the host's record of the write"`
}

// Profiles resolves a model's profile name (Model.Profile) in scope. It
// returns nil when the name is unknown; lint then skips profile rules.
type Profiles func(ctx context.Context, scope, ref string) (*model.Profile, error)

// Deps is what the capabilities need.
type Deps[S any] struct {
	Store    Store[S]
	Prefix   string // capability name prefix, e.g. "models"
	Limits   model.Limits
	Profiles Profiles
	// Codes maps the Store's errors to registry codes. model.ErrInvalid is
	// always mapped to registry.Invalid.
	Codes registry.Codes
	// Tags are added to every capability (the host's scope middleware tag).
	Tags []string
}

// Service serves the model capabilities.
type Service[S any] struct {
	d     Deps[S]
	codes registry.Codes
}

// New builds the service.
func New[S any](d Deps[S]) *Service[S] {
	codes := registry.Codes{model.ErrInvalid: registry.Invalid}
	for k, v := range d.Codes {
		codes[k] = v
	}
	return &Service[S]{d: d, codes: codes}
}

// Group is the capability group to register with the capabilities.
func (s *Service[S]) Group() registry.Group {
	return registry.Group{Name: s.d.Prefix, Description: "Block models: nested areas, relationships and cited evidence. List, read, create, revise with small operations, attach evidence, compare revisions, lint, query and export."}
}

// read is one revision, re-validated.
func (s *Service[S]) read(ctx context.Context, scope, id string) (model.Model, error) {
	m, err := s.d.Store.Read(ctx, scope, id)
	if err != nil {
		return m, err
	}
	return m, m.Validate(s.d.Limits)
}

// lint is the findings worth showing a writer: errors and warnings.
func (s *Service[S]) lint(ctx context.Context, scope string, m model.Model) ([]query.Finding, error) {
	all, err := s.lintAll(ctx, scope, m)
	var out []query.Finding
	for _, f := range all {
		if f.Severity != query.Info {
			out = append(out, f)
		}
	}
	return out, err
}

func (s *Service[S]) lintAll(ctx context.Context, scope string, m model.Model) ([]query.Finding, error) {
	var profile *model.Profile
	if m.Profile != "" && s.d.Profiles != nil {
		p, err := s.d.Profiles(ctx, scope, m.Profile)
		if err != nil {
			return nil, err
		}
		profile = p
	}
	return query.Lint(model.NewIndex(m), profile), nil
}

// saved is a write's output: the stored revision, its document and the
// writer's lint findings.
func (s *Service[S]) saved(ctx context.Context, scope string, sv Saved, m model.Model, err error) (writeOut, error) {
	if err != nil {
		return writeOut{}, s.codes.Wrap(err)
	}
	findings, err := s.lint(ctx, scope, m)
	if err != nil {
		return writeOut{}, s.codes.Wrap(err)
	}
	return writeOut{Scope: scope, Saved: sv, Document: m, Lint: findings}, nil
}

// create validates m and stores it.
func (s *Service[S]) create(ctx context.Context, scope string, m model.Model, basedOn string) (Saved, error) {
	if basedOn != "" {
		if _, err := s.read(ctx, scope, basedOn); err != nil {
			return Saved{}, err
		}
	}
	if err := m.Validate(s.d.Limits); err != nil {
		return Saved{}, err
	}
	return s.d.Store.Create(ctx, scope, m, basedOn)
}

// revise validates m and stores it as id's next revision.
func (s *Service[S]) revise(ctx context.Context, scope, id string, m model.Model, how string) (Saved, error) {
	if err := m.Validate(s.d.Limits); err != nil {
		return Saved{}, err
	}
	return s.d.Store.Revise(ctx, scope, id, m, how)
}

var errFormat = errors.New("unknown format")
