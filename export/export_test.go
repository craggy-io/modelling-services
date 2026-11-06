package export_test

import (
	"encoding/xml"
	"os"
	"strings"
	"testing"

	"github.com/craggy-io/modelling-services/export"
	"github.com/craggy-io/modelling-services/model"
)

func fixture(t *testing.T) model.Model {
	t.Helper()
	raw, err := os.ReadFile("../conformance/fixtures/app.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := model.Decode(raw)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestCSVRoundTrip(t *testing.T) {
	m := fixture(t)
	nodes, edges, err := export.CSV(m)
	if err != nil {
		t.Fatal(err)
	}
	back, err := export.ParseCSV(m.Title, nodes, edges)
	if err != nil {
		t.Fatal(err)
	}
	if err := back.Validate(model.Limits{}); err != nil {
		t.Fatal(err)
	}
	// CSV drops evidence, links and views; everything else survives.
	want := m.Clone()
	want.Subject, want.Profile, want.Views = back.Subject, "", nil
	for i := range want.Nodes {
		want.Nodes[i].Evidence, want.Nodes[i].Link = nil, nil
	}
	for i := range want.Edges {
		want.Edges[i].Evidence = nil
	}
	if !model.Equal(back, want) {
		a, _ := model.Encode(back)
		t.Fatalf("round trip:\n%s", a)
	}
}

func TestDOT(t *testing.T) {
	dot := export.DOT(fixture(t))
	for _, want := range []string{`subgraph "cluster_app" {`, `"pinner" [label="Certificate pinner"];`, `"ui" -> "native" [label="shares data with", dir=none];`} {
		if !strings.Contains(dot, want) {
			t.Errorf("DOT lacks %s:\n%s", want, dot)
		}
	}
}

func TestSVGIsWellFormed(t *testing.T) {
	svg := export.SVG(fixture(t), export.SVGOptions{Width: 600})
	dec := xml.NewDecoder(strings.NewReader(svg))
	rects := 0
	for {
		tok, err := dec.Token()
		if err != nil {
			break
		}
		if s, ok := tok.(xml.StartElement); ok && s.Name.Local == "rect" {
			rects++
		}
	}
	if rects != 7 { // the root and six areas
		t.Fatalf("%d rects in\n%s", rects, svg)
	}
}
