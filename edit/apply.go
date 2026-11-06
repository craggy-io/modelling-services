package edit

import (
	"slices"

	"github.com/craggy-io/modelling-services/model"
)

// Apply runs ops against a copy of m, in order, and validates the result
// with l. It is all or nothing: on error m is unchanged and no result is
// returned. The returned inverse operations, applied to the result, give
// back m exactly.
func Apply(m model.Model, ops []Op, l model.Limits) (model.Model, []Op, error) {
	s := &state{m: m.Clone()}
	var inverse []Op
	for i, op := range ops {
		inv, err := s.apply(op)
		if err != nil {
			err.Index = i
			return m, nil, err
		}
		inverse = append(inv, inverse...)
	}
	if issues := s.m.Issues(l); len(issues) > 0 {
		return m, nil, &Error{Index: -1, Code: issues[0].Code, Message: (&model.ValidationError{Issues: issues}).Error(), Issues: issues}
	}
	if inverse == nil {
		inverse = []Op{}
	}
	return s.m, inverse, nil
}

type state struct{ m model.Model }

func (s *state) node(id string) int {
	return slices.IndexFunc(s.m.Nodes, func(n model.Node) bool { return n.ID == id })
}

func (s *state) edge(id string) int {
	return slices.IndexFunc(s.m.Edges, func(e model.Edge) bool { return e.ID == id })
}

func (s *state) apply(op Op) ([]Op, *Error) {
	switch op.Op {
	case NodeAdd:
		if op.Node == nil {
			return nil, opErr("op.field", "node.add needs a node")
		}
		if s.node(op.Node.ID) >= 0 {
			return nil, opErr("op.exists", "node %q already exists", op.Node.ID)
		}
		n := op.Node.Clone()
		model.FillEvidenceIDs(n.Evidence)
		var err *Error
		if s.m.Nodes, err = insert(s.m.Nodes, n, op.Index); err != nil {
			return nil, err
		}
		return []Op{{Op: NodeRemove, ID: n.ID}}, nil
	case NodeRemove:
		return s.removeNode(op)
	case NodeMove:
		i := s.node(op.ID)
		if i < 0 {
			return nil, opErr("op.missing", "no node %q", op.ID)
		}
		n := s.m.Nodes[i]
		inv := Op{Op: NodeMove, ID: n.ID, Parent: n.Parent, Index: At(i)}
		n.Parent = op.Parent
		if op.Index == nil {
			s.m.Nodes[i] = n
			return []Op{inv}, nil
		}
		rest := slices.Delete(slices.Clone(s.m.Nodes), i, i+1)
		var err *Error
		if s.m.Nodes, err = insert(rest, n, op.Index); err != nil {
			return nil, err
		}
		return []Op{inv}, nil
	case NodeSet:
		i := s.node(op.ID)
		if i < 0 {
			return nil, opErr("op.missing", "no node %q", op.ID)
		}
		inv, err := setFields(op, nodeFields(&s.m.Nodes[i]))
		return wrap(inv, err)
	case EdgeAdd:
		if op.Edge == nil {
			return nil, opErr("op.field", "edge.add needs an edge")
		}
		if s.edge(op.Edge.ID) >= 0 {
			return nil, opErr("op.exists", "edge %q already exists", op.Edge.ID)
		}
		e := op.Edge.Clone()
		model.FillEvidenceIDs(e.Evidence)
		var err *Error
		if s.m.Edges, err = insert(s.m.Edges, e, op.Index); err != nil {
			return nil, err
		}
		return []Op{{Op: EdgeRemove, ID: e.ID}}, nil
	case EdgeRemove:
		i := s.edge(op.ID)
		if i < 0 {
			return nil, opErr("op.missing", "no edge %q", op.ID)
		}
		e := s.m.Edges[i]
		s.m.Edges = slices.Delete(s.m.Edges, i, i+1)
		return []Op{{Op: EdgeAdd, Edge: &e, Index: At(i)}}, nil
	case EdgeSet:
		i := s.edge(op.ID)
		if i < 0 {
			return nil, opErr("op.missing", "no edge %q", op.ID)
		}
		inv, err := setFields(op, edgeFields(&s.m.Edges[i]))
		return wrap(inv, err)
	case PropSet, PropUnset:
		return s.prop(op)
	case EvidenceAdd, EvidenceRemove:
		return s.evidence(op)
	case ModelSet:
		inv, err := setFields(op, modelFields(&s.m))
		return wrap(inv, err)
	case ViewPut:
		return s.putView(op)
	case ViewRemove:
		i := slices.IndexFunc(s.m.Views, func(v model.View) bool { return v.ID == op.ID })
		if i < 0 {
			return nil, opErr("op.missing", "no view %q", op.ID)
		}
		v := s.m.Views[i]
		s.m.Views = slices.Delete(s.m.Views, i, i+1)
		if len(s.m.Views) == 0 {
			s.m.Views = nil
		}
		return []Op{{Op: ViewPut, View: &v, Index: At(i)}}, nil
	}
	return nil, opErr("op.unknown", "unknown operation %q", op.Op)
}

func wrap(inv Op, err *Error) ([]Op, *Error) {
	if err != nil {
		return nil, err
	}
	return []Op{inv}, nil
}

// removeNode removes a node, refusing one with children or edges unless
// cascade is set. The inverse re-adds every removed node and edge at its
// old position, in ascending position order.
func (s *state) removeNode(op Op) ([]Op, *Error) {
	if s.node(op.ID) < 0 {
		return nil, opErr("op.missing", "no node %q", op.ID)
	}
	ix := model.NewIndex(s.m)
	gone := map[string]bool{op.ID: true}
	for _, d := range ix.Descendants(op.ID) {
		gone[d] = true
	}
	var touching int
	for _, e := range s.m.Edges {
		if gone[e.From] || gone[e.To] {
			touching++
		}
	}
	if !op.Cascade && (len(gone) > 1 || touching > 0) {
		return nil, opErr("op.not-empty", "node %q has %d nested nodes and %d edges; remove them first or set cascade", op.ID, len(gone)-1, touching)
	}
	var inverse []Op
	var nodes []model.Node
	for i, n := range s.m.Nodes {
		if gone[n.ID] {
			inverse = append(inverse, Op{Op: NodeAdd, Node: &n, Index: At(i)})
		} else {
			nodes = append(nodes, n)
		}
	}
	var edges []model.Edge
	for i, e := range s.m.Edges {
		if gone[e.From] || gone[e.To] {
			inverse = append(inverse, Op{Op: EdgeAdd, Edge: &e, Index: At(i)})
		} else {
			edges = append(edges, e)
		}
	}
	s.m.Nodes, s.m.Edges = orEmpty(nodes), orEmpty(edges)
	return inverse, nil
}

// element is the properties and evidence of a node or edge.
type element struct {
	props    *model.Properties
	evidence *[]model.Evidence
}

func (s *state) element(op Op) (element, *Error) {
	switch op.Target {
	case TargetNode:
		if i := s.node(op.ID); i >= 0 {
			return element{&s.m.Nodes[i].Properties, &s.m.Nodes[i].Evidence}, nil
		}
		return element{}, opErr("op.missing", "no node %q", op.ID)
	case TargetEdge:
		if i := s.edge(op.ID); i >= 0 {
			return element{&s.m.Edges[i].Properties, &s.m.Edges[i].Evidence}, nil
		}
		return element{}, opErr("op.missing", "no edge %q", op.ID)
	}
	return element{}, opErr("op.field", "%s target must be node or edge, got %q", op.Op, op.Target)
}

func (s *state) prop(op Op) ([]Op, *Error) {
	el, err := s.element(op)
	if err != nil {
		return nil, err
	}
	if op.Key == "" {
		return nil, opErr("op.field", "%s needs a key", op.Op)
	}
	old, had := (*el.props)[op.Key]
	inv := Op{Op: PropUnset, Target: op.Target, ID: op.ID, Key: op.Key}
	if had {
		inv = Op{Op: PropSet, Target: op.Target, ID: op.ID, Key: op.Key, Value: old}
	}
	if op.Op == PropUnset {
		if !had {
			return []Op{}, nil
		}
		delete(*el.props, op.Key)
		if len(*el.props) == 0 {
			*el.props = nil
		}
		return []Op{inv}, nil
	}
	if !model.ScalarValue(op.Value) {
		return nil, opErr("op.field", "prop.set value must be a string, number or bool")
	}
	if *el.props == nil {
		*el.props = model.Properties{}
	}
	(*el.props)[op.Key] = op.Value
	return []Op{inv}, nil
}

func (s *state) evidence(op Op) ([]Op, *Error) {
	el, err := s.element(op)
	if err != nil {
		return nil, err
	}
	list := *el.evidence
	if op.Op == EvidenceRemove {
		i := slices.IndexFunc(list, func(e model.Evidence) bool { return e.ID == op.EvidenceID })
		if i < 0 {
			return nil, opErr("op.missing", "%s %q has no evidence %q", op.Target, op.ID, op.EvidenceID)
		}
		e := list[i]
		*el.evidence = orNil(slices.Delete(slices.Clone(list), i, i+1))
		return []Op{{Op: EvidenceAdd, Target: op.Target, ID: op.ID, Evidence: &e, Index: At(i)}}, nil
	}
	if op.Evidence == nil {
		return nil, opErr("op.field", "evidence.add needs evidence")
	}
	e := *op.Evidence
	for _, have := range list {
		if have.Ref == e.Ref {
			return []Op{}, nil // already cited
		}
		if e.ID != "" && have.ID == e.ID {
			return nil, opErr("op.exists", "%s %q already has evidence %q", op.Target, op.ID, e.ID)
		}
	}
	next, ierr := insert(slices.Clone(list), e, op.Index)
	if ierr != nil {
		return nil, ierr
	}
	model.FillEvidenceIDs(next)
	*el.evidence = next
	id := next[slices.IndexFunc(next, func(x model.Evidence) bool { return x.Ref == e.Ref })].ID
	return []Op{{Op: EvidenceRemove, Target: op.Target, ID: op.ID, EvidenceID: id}}, nil
}

func (s *state) putView(op Op) ([]Op, *Error) {
	if op.View == nil {
		return nil, opErr("op.field", "view.put needs a view")
	}
	v := op.View.Clone()
	if i := slices.IndexFunc(s.m.Views, func(x model.View) bool { return x.ID == v.ID }); i >= 0 {
		old := s.m.Views[i]
		s.m.Views[i] = v
		return []Op{{Op: ViewPut, View: &old}}, nil
	}
	var err *Error
	if s.m.Views, err = insert(s.m.Views, v, op.Index); err != nil {
		return nil, err
	}
	return []Op{{Op: ViewRemove, ID: v.ID}}, nil
}

// insert puts v at index (nil appends), refusing an index out of range.
func insert[T any](s []T, v T, index *int) ([]T, *Error) {
	if index == nil {
		return append(s, v), nil
	}
	if *index < 0 || *index > len(s) {
		return nil, opErr("op.index", "index %d is outside 0..%d", *index, len(s))
	}
	return slices.Insert(s, *index, v), nil
}

func orEmpty[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

func orNil[T any](s []T) []T {
	if len(s) == 0 {
		return nil
	}
	return s
}
