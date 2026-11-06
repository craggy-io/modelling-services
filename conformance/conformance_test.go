// Package conformance runs the shared vectors in this directory against the
// Go implementation. The Dart implementation runs the same files
// (clients/dart/modelling/test/conformance_test.dart).
//
// Hand-written inputs live in <area>.json. Generated expectations live in
// expected/<area>.json, keyed by case name: regenerate them with
// `go test ./conformance -update`, then review the diff before committing.
package conformance

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/craggy-io/foundation-kit/canonjson"

	"github.com/craggy-io/modelling-services/diff"
	"github.com/craggy-io/modelling-services/edit"
	"github.com/craggy-io/modelling-services/export"
	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/query"
)

var update = flag.Bool("update", false, "rewrite expected/*.json from the Go implementation")

type rawCase map[string]json.RawMessage

func (c rawCase) name() string {
	var s string
	_ = json.Unmarshal(c["name"], &s)
	return s
}

func (c rawCase) str(key string) string {
	var s string
	_ = json.Unmarshal(c[key], &s)
	return s
}

func load(t *testing.T, file, list string) []rawCase {
	t.Helper()
	raw, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("%s: %v", file, err)
	}
	var cases []rawCase
	if err := json.Unmarshal(doc[list], &cases); err != nil {
		t.Fatalf("%s %s: %v", file, list, err)
	}
	return cases
}

// resolve reads a field that may be "@fixture", "@mermaid:fixture" or
// "@outline:fixture" (that fixture's export), or inline JSON.
func resolve(t *testing.T, raw json.RawMessage) json.RawMessage {
	t.Helper()
	var ref string
	if json.Unmarshal(raw, &ref) != nil || !strings.HasPrefix(ref, "@") {
		return raw
	}
	ref = ref[1:]
	if format, name, ok := strings.Cut(ref, ":"); ok {
		m := decode(t, resolve(t, json.RawMessage(`"@`+name+`"`)))
		text := map[string]func(model.Model) string{"mermaid": export.Mermaid, "outline": export.Outline}[format](m)
		out, _ := json.Marshal(text)
		return out
	}
	data, err := os.ReadFile(filepath.Join("fixtures", ref+".json"))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func decode(t *testing.T, raw json.RawMessage) model.Model {
	t.Helper()
	m, err := model.Decode(raw)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	return m
}

func canonical(t *testing.T, v any) string {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	out, err := canonjson.Normalize(raw)
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

// expected compares got with expected/<area>.json[name], or records it
// under -update.
type expected struct {
	area string
	want map[string]json.RawMessage
	got  map[string]any
}

func openExpected(t *testing.T, area string) *expected {
	e := &expected{area: area, want: map[string]json.RawMessage{}, got: map[string]any{}}
	raw, err := os.ReadFile(filepath.Join("expected", area+".json"))
	if err == nil {
		if err := json.Unmarshal(raw, &e.want); err != nil {
			t.Fatal(err)
		}
	} else if !*update {
		t.Fatalf("expected/%s.json missing; run go test ./conformance -update", area)
	}
	t.Cleanup(func() {
		if !*update || t.Failed() {
			return
		}
		raw, _ := json.MarshalIndent(e.got, "", "  ")
		raw = bytes.ReplaceAll(raw, []byte(`<`), []byte("<"))
		raw = bytes.ReplaceAll(raw, []byte(`>`), []byte(">"))
		raw = bytes.ReplaceAll(raw, []byte(`&`), []byte("&"))
		_ = os.MkdirAll("expected", 0o755)
		if err := os.WriteFile(filepath.Join("expected", area+".json"), append(raw, '\n'), 0o644); err != nil {
			t.Error(err)
		}
	})
	return e
}

func (e *expected) check(t *testing.T, name string, got any) {
	t.Helper()
	e.got[name] = got
	if *update {
		return
	}
	want, ok := e.want[name]
	if !ok {
		t.Fatalf("expected/%s.json has no %q; run -update", e.area, name)
	}
	var w any
	_ = json.Unmarshal(want, &w)
	if g, x := canonical(t, got), canonical(t, w); g != x {
		t.Errorf("%s: got\n%s\nwant\n%s", name, g, x)
	}
}

func TestDocuments(t *testing.T) {
	for _, c := range load(t, "documents.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			var limits model.Limits
			if l, ok := c["limits"]; ok {
				var x struct{ MaxDepth, MaxNodes, MaxRefs, MaxEdges int }
				_ = json.Unmarshal(l, &x)
				limits = model.Limits{MaxDepth: x.MaxDepth, MaxNodes: x.MaxNodes, MaxRefs: x.MaxRefs, MaxEdges: x.MaxEdges}
			}
			raw := c["document"]
			if r := c.str("raw"); r != "" {
				raw = json.RawMessage(r)
			}
			m, err := model.Decode(resolve(t, raw))
			var wantDecodeError bool
			_ = json.Unmarshal(c["decodeError"], &wantDecodeError)
			if wantDecodeError != (err != nil) {
				t.Fatalf("decode error = %v, want error %v", err, wantDecodeError)
			}
			if err != nil {
				if !errors.Is(err, model.ErrInvalid) {
					t.Fatalf("decode error %v is not ErrInvalid", err)
				}
				return
			}
			var codes []string
			for _, is := range m.Issues(limits) {
				codes = append(codes, is.Code)
			}
			var want []string
			_ = json.Unmarshal(c["issues"], &want)
			if fmt.Sprint(codes) != fmt.Sprint(want) {
				t.Errorf("issues %v, want %v", codes, want)
			}
			if enc := c.str("encoded"); enc != "" {
				got, err := model.Encode(m)
				if err != nil || string(got) != enc {
					t.Errorf("encoded\n%s\nwant\n%s (%v)", got, enc, err)
				}
			}
			if len(codes) == 0 {
				again := decode(t, mustEncode(t, m))
				if !model.Equal(m, again) {
					t.Error("encode/decode round trip changed the model")
				}
			}
		})
	}
}

func mustEncode(t *testing.T, m model.Model) []byte {
	raw, err := model.Encode(m)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestMigrate(t *testing.T) {
	for _, c := range load(t, "migrate.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			got, want := decode(t, c["v1"]), decode(t, c["expected"])
			if err := got.Validate(model.Limits{}); err != nil {
				t.Fatal(err)
			}
			if !model.Equal(got, want) {
				t.Errorf("got %s", mustEncode(t, got))
			}
		})
	}
}

func TestDiff(t *testing.T) {
	exp := openExpected(t, "diff")
	for _, c := range load(t, "diff.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			var views bool
			_ = json.Unmarshal(c["views"], &views)
			cs := diff.Compare(decode(t, resolve(t, c["base"])), decode(t, resolve(t, c["revision"])), diff.Options{Views: views})
			if want, ok := c["changes"]; ok {
				var w any
				_ = json.Unmarshal(want, &w)
				if canonical(t, cs) != canonical(t, w) {
					t.Errorf("changes %s, want %s", canonical(t, cs), want)
				}
			}
			exp.check(t, c.name(), cs)
		})
	}
}

func TestEdit(t *testing.T) {
	exp := openExpected(t, "edit")
	for _, c := range load(t, "edit.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			m := decode(t, resolve(t, c["model"]))
			var ops []edit.Op
			if err := json.Unmarshal(c["ops"], &ops); err != nil {
				t.Fatal(err)
			}
			result, inverse, err := edit.Apply(m, ops, model.Limits{})
			if wantErr, ok := c["error"]; ok {
				var e *edit.Error
				if !errors.As(err, &e) {
					t.Fatalf("got %v, want error %s", err, wantErr)
				}
				got := map[string]any{"index": e.Index, "code": e.Code}
				if canonical(t, got) != canonical(t, json.RawMessage(wantErr)) {
					t.Fatalf("error %v, want %s", got, wantErr)
				}
				exp.check(t, c.name(), map[string]any{"error": got})
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			back, _, err := edit.Apply(result, inverse, model.Limits{})
			if err != nil {
				t.Fatalf("inverse: %v", err)
			}
			if !model.Equal(back, m) {
				t.Errorf("inverse did not restore the model:\n%s", mustEncode(t, back))
			}
			exp.check(t, c.name(), map[string]any{"result": json.RawMessage(mustEncode(t, result)), "inverse": inverse})
		})
	}
}

func TestQuery(t *testing.T) {
	exp := openExpected(t, "query")
	for _, c := range load(t, "query.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			ix := model.NewIndex(decode(t, resolve(t, c["model"])))
			var a struct {
				Filter           model.Filter
				ID, From, To     string
				Direction        query.Direction
				Depth            int
				MaxLen, MaxPaths int
			}
			if err := json.Unmarshal(c["args"], &a); err != nil {
				t.Fatal(err)
			}
			var got any
			switch c.str("fn") {
			case "search":
				got = list(query.Search(ix, a.Filter))
			case "neighbours":
				got = list(query.Neighbours(ix, a.ID, a.Direction, a.Depth))
			case "paths":
				p := query.Paths(ix, a.From, a.To, a.MaxLen, a.MaxPaths)
				if p == nil {
					p = [][]string{}
				}
				got = p
			case "impact":
				got = list(query.Impact(ix, a.ID))
			case "descendants":
				got = list(ix.Descendants(a.ID))
			case "ancestors":
				got = list(ix.Ancestors(a.ID))
			default:
				t.Fatalf("unknown fn %q", c.str("fn"))
			}
			exp.check(t, c.name(), got)
		})
	}
}

func list(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func TestLint(t *testing.T) {
	exp := openExpected(t, "lint")
	for _, c := range load(t, "lint.json", "cases") {
		t.Run(c.name(), func(t *testing.T) {
			ix := model.NewIndex(decode(t, resolve(t, c["model"])))
			var profile *model.Profile
			if raw, ok := c["profile"]; ok {
				p, err := model.DecodeProfile(resolve(t, raw))
				if err != nil {
					t.Fatal(err)
				}
				profile = &p
			}
			got := []map[string]any{}
			for _, f := range query.Lint(ix, profile) {
				got = append(got, map[string]any{"rule": f.Rule, "element": f.Element, "severity": f.Severity})
			}
			exp.check(t, c.name(), got)
		})
	}
}

func TestExport(t *testing.T) {
	exp := openExpected(t, "export")
	for _, c := range load(t, "export.json", "export") {
		t.Run(c.name(), func(t *testing.T) {
			m := decode(t, resolve(t, c["model"]))
			exp.check(t, "export: "+c.name(), map[string]string{"mermaid": export.Mermaid(m), "outline": export.Outline(m)})
		})
	}
	for _, c := range load(t, "export.json", "import") {
		t.Run(c.name(), func(t *testing.T) {
			var src string
			_ = json.Unmarshal(resolve(t, c["source"]), &src)
			parse := map[string]func(string) (model.Model, error){"mermaid": export.ParseMermaid, "outline": export.ParseOutline}[c.str("format")]
			m, err := parse(src)
			var wantErr bool
			_ = json.Unmarshal(c["error"], &wantErr)
			if wantErr != (err != nil) {
				t.Fatalf("error = %v, want error %v", err, wantErr)
			}
			if err != nil {
				exp.check(t, "import: "+c.name(), map[string]any{"error": true})
				return
			}
			if err := m.Validate(model.Limits{}); err != nil {
				t.Fatalf("imported model is invalid: %v", err)
			}
			exp.check(t, "import: "+c.name(), json.RawMessage(mustEncode(t, m)))
		})
	}
}
