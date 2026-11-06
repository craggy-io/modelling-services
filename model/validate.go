package model

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

// Limits bound one model. Hosts may tighten them; zero fields take the
// default.
type Limits struct {
	MaxBytes      int // encoded document size
	MaxNodes      int
	MaxEdges      int
	MaxRefs       int // distinct evidence refs
	MaxDepth      int // containment depth; top-level nodes are depth 1
	MaxProperties int // per element
	MaxValueBytes int // per string property value
	MaxViews      int
}

// DefaultLimits are the bounds craggy-labs has always applied to models.
var DefaultLimits = Limits{
	MaxBytes: 512 << 10, MaxNodes: 1000, MaxEdges: 2000, MaxRefs: 128,
	MaxDepth: 32, MaxProperties: 32, MaxValueBytes: 1024, MaxViews: 32,
}

func (l Limits) withDefaults() Limits {
	d := DefaultLimits
	pick := func(v, def int) int {
		if v > 0 {
			return v
		}
		return def
	}
	return Limits{
		MaxBytes: pick(l.MaxBytes, d.MaxBytes), MaxNodes: pick(l.MaxNodes, d.MaxNodes),
		MaxEdges: pick(l.MaxEdges, d.MaxEdges), MaxRefs: pick(l.MaxRefs, d.MaxRefs),
		MaxDepth: pick(l.MaxDepth, d.MaxDepth), MaxProperties: pick(l.MaxProperties, d.MaxProperties),
		MaxValueBytes: pick(l.MaxValueBytes, d.MaxValueBytes), MaxViews: pick(l.MaxViews, d.MaxViews),
	}
}

// Issue is one validation failure. Code is stable and shared with the Dart
// implementation; Element is the node, edge or view id concerned ("" for the
// model itself).
type Issue struct {
	Code    string `json:"code"`
	Element string `json:"element,omitempty"`
	Message string `json:"message"`
}

// ValidationError lists every issue found, in document order.
type ValidationError struct{ Issues []Issue }

func (e *ValidationError) Error() string {
	parts := make([]string, len(e.Issues))
	for i, is := range e.Issues {
		parts[i] = is.Message
	}
	return "invalid model: " + strings.Join(parts, "; ")
}

// Is makes a ValidationError match ErrInvalid.
func (e *ValidationError) Is(target error) bool { return target == ErrInvalid }

var (
	identifier  = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)
	propertyKey = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$`)
	scheme      = regexp.MustCompile(`^[a-z][a-z0-9+.-]{0,31}$`)
	renderer    = regexp.MustCompile(`^[a-z][a-z0-9-]{0,31}$`)
)

// ValidID reports whether s is a valid node, edge, evidence, view or kind id.
func ValidID(s string) bool { return identifier.MatchString(s) }

// Validate checks the whole document's structure and bounds, returning a
// *ValidationError listing every issue, or nil. It does not check profiles
// (query.Lint does) or that refs resolve (the host does).
func (m Model) Validate(l Limits) error {
	if issues := m.Issues(l); len(issues) > 0 {
		return &ValidationError{Issues: issues}
	}
	return nil
}

// Issues are the validation issues of m, in document order.
func (m Model) Issues(l Limits) []Issue {
	l = l.withDefaults()
	var out []Issue
	add := func(code, element, format string, args ...any) {
		out = append(out, Issue{Code: code, Element: element, Message: fmt.Sprintf(format, args...)})
	}
	if m.Format != Format {
		add("format", "", "format must be %q, got %q", Format, m.Format)
	}
	if m.Version != Version {
		add("version", "", "version must be %d, got %d", Version, m.Version)
	}
	if strings.TrimSpace(m.Title) == "" {
		add("title", "", "title is required")
	}
	if strings.TrimSpace(m.Subject) == "" {
		add("subject", "", "subject is required")
	}
	if raw, err := json.Marshal(m); err == nil && len(raw) > l.MaxBytes {
		add("size", "", "model is %d bytes (max %d)", len(raw), l.MaxBytes)
	}
	if len(m.Nodes) > l.MaxNodes {
		add("bounds.nodes", "", "%d nodes (max %d)", len(m.Nodes), l.MaxNodes)
	}
	if len(m.Edges) > l.MaxEdges {
		add("bounds.edges", "", "%d edges (max %d)", len(m.Edges), l.MaxEdges)
	}
	checkTags(m.Tags, "", add)

	nodes := map[string]bool{}
	for _, n := range m.Nodes {
		if !identifier.MatchString(n.ID) {
			add("id.invalid", n.ID, "node id %q is not a valid id", n.ID)
		} else if nodes[n.ID] {
			add("id.duplicate", n.ID, "node id %q is used twice", n.ID)
		}
		nodes[n.ID] = true
		if strings.TrimSpace(n.Label) == "" {
			add("label.empty", n.ID, "node %q has no label", n.ID)
		}
		checkElement(n.ID, n.Kind, n.Tags, n.Properties, n.Evidence, l, add)
		if n.Link != nil && strings.TrimSpace(n.Link.Model) == "" {
			add("link.model", n.ID, "node %q links to no model", n.ID)
		}
	}
	parents := map[string]string{}
	for _, n := range m.Nodes {
		switch {
		case n.Parent == "":
		case n.Parent == n.ID:
			add("parent.self", n.ID, "node %q contains itself", n.ID)
		case !nodes[n.Parent]:
			add("parent.missing", n.ID, "node %q's parent %q is not a node", n.ID, n.Parent)
		default:
			parents[n.ID] = n.Parent
		}
	}
	for _, n := range m.Nodes {
		depth, cyclic, loops := 1, false, false
		seen := map[string]bool{n.ID: true}
		for p := parents[n.ID]; p != ""; p = parents[p] {
			if seen[p] {
				cyclic, loops = p == n.ID, true
				break
			}
			seen[p] = true
			depth++
		}
		if loops && !cyclic {
			continue // an ancestor's cycle, reported on its members
		}
		if cyclic {
			add("parent.cycle", n.ID, "node %q is inside its own containment cycle", n.ID)
		} else if depth > l.MaxDepth {
			add("bounds.depth", n.ID, "node %q is nested %d deep (max %d)", n.ID, depth, l.MaxDepth)
		}
	}

	edges := map[string]bool{}
	for _, e := range m.Edges {
		if !identifier.MatchString(e.ID) {
			add("id.invalid", e.ID, "edge id %q is not a valid id", e.ID)
		} else if edges[e.ID] {
			add("id.duplicate", e.ID, "edge id %q is used twice", e.ID)
		}
		edges[e.ID] = true
		if !nodes[e.From] || !nodes[e.To] {
			add("edge.endpoint", e.ID, "edge %q must join two nodes (from %q, to %q)", e.ID, e.From, e.To)
		}
		if strings.TrimSpace(e.Label) == "" {
			add("label.empty", e.ID, "edge %q has no label", e.ID)
		}
		checkElement(e.ID, e.Kind, e.Tags, e.Properties, e.Evidence, l, add)
	}
	if refs := len(m.Refs()); refs > l.MaxRefs {
		add("bounds.refs", "", "%d distinct evidence refs (max %d)", refs, l.MaxRefs)
	}

	if len(m.Views) > l.MaxViews {
		add("bounds.views", "", "%d views (max %d)", len(m.Views), l.MaxViews)
	}
	views := map[string]bool{}
	for _, v := range m.Views {
		if !identifier.MatchString(v.ID) || views[v.ID] {
			add("view.id", v.ID, "view id %q is invalid or used twice", v.ID)
		}
		views[v.ID] = true
		if !renderer.MatchString(v.Renderer) {
			add("view.renderer", v.ID, "view %q has an invalid renderer %q", v.ID, v.Renderer)
		}
		for _, id := range SortedKeys(v.Sizes) {
			if sz := v.Sizes[id]; !identifier.MatchString(id) || !SizeInBounds(sz) {
				add("view.size", v.ID, "view %q has an invalid size for %q (w %d of 1–%d, h %d of 1–%d)", v.ID, id, sz.W, MaxSizeW, sz.H, MaxSizeH)
			}
		}
		checkProperties(v.ID, v.Options, l, add)
	}
	return out
}

// MaxSizeW and MaxSizeH bound a view Size: tenths of the parent's width and
// row units.
const (
	MaxSizeW = 10
	MaxSizeH = 20
)

// SizeInBounds reports whether s sets a width or height and each set value
// is in range (0 is auto).
func SizeInBounds(s Size) bool {
	return (s.W != 0 || s.H != 0) && s.W >= 0 && s.W <= MaxSizeW && s.H >= 0 && s.H <= MaxSizeH
}

type addFunc func(code, element, format string, args ...any)

func checkElement(id, kind string, tags []string, props Properties, evidence []Evidence, l Limits, add addFunc) {
	if kind != "" && !identifier.MatchString(kind) {
		add("kind.invalid", id, "%q has an invalid kind %q", id, kind)
	}
	checkTags(tags, id, add)
	checkProperties(id, props, l, add)
	seen := map[string]bool{}
	for _, e := range evidence {
		if !identifier.MatchString(e.ID) || seen[e.ID] {
			add("evidence.id", id, "%q has evidence with an invalid or repeated id %q", id, e.ID)
		}
		seen[e.ID] = true
		if strings.TrimSpace(e.Caption) == "" {
			add("evidence.caption", id, "%q has evidence %q with no caption", id, e.ID)
		}
		if !scheme.MatchString(e.Ref.Scheme) || strings.TrimSpace(e.Ref.ID) == "" {
			add("evidence.ref", id, "%q has evidence %q without a valid ref (scheme %q, id %q)", id, e.ID, e.Ref.Scheme, e.Ref.ID)
		}
	}
}

func checkTags(tags []string, id string, add addFunc) {
	seen := map[string]bool{}
	for _, t := range tags {
		if strings.TrimSpace(t) == "" || seen[t] {
			add("tag.invalid", id, "%q has an empty or repeated tag %q", id, t)
		}
		seen[t] = true
	}
}

func checkProperties(id string, props Properties, l Limits, add addFunc) {
	if len(props) > l.MaxProperties {
		add("bounds.properties", id, "%q has %d properties (max %d)", id, len(props), l.MaxProperties)
	}
	for _, k := range SortedKeys(props) {
		if !propertyKey.MatchString(k) {
			add("property.key", id, "%q has an invalid property key %q", id, k)
		}
		if !ScalarValue(props[k]) {
			add("property.value", id, "%q property %q must be a string, number or bool", id, k)
		} else if s, ok := props[k].(string); ok && len(s) > l.MaxValueBytes {
			add("property.value", id, "%q property %q is %d bytes (max %d)", id, k, len(s), l.MaxValueBytes)
		}
	}
}

// ScalarValue reports whether v may be a property value.
func ScalarValue(v any) bool {
	switch v.(type) {
	case string, bool, float64, float32, int, int32, int64, json.Number:
		return true
	}
	return false
}
