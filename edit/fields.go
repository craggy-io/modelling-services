package edit

import (
	"encoding/json"
	"fmt"

	"github.com/craggy-io/modelling-services/model"
)

// field reads and writes one settable field. JSON null clears it.
type field struct {
	get func() any
	set func(json.RawMessage) error
}

// setFields applies op.Fields through fields and returns the inverse
// operation, which sets every touched field back to its old value.
func setFields(op Op, fields map[string]field) (Op, *Error) {
	if len(op.Fields) == 0 {
		return Op{}, opErr("op.field", "%s needs fields", op.Op)
	}
	for _, name := range model.SortedKeys(op.Fields) {
		if _, ok := fields[name]; !ok {
			return Op{}, opErr("op.field", "%s cannot set %q", op.Op, name)
		}
	}
	old := map[string]json.RawMessage{}
	for _, name := range model.SortedKeys(op.Fields) {
		f := fields[name]
		prev, err := json.Marshal(f.get())
		if err != nil {
			return Op{}, opErr("op.field", "%s: %v", name, err)
		}
		if err := f.set(op.Fields[name]); err != nil {
			return Op{}, opErr("op.field", "%s %s: %v", op.Op, name, err)
		}
		old[name] = prev
	}
	return Op{Op: op.Op, ID: op.ID, Fields: old}, nil
}

func text(p *string) field {
	return field{
		get: func() any { return *p },
		set: func(raw json.RawMessage) error { *p = ""; return decodeOrNull(raw, p) },
	}
}

func tags(p *[]string) field {
	return field{
		get: func() any { return *p },
		set: func(raw json.RawMessage) error {
			var v []string
			if err := decodeOrNull(raw, &v); err != nil {
				return err
			}
			if len(v) == 0 {
				v = nil
			}
			*p = v
			return nil
		},
	}
}

func flag(p *bool) field {
	return field{
		get: func() any { return *p },
		set: func(raw json.RawMessage) error { *p = false; return decodeOrNull(raw, p) },
	}
}

func link(p **model.Link) field {
	return field{
		get: func() any { return *p },
		set: func(raw json.RawMessage) error {
			var l *model.Link
			if err := decodeOrNull(raw, &l); err != nil {
				return err
			}
			*p = l
			return nil
		},
	}
}

func decodeOrNull(raw json.RawMessage, v any) error {
	if string(raw) == "null" {
		return nil
	}
	if err := json.Unmarshal(raw, v); err != nil {
		return fmt.Errorf("bad value %s", raw)
	}
	return nil
}

func nodeFields(n *model.Node) map[string]field {
	return map[string]field{
		"label": text(&n.Label), "kind": text(&n.Kind), "notes": text(&n.Notes),
		"tags": tags(&n.Tags), "link": link(&n.Link),
	}
}

func edgeFields(e *model.Edge) map[string]field {
	return map[string]field{
		"label": text(&e.Label), "from": text(&e.From), "to": text(&e.To), "kind": text(&e.Kind),
		"undirected": flag(&e.Undirected), "notes": text(&e.Notes), "tags": tags(&e.Tags),
	}
}

func modelFields(m *model.Model) map[string]field {
	return map[string]field{
		"title": text(&m.Title), "subject": text(&m.Subject), "notes": text(&m.Notes),
		"profile": text(&m.Profile), "tags": tags(&m.Tags),
	}
}
