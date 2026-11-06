package modelcap_test

import (
	"bytes"
	"compress/flate"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/modelcap"
)

var updateLink = flag.Bool("update-link", false, "rewrite conformance/link.json from the Go encoder")

func toolsSetup(t *testing.T) *registry.Registry {
	t.Helper()
	tools := modelcap.NewTools(modelcap.ToolDeps{Prefix: "model", Editor: "https://models.example/#ignored"})
	r := registry.New()
	t.Cleanup(func() { r.Close() })
	if err := r.Add(tools.Capabilities()...); err != nil {
		t.Fatal(err)
	}
	return r
}

const twoAreas = `{"format":"craggy.model","version":2,"title":"T","subject":"s","nodes":[{"id":"a","label":"A"},{"id":"b","label":"B","parent":"a"}],"edges":[]}`

func TestToolsImportApplyExport(t *testing.T) {
	r := toolsSetup(t)
	imported := call(t, r, "model.import", `{"format":"outline","source":"# Shop\n\nWeb shop\n\n- **Web** `+"`web`"+`\n  - **Cart** `+"`cart`"+`\n- **Db** `+"`db`"+`\n\n## Relationships\n\n- `+"`cart` -> `db`"+`: stores in `+"`e1`"+`\n"}`)
	doc, _ := json.Marshal(imported["document"])
	if !strings.Contains(string(doc), `"parent":"web"`) || !strings.Contains(string(doc), `"from":"cart"`) {
		t.Fatalf("import: %s", doc)
	}
	applied := call(t, r, "model.apply", `{"document":`+string(doc)+`,"ops":[{"op":"node.add","node":{"id":"api","label":"API","parent":"web"}}]}`)
	if len(applied["inverse"].([]any)) != 1 {
		t.Fatalf("apply: %v", applied)
	}
	next, _ := json.Marshal(applied["document"])
	out := call(t, r, "model.export", `{"document":`+string(next)+`,"format":"outline"}`)
	if !strings.Contains(out["text"].(string), "**API** `api`") {
		t.Fatalf("export: %v", out)
	}
	changes := call(t, r, "model.diff", `{"base":`+string(doc)+`,"document":`+string(next)+`}`)
	if !strings.Contains(mustJSON(t, changes), `"api"`) {
		t.Fatalf("diff: %v", changes)
	}
	q := call(t, r, "model.query", `{"document":`+string(next)+`,"fn":"impact","node":"web"}`)
	if !strings.Contains(mustJSON(t, q), `"db"`) {
		t.Fatalf("query: %v", q)
	}
}

func TestToolsCheck(t *testing.T) {
	r := toolsSetup(t)
	ok := call(t, r, "model.check", `{"document":`+twoAreas+`}`)
	if ok["valid"] != true || ok["document"] == nil {
		t.Fatalf("valid: %v", ok)
	}
	bad := call(t, r, "model.check", `{"document":{"format":"craggy.model","version":2,"title":"T","subject":"s","nodes":[{"id":"a","label":"A","parent":"zz"}],"edges":[]}}`)
	if bad["valid"] != false || len(bad["issues"].([]any)) == 0 || bad["document"] != nil {
		t.Fatalf("invalid: %v", bad)
	}
	profiled := call(t, r, "model.check", `{"document":`+twoAreas+`,"profile":{"id":"p","version":1,"requireKinds":true}}`)
	if len(profiled["lint"].([]any)) == 0 {
		t.Fatalf("profile lint: %v", profiled)
	}
}

func TestToolsRefuseInvalid(t *testing.T) {
	r := toolsSetup(t)
	_, err := r.Invoke(context.Background(), "model.apply", json.RawMessage(`{"document":`+twoAreas+`,"ops":[{"op":"node.remove","id":"nope"}]}`))
	var re *registry.Error
	if !errors.As(err, &re) || re.Code != registry.Invalid {
		t.Fatalf("want invalid, got %v", err)
	}
}

func TestToolsOpen(t *testing.T) {
	r := toolsSetup(t)
	out := call(t, r, "model.open", `{"document":`+twoAreas+`}`)
	url := out["url"].(string)
	if !strings.HasPrefix(url, "https://models.example/#m=") {
		t.Fatalf("url: %s", url)
	}
	m, err := model.Decode(inflate(t, strings.TrimPrefix(url, "https://models.example/#m=")))
	if err != nil || m.Title != "T" || len(m.Nodes) != 2 {
		t.Fatalf("round trip: %v %v", m, err)
	}
}

// TestLinkVector keeps conformance/link.json decodable: the modeller's
// decoder reads the same file. Regenerate with -update-link.
func TestLinkVector(t *testing.T) {
	const path = "../conformance/link.json"
	fixture, err := os.ReadFile("../conformance/fixtures/app.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := model.Decode(fixture)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := model.Encode(m)
	if *updateLink {
		link, err := modelcap.Link("", m)
		if err != nil {
			t.Fatal(err)
		}
		v, _ := json.MarshalIndent(map[string]string{"fixture": "fixtures/app.json", "fragment": strings.TrimPrefix(link, "#m=")}, "", "  ")
		if err := os.WriteFile(path, append(v, '\n'), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var v struct{ Fragment string }
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	if got := inflate(t, v.Fragment); !bytes.Equal(got, want) {
		t.Fatalf("link vector decodes to\n%s\nwant\n%s", got, want)
	}
}

func inflate(t *testing.T, fragment string) []byte {
	t.Helper()
	packed, err := base64.RawURLEncoding.DecodeString(fragment)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := io.ReadAll(flate.NewReader(bytes.NewReader(packed)))
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
