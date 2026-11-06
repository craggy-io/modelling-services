package modelcap_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/craggy-io/capability-services/registry"

	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/modelcap"
)

var (
	errReadOnly = errors.New("read-only")
	errNotFound = errors.New("not found")
)

// memStore keeps revisions in memory; ids starting "sys-" are read-only.
type memStore struct {
	revisions map[string]model.Model
	order     []string
	hows      []string
}

type summary struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

func (s *memStore) List(_ context.Context, scope string) ([]summary, error) {
	var out []summary
	for _, id := range s.order {
		out = append(out, summary{ID: id, Title: s.revisions[id].Title})
	}
	return out, nil
}

func (s *memStore) Read(_ context.Context, scope, id string) (model.Model, error) {
	m, ok := s.revisions[id]
	if !ok {
		return m, fmt.Errorf("%w: no model %s", errNotFound, id)
	}
	return m, nil
}

func (s *memStore) put(m model.Model) modelcap.Saved {
	id := fmt.Sprintf("m%d", len(s.order)+1)
	s.revisions[id] = m
	s.order = append(s.order, id)
	return modelcap.Saved{ID: id, Receipt: "run-" + id}
}

func (s *memStore) Create(_ context.Context, scope string, m model.Model, basedOn string) (modelcap.Saved, error) {
	s.hows = append(s.hows, "create:"+basedOn)
	return s.put(m), nil
}

func (s *memStore) Revise(_ context.Context, scope, id string, m model.Model, how string) (modelcap.Saved, error) {
	if strings.HasPrefix(id, "sys-") {
		return modelcap.Saved{}, errReadOnly
	}
	s.hows = append(s.hows, how+":"+id)
	return s.put(m), nil
}

func setup(t *testing.T) (*registry.Registry, *memStore) {
	t.Helper()
	store := &memStore{revisions: map[string]model.Model{}}
	sys := model.New("Expected", "target")
	sys.Nodes = []model.Node{{ID: "app", Label: "App"}, {ID: "ui", Label: "UI", Parent: "app"}}
	store.revisions["sys-1"] = sys
	store.order = append(store.order, "sys-1")
	svc := modelcap.New(modelcap.Deps[summary]{
		Store: store, Prefix: "models",
		Codes: registry.Codes{errReadOnly: registry.Denied, errNotFound: registry.NotFound},
		Profiles: func(ctx context.Context, scope, ref string) (*model.Profile, error) {
			return &model.Profile{ID: "p", Version: 1, RequireKinds: true}, nil
		},
	})
	r := registry.New()
	t.Cleanup(func() { r.Close() })
	if err := r.Add(svc.Capabilities()...); err != nil {
		t.Fatal(err)
	}
	return r, store
}

func call(t *testing.T, r *registry.Registry, name, in string) map[string]any {
	t.Helper()
	out, err := r.Invoke(context.Background(), name, json.RawMessage(in))
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	var v map[string]any
	if err := json.Unmarshal(out, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestCreateApplyAttachDiff(t *testing.T) {
	r, store := setup(t)
	created := call(t, r, "models.create", `{"id":"lab","basedOn":"sys-1","document":{"format":"craggy.model","version":2,"title":"Observed","subject":"target",
		"nodes":[{"id":"app","label":"App"},{"id":"ui","label":"UI","parent":"app"}],"edges":[]}}`)
	if created["model"] != "m2" || created["receipt"] != "run-m2" || store.hows[0] != "create:sys-1" {
		t.Fatalf("create: %v %v", created, store.hows)
	}
	applied := call(t, r, "models.apply", `{"id":"lab","model":"m2","ops":[
		{"op":"node.add","node":{"id":"net","label":"Network","parent":"app"}},
		{"op":"edge.add","edge":{"id":"e1","from":"ui","to":"net","label":"calls"}}]}`)
	if applied["model"] != "m3" || len(applied["inverse"].([]any)) != 2 {
		t.Fatalf("apply: %v", applied)
	}
	attached := call(t, r, "models.attach", `{"id":"lab","model":"m3","edge":"e1","evidence":[{"caption":"trace","ref":{"scheme":"artifact","id":"a1"}}]}`)
	if attached["model"] != "m4" {
		t.Fatalf("attach: %v", attached)
	}
	again := call(t, r, "models.attach", `{"id":"lab","model":"m4","edge":"e1","evidence":[{"caption":"same ref","ref":{"scheme":"artifact","id":"a1"}}]}`)
	if again["model"] != "m4" || again["receipt"] != nil {
		t.Fatalf("attach of a known ref stored a revision: %v", again)
	}
	updated := call(t, r, "models.update", `{"id":"lab","model":"m4","document":{"format":"craggy.model","version":2,"title":"Observed","subject":"target",
		"nodes":[{"id":"app","label":"App","evidence":[{"caption":"no id given","ref":{"scheme":"url","id":"https://x"}}]}],"edges":[]}}`)
	if updated["model"] != "m5" {
		t.Fatalf("update: %v", updated)
	}
	changes := call(t, r, "models.diff", `{"id":"lab","base":"sys-1","model":"m4"}`)["changes"].(map[string]any)
	if fmt.Sprint(changes["nodes"]) != "[map[change:added id:net]]" || len(changes["edges"].([]any)) != 1 {
		t.Fatalf("diff: %v", changes)
	}
	// The profile requires kinds, so lint reports every element.
	lint := call(t, r, "models.lint", `{"id":"lab","model":"m4"}`)
	if len(lint["findings"].([]any)) != 0 {
		t.Fatalf("model names no profile, so no profile findings: %v", lint)
	}
}

func TestReadFormatsQueryExport(t *testing.T) {
	r, _ := setup(t)
	if text := call(t, r, "models.read", `{"id":"lab","model":"sys-1","format":"outline"}`)["text"].(string); !strings.Contains(text, "- **UI** `ui`") {
		t.Fatalf("outline: %q", text)
	}
	q := call(t, r, "models.query", `{"id":"lab","model":"sys-1","fn":"search","filter":{"text":"ui"}}`)
	if fmt.Sprint(q["nodes"]) != "[ui]" {
		t.Fatalf("search: %v", q)
	}
	for _, f := range []string{"mermaid", "dot", "outline", "svg", "csv"} {
		if out := call(t, r, "models.export", `{"id":"lab","model":"sys-1","format":"`+f+`"}`); out["text"] == "" {
			t.Errorf("%s export is empty", f)
		}
	}
	list := call(t, r, "models.list", `{"id":"lab"}`)
	if len(list["models"].([]any)) != 1 {
		t.Fatalf("list: %v", list)
	}
}

func TestErrors(t *testing.T) {
	r, _ := setup(t)
	cases := []struct {
		name, in string
		code     registry.Code
	}{
		{"models.apply", `{"id":"lab","model":"sys-1","ops":[{"op":"node.add","node":{"id":"x","label":"X"}}]}`, registry.Denied},
		{"models.apply", `{"id":"lab","model":"nope","ops":[]}`, registry.NotFound},
		{"models.apply", `{"id":"lab","model":"sys-1","ops":[{"op":"node.remove","id":"app"}]}`, registry.Invalid},
		{"models.create", `{"id":"lab","import":{"format":"outline","source":"# T\n\n- a\n    - b\n"}}`, registry.Invalid},
		{"models.create", `{"id":"lab","document":{"format":"craggy.model","version":2,"title":"","subject":"S","nodes":[],"edges":[]}}`, registry.Invalid},
		{"models.read", `{"id":"lab","model":"sys-1","format":"png"}`, registry.Invalid},
		{"models.query", `{"id":"lab","model":"sys-1","fn":"impact","node":"zz"}`, registry.Invalid},
	}
	for _, c := range cases {
		_, err := r.Invoke(context.Background(), c.name, json.RawMessage(c.in))
		if registry.CodeOf(err) != c.code {
			t.Errorf("%s %s: got %v (%v), want %s", c.name, c.in, registry.CodeOf(err), err, c.code)
		}
	}
}

func TestCreateFromImportAndLintWithProfile(t *testing.T) {
	r, _ := setup(t)
	out := call(t, r, "models.create", `{"id":"lab","import":{"format":"mermaid","source":"flowchart LR\n  a[A] --> b[B]\n"}}`)
	doc := out["document"].(map[string]any)
	if len(doc["nodes"].([]any)) != 2 {
		t.Fatalf("import: %v", out)
	}
	set := call(t, r, "models.apply", `{"id":"lab","model":"`+out["model"].(string)+`","ops":[{"op":"model.set","fields":{"profile":"p@1"}}]}`)
	if len(set["lint"].([]any)) != 3 { // a, b and the edge have no kind
		t.Fatalf("lint with profile: %v", set["lint"])
	}
}
