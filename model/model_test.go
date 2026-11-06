package model_test

import (
	"errors"
	"testing"

	"github.com/craggy-io/modelling-services/model"
)

func TestCloneIsDeep(t *testing.T) {
	m := model.New("T", "S")
	m.Nodes = []model.Node{{ID: "a", Label: "A", Tags: []string{"x"}, Properties: model.Properties{"k": "v"},
		Evidence: []model.Evidence{{ID: "ev1", Caption: "c", Ref: model.Ref{Scheme: "url", ID: "u"}}}, Link: &model.Link{Model: "m"}}}
	m.Views = []model.View{{ID: "v", Renderer: "blocks", Positions: map[string][2]float64{"a": {1, 2}}}}
	c := m.Clone()
	c.Nodes[0].Tags[0], c.Nodes[0].Properties["k"], c.Nodes[0].Evidence[0].Caption, c.Nodes[0].Link.Model = "y", "w", "d", "n"
	c.Views[0].Positions["a"] = [2]float64{9, 9}
	if !model.Equal(m, func() model.Model { x := m; return x }()) || m.Nodes[0].Tags[0] != "x" || m.Nodes[0].Properties["k"] != "v" ||
		m.Nodes[0].Evidence[0].Caption != "c" || m.Nodes[0].Link.Model != "m" || m.Views[0].Positions["a"][0] != 1 {
		t.Fatal("clone shares state with the original")
	}
}

func TestValidationErrorIsInvalid(t *testing.T) {
	err := model.New("", "S").Validate(model.Limits{})
	var v *model.ValidationError
	if !errors.Is(err, model.ErrInvalid) || !errors.As(err, &v) || v.Issues[0].Code != "title" {
		t.Fatalf("got %v", err)
	}
}

func TestProfileCheck(t *testing.T) {
	_, err := model.DecodeProfile([]byte(`{"id":"p","version":1,"nodeKinds":{"a":{"label":"A","children":["b"]}}}`))
	if !errors.Is(err, model.ErrInvalid) {
		t.Fatalf("unknown child kind accepted: %v", err)
	}
	_, err = model.DecodeProfile([]byte(`{"id":"p","version":1,"nodeKinds":{"a":{"label":"A","properties":{"x":{"type":"date"}}}}}`))
	if !errors.Is(err, model.ErrInvalid) {
		t.Fatalf("unknown property type accepted: %v", err)
	}
}
