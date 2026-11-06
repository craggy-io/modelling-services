// Package kinds declares the foundation-kit bundle kinds for modelling
// content, so hosts can ship model profiles and template models in bundles:
//
//	craggy.model-profile@1  one profile (JSON or YAML), contribution id = profile id
//	craggy.model@1          one template model (JSON or YAML, format version 1 or 2)
//
// Register Compilers() with the host catalog and read definitions with
// bundle.Lookup on ProfileKind or ModelKind.
package kinds

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/craggy-io/foundation-kit/bundle"
	"github.com/craggy-io/foundation-kit/bundle/compile"
	"github.com/craggy-io/foundation-kit/kind"

	"github.com/craggy-io/modelling-services/model"
)

// ProfileKind is craggy.model-profile@1.
var ProfileKind = kind.New[model.Profile]("craggy.model-profile", 1, kind.Global())

// ModelKind is craggy.model@1: a template model.
var ModelKind = kind.New[model.Model]("craggy.model", 1, kind.Global())

// Compilers are the modelling kinds' compilers, for the host catalog.
func Compilers() []bundle.AnyCompiler {
	return []bundle.AnyCompiler{
		bundle.Compile(ProfileKind, compileProfile),
		bundle.Compile(ModelKind, compileModel),
	}
}

func compileProfile(ctx context.Context, c bundle.Contribution) (bundle.Compiled[model.Profile], []bundle.Diagnostic) {
	raw, diags := compile.YAML[json.RawMessage]()(ctx, c)
	if len(diags) > 0 {
		return bundle.Compiled[model.Profile]{}, diags
	}
	p, err := model.DecodeProfile(raw.Value)
	if err == nil && p.ID != c.Ref.ID {
		err = fmt.Errorf("profile id %q must equal the contribution id %q", p.ID, c.Ref.ID)
	}
	if err != nil {
		return bundle.Compiled[model.Profile]{}, []bundle.Diagnostic{diagnostic(c, err)}
	}
	return bundle.Compiled[model.Profile]{Value: p}, nil
}

func compileModel(ctx context.Context, c bundle.Contribution) (bundle.Compiled[model.Model], []bundle.Diagnostic) {
	raw, diags := compile.YAML[json.RawMessage]()(ctx, c)
	if len(diags) > 0 {
		return bundle.Compiled[model.Model]{}, diags
	}
	m, err := model.Decode(raw.Value)
	if err == nil {
		err = m.Validate(model.Limits{})
	}
	if err != nil {
		return bundle.Compiled[model.Model]{}, []bundle.Diagnostic{diagnostic(c, err)}
	}
	return bundle.Compiled[model.Model]{Value: m}, nil
}

func diagnostic(c bundle.Contribution, err error) bundle.Diagnostic {
	return bundle.Diagnostic{
		Code: "craggy.model.invalid", Severity: bundle.SeverityError,
		Bundle: c.Bundle.ID, Contribution: c.Ref.ID, Path: c.Path, Message: err.Error(),
	}
}
