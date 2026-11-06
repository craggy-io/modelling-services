// Package edit changes models through small, id-addressed operations. Apply
// runs a list of operations atomically, validates the result and returns
// the inverse operations, which undo the change exactly.
package edit

import (
	"encoding/json"
	"fmt"

	"github.com/craggy-io/modelling-services/model"
)

// Operation names.
const (
	NodeAdd        = "node.add"
	NodeRemove     = "node.remove"
	NodeMove       = "node.move"
	NodeSet        = "node.set"
	EdgeAdd        = "edge.add"
	EdgeRemove     = "edge.remove"
	EdgeSet        = "edge.set"
	PropSet        = "prop.set"
	PropUnset      = "prop.unset"
	EvidenceAdd    = "evidence.add"
	EvidenceRemove = "evidence.remove"
	ModelSet       = "model.set"
	ViewPut        = "view.put"
	ViewRemove     = "view.remove"
)

// Targets of prop.* and evidence.* operations.
const (
	TargetNode = "node"
	TargetEdge = "edge"
)

// Op is one operation. Which fields it uses depends on Op:
//
//	node.add        node, index?            index: position in nodes; absent appends
//	node.remove     id, cascade?            cascade removes descendants and touching edges
//	node.move       id, parent, index?      parent "" is top level; absent index keeps the position
//	node.set        id, fields              label, kind, notes, tags, link (null clears)
//	edge.add        edge, index?
//	edge.remove     id
//	edge.set        id, fields              label, from, to, kind, undirected, notes, tags
//	prop.set        target, id, key, value
//	prop.unset      target, id, key
//	evidence.add    target, id, evidence, index?   an already-cited ref is skipped
//	evidence.remove target, id, evidenceId
//	model.set       fields                  title, subject, notes, profile, tags
//	view.put        view, index?            replaces the view with the same id, else inserts
//	view.remove     id
type Op struct {
	Op         string                     `json:"op"`
	ID         string                     `json:"id,omitempty"`
	Target     string                     `json:"target,omitempty"`
	Node       *model.Node                `json:"node,omitempty"`
	Edge       *model.Edge                `json:"edge,omitempty"`
	View       *model.View                `json:"view,omitempty"`
	Evidence   *model.Evidence            `json:"evidence,omitempty"`
	EvidenceID string                     `json:"evidenceId,omitempty"`
	Parent     string                     `json:"parent,omitempty"`
	Index      *int                       `json:"index,omitempty"`
	Cascade    bool                       `json:"cascade,omitempty"`
	Key        string                     `json:"key,omitempty"`
	Value      any                        `json:"value,omitempty"`
	Fields     map[string]json.RawMessage `json:"fields,omitempty"`
}

// Set is a node.set, edge.set or model.set operation from Go values. A nil
// value clears the field.
func Set(op, id string, fields map[string]any) Op {
	raw := make(map[string]json.RawMessage, len(fields))
	for k, v := range fields {
		b, err := json.Marshal(v)
		if err != nil {
			panic(fmt.Sprintf("edit.Set: field %s: %v", k, err))
		}
		raw[k] = b
	}
	return Op{Op: op, ID: id, Fields: raw}
}

// At is a pointer to i, for Op.Index.
func At(i int) *int { return &i }

// Error is a refused Apply. Index is the failing operation, or -1 when the
// operations ran but the result is not a valid model (Issues says why).
type Error struct {
	Index   int           `json:"index"`
	Code    string        `json:"code"`
	Message string        `json:"message"`
	Issues  []model.Issue `json:"issues,omitempty"`
}

func (e *Error) Error() string {
	if e.Index < 0 {
		return "edit: result is not a valid model: " + e.Message
	}
	return fmt.Sprintf("edit: operation %d: %s", e.Index, e.Message)
}

// Is makes an Error match model.ErrInvalid.
func (e *Error) Is(target error) bool { return target == model.ErrInvalid }

func opErr(code, format string, args ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, args...)}
}
