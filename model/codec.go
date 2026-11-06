package model

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/craggy-io/foundation-kit/canonjson"
)

// ErrInvalid marks every decode and validation failure.
var ErrInvalid = errors.New("invalid model")

// Decode strictly decodes one document: unknown fields, trailing content and
// unsupported versions are refused. A version 1 document (the craggy-labs
// intel graph) is upgraded to the current version. Evidence without an id is
// given one ("ev1", "ev2", … skipping ids the element already uses). Decode
// does not validate; call Validate.
func Decode(raw []byte) (Model, error) {
	var head struct {
		Version int `json:"version"`
	}
	if err := json.Unmarshal(raw, &head); err != nil {
		return Model{}, fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	var m Model
	switch head.Version {
	case 1:
		var g v1Graph
		if err := strict(raw, &g); err != nil {
			return Model{}, err
		}
		m = g.upgrade()
	case Version:
		if err := strict(raw, &m); err != nil {
			return Model{}, err
		}
	default:
		return Model{}, fmt.Errorf("%w: unsupported model version %d (want 1 or %d)", ErrInvalid, head.Version, Version)
	}
	m.normalize()
	return m, nil
}

// Encode writes m as canonical JSON at the current format and version, so
// equal models encode to equal bytes.
func Encode(m Model) ([]byte, error) {
	m.Format, m.Version = Format, Version
	if m.Nodes == nil {
		m.Nodes = []Node{}
	}
	if m.Edges == nil {
		m.Edges = []Edge{}
	}
	return canonjson.Marshal(m)
}

// Equal reports whether a and b encode to the same canonical bytes.
func Equal(a, b Model) bool {
	x, err1 := Encode(a)
	y, err2 := Encode(b)
	return err1 == nil && err2 == nil && bytes.Equal(x, y)
}

func strict(raw []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		return fmt.Errorf("%w: a model must be exactly one JSON document", ErrInvalid)
	}
	var doc any
	_ = json.Unmarshal(raw, &doc)
	return exactNames(doc, "")
}

// fieldNames are every field name the format uses. encoding/json matches
// names case-insensitively; the format does not, so "TITLE" is refused.
var fieldNames = map[string]bool{}

func init() {
	for _, n := range strings.Fields(`format version title subject notes profile tags nodes edges views
		id label parent kind properties evidence link from to undirected caption ref scheme selector model node
		renderer root collapsed filter positions sizes w h options kinds text changedOnly citation artifactId`) {
		fieldNames[n] = true
	}
}

// exactNames refuses an object key that is not spelled exactly as a field,
// outside free-form maps (properties, options, positions). Sizes is keyed
// by node id, but each size's own names are exact.
func exactNames(v any, parent string) error {
	switch x := v.(type) {
	case map[string]any:
		if parent == "properties" || parent == "options" || parent == "positions" {
			return nil // free-form: values are checked by Validate
		}
		if parent == "sizes" {
			for _, size := range x {
				if err := exactNames(size, "size"); err != nil {
					return err
				}
			}
			return nil
		}
		for k, child := range x {
			if !fieldNames[k] {
				return fmt.Errorf("%w: unknown field %q", ErrInvalid, k)
			}
			if err := exactNames(child, k); err != nil {
				return err
			}
		}
	case []any:
		for _, child := range x {
			if err := exactNames(child, parent); err != nil {
				return err
			}
		}
	}
	return nil
}

// normalize fills defaults that make a decoded document complete: empty
// node and edge lists, and missing evidence ids.
func (m *Model) normalize() {
	if m.Nodes == nil {
		m.Nodes = []Node{}
	}
	if m.Edges == nil {
		m.Edges = []Edge{}
	}
	for i := range m.Nodes {
		FillEvidenceIDs(m.Nodes[i].Evidence)
	}
	for i := range m.Edges {
		FillEvidenceIDs(m.Edges[i].Evidence)
	}
}

// FillEvidenceIDs gives evidence without an id the first free "evN"
// ("ev1", "ev2", …) among the ids already in the list.
func FillEvidenceIDs(evidence []Evidence) {
	used := map[string]bool{}
	for _, e := range evidence {
		used[e.ID] = true
	}
	next := 1
	for i := range evidence {
		if evidence[i].ID != "" {
			continue
		}
		for used["ev"+strconv.Itoa(next)] {
			next++
		}
		evidence[i].ID = "ev" + strconv.Itoa(next)
		used[evidence[i].ID] = true
	}
}

// v1Graph is the craggy-labs intel graph (version 1), read only to upgrade.
type v1Graph struct {
	Version int      `json:"version"`
	Title   string   `json:"title"`
	Subject string   `json:"subject"`
	Notes   string   `json:"notes,omitempty"`
	Nodes   []v1Node `json:"nodes"`
	Edges   []v1Edge `json:"edges"`
}

type v1Node struct {
	ID       string       `json:"id"`
	Label    string       `json:"label"`
	Parent   string       `json:"parent,omitempty"`
	Notes    string       `json:"notes,omitempty"`
	Evidence []v1Evidence `json:"evidence,omitempty"`
}

type v1Edge struct {
	ID       string       `json:"id"`
	From     string       `json:"from"`
	To       string       `json:"to"`
	Label    string       `json:"label"`
	Notes    string       `json:"notes,omitempty"`
	Evidence []v1Evidence `json:"evidence,omitempty"`
}

type v1Evidence struct {
	Citation struct {
		ArtifactID string `json:"artifactId"`
		Selector   string `json:"selector,omitempty"`
	} `json:"citation"`
	Caption string `json:"caption"`
}

func (g v1Graph) upgrade() Model {
	m := New(g.Title, g.Subject)
	m.Notes = g.Notes
	evidence := func(in []v1Evidence) []Evidence {
		var out []Evidence
		for _, e := range in {
			out = append(out, Evidence{Caption: e.Caption, Ref: Ref{Scheme: "artifact", ID: e.Citation.ArtifactID, Selector: e.Citation.Selector}})
		}
		return out
	}
	for _, n := range g.Nodes {
		m.Nodes = append(m.Nodes, Node{ID: n.ID, Label: n.Label, Parent: n.Parent, Notes: n.Notes, Evidence: evidence(n.Evidence)})
	}
	for _, e := range g.Edges {
		m.Edges = append(m.Edges, Edge{ID: e.ID, From: e.From, To: e.To, Label: e.Label, Notes: e.Notes, Evidence: evidence(e.Evidence)})
	}
	return m
}
