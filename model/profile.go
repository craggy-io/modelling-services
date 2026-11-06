package model

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// Profile is an optional metamodel: the node and edge kinds a model may use,
// which kinds may nest in which, where edges may run, and typed properties.
// A model names its profile in Model.Profile; the host resolves the name and
// query.Lint checks the model against it.
type Profile struct {
	ID           string              `json:"id"`
	Version      int                 `json:"version"`
	Title        string              `json:"title,omitempty"`
	RequireKinds bool                `json:"requireKinds,omitempty"`
	NodeKinds    map[string]NodeKind `json:"nodeKinds,omitempty"`
	EdgeKinds    map[string]EdgeKind `json:"edgeKinds,omitempty"`
}

// NodeKind is one kind of area. Children lists the kinds that may nest
// directly inside it; empty allows any.
type NodeKind struct {
	Label      string                  `json:"label"`
	Children   []string                `json:"children,omitempty"`
	Properties map[string]PropertySpec `json:"properties,omitempty"`
}

// EdgeKind is one kind of relationship. From and To list the node kinds it
// may join; empty allows any.
type EdgeKind struct {
	Label      string                  `json:"label"`
	From       []string                `json:"from,omitempty"`
	To         []string                `json:"to,omitempty"`
	Undirected bool                    `json:"undirected,omitempty"`
	Properties map[string]PropertySpec `json:"properties,omitempty"`
}

// PropertySpec types one property. Type is "string", "number" or "bool".
type PropertySpec struct {
	Type     string `json:"type"`
	Label    string `json:"label,omitempty"`
	Enum     []any  `json:"enum,omitempty"`
	Required bool   `json:"required,omitempty"`
}

// Ref is the name a model uses for this profile: "<id>@<version>".
func (p Profile) Ref() string { return fmt.Sprintf("%s@%d", p.ID, p.Version) }

// DecodeProfile strictly decodes and checks one profile.
func DecodeProfile(raw []byte) (Profile, error) {
	var p Profile
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&p); err != nil {
		return p, fmt.Errorf("%w: profile: %v", ErrInvalid, err)
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		return p, fmt.Errorf("%w: a profile must be exactly one JSON document", ErrInvalid)
	}
	return p, p.Check()
}

// Check refuses a profile that names unknown kinds or property types.
func (p Profile) Check() error {
	if p.ID == "" || p.Version < 1 {
		return fmt.Errorf("%w: profile needs an id and a version >= 1", ErrInvalid)
	}
	known := func(kinds []string, where string) error {
		for _, k := range kinds {
			if _, ok := p.NodeKinds[k]; !ok {
				return fmt.Errorf("%w: profile %s: %s names unknown node kind %q", ErrInvalid, p.ID, where, k)
			}
		}
		return nil
	}
	props := func(specs map[string]PropertySpec, where string) error {
		for _, k := range SortedKeys(specs) {
			switch specs[k].Type {
			case "string", "number", "bool":
			default:
				return fmt.Errorf("%w: profile %s: %s property %q has type %q (want string, number or bool)", ErrInvalid, p.ID, where, k, specs[k].Type)
			}
		}
		return nil
	}
	for _, name := range SortedKeys(p.NodeKinds) {
		if !ValidID(name) {
			return fmt.Errorf("%w: profile %s: invalid node kind %q", ErrInvalid, p.ID, name)
		}
		k := p.NodeKinds[name]
		if err := known(k.Children, "node kind "+name+" children"); err != nil {
			return err
		}
		if err := props(k.Properties, "node kind "+name); err != nil {
			return err
		}
	}
	for _, name := range SortedKeys(p.EdgeKinds) {
		if !ValidID(name) {
			return fmt.Errorf("%w: profile %s: invalid edge kind %q", ErrInvalid, p.ID, name)
		}
		k := p.EdgeKinds[name]
		if err := known(k.From, "edge kind "+name+" from"); err != nil {
			return err
		}
		if err := known(k.To, "edge kind "+name+" to"); err != nil {
			return err
		}
		if err := props(k.Properties, "edge kind "+name); err != nil {
			return err
		}
	}
	return nil
}
