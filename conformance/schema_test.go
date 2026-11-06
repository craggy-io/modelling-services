package conformance

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/jsonschema-go/jsonschema"

	"github.com/craggy-io/modelling-services/model"
)

func schema(t *testing.T, name string) *jsonschema.Resolved {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "schema", name))
	if err != nil {
		t.Fatal(err)
	}
	var s jsonschema.Schema
	if err := json.Unmarshal(raw, &s); err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	res, err := s.Resolve(nil)
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return res
}

func conforms(t *testing.T, res *jsonschema.Resolved, what string, raw []byte) {
	t.Helper()
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	if err := res.Validate(v); err != nil {
		t.Errorf("%s does not match the schema: %v", what, err)
	}
}

// TestSchemas checks that every valid model the vectors produce matches
// schema/model.v2, every v1 input matches model.v1 and the profile fixture
// matches profile.v1, so the published schemas agree with the code.
func TestSchemas(t *testing.T) {
	v2, v1, profile := schema(t, "model.v2.schema.json"), schema(t, "model.v1.schema.json"), schema(t, "profile.v1.schema.json")
	check := func(what string, m model.Model) {
		if len(m.Issues(model.Limits{})) == 0 {
			conforms(t, v2, what, mustEncode(t, m))
		}
	}
	for _, c := range load(t, "documents.json", "cases") {
		if c["document"] != nil {
			if m, err := model.Decode(resolve(t, c["document"])); err == nil {
				check("documents: "+c.name(), m)
			}
		}
	}
	for _, c := range load(t, "migrate.json", "cases") {
		conforms(t, v1, "migrate v1: "+c.name(), c["v1"])
		check("migrate: "+c.name(), decode(t, c["expected"]))
	}
	var edits map[string]struct{ Result json.RawMessage }
	raw, _ := os.ReadFile(filepath.Join("expected", "edit.json"))
	_ = json.Unmarshal(raw, &edits)
	for name, e := range edits {
		if e.Result != nil {
			conforms(t, v2, "edit: "+name, e.Result)
		}
	}
	p, _ := os.ReadFile(filepath.Join("fixtures", "android-profile.json"))
	conforms(t, profile, "android profile", p)
}
