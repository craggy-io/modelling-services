package kinds_test

import (
	"testing"
	"testing/fstest"

	"github.com/craggy-io/foundation-kit/bundle"
	"github.com/craggy-io/foundation-kit/bundle/bundletest"

	"github.com/craggy-io/modelling-services/kinds"
)

func TestBundleContent(t *testing.T) {
	fsys := fstest.MapFS{
		"bundle.yaml": {Data: []byte(`apiVersion: craggy.io/bundle/v1
metadata:
  id: shapes
  version: 1.0.0
contributions:
  - id: android-app
    kind: craggy.model-profile@1
    path: android.yaml
  - id: starter
    kind: craggy.model@1
    path: starter.json
`)},
		"android.yaml": {Data: []byte("id: android-app\nversion: 1\nnodeKinds:\n  app: {label: Application}\n")},
		"starter.json": {Data: []byte(`{"version":1,"title":"Starter","subject":"any app","nodes":[{"id":"app","label":"App"}],"edges":[]}`)},
	}
	cat := bundletest.Load(t, fsys, kinds.Compilers()...)
	p, ok := bundle.Lookup(cat, kinds.ProfileKind, "android-app")
	if !ok || p.Value.NodeKinds["app"].Label != "Application" {
		t.Fatalf("profile: %+v %v", p, ok)
	}
	m, ok := bundle.Lookup(cat, kinds.ModelKind, "starter")
	if !ok || m.Value.Version != 2 || len(m.Value.Nodes) != 1 {
		t.Fatalf("template: %+v %v", m, ok)
	}
}
