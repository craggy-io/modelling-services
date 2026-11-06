package query

import (
	"fmt"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// Severity ranks a lint finding.
type Severity string

const (
	Error   Severity = "error"
	Warning Severity = "warning"
	Info    Severity = "info"
)

// Finding is one lint result. Rule is stable and shared with Dart.
type Finding struct {
	Rule     string   `json:"rule"`
	Element  string   `json:"element"`
	Severity Severity `json:"severity"`
	Message  string   `json:"message"`
}

// Lint checks a valid model for likely mistakes, and against profile when it
// is not nil. Findings come in document order: nodes, then edges, then views,
// and per element in a fixed rule order. Lint never fails; an invalid model
// gives whatever findings still make sense.
func Lint(ix *model.Index, profile *model.Profile) []Finding {
	m := ix.Model()
	var out []Finding
	add := func(rule, element string, sev Severity, format string, args ...any) {
		out = append(out, Finding{Rule: rule, Element: element, Severity: sev, Message: fmt.Sprintf(format, args...)})
	}

	siblings := map[string]map[string]bool{}
	for _, n := range m.Nodes {
		p := ix.Parent(n.ID)
		label := strings.ToLower(strings.TrimSpace(n.Label))
		if siblings[p] == nil {
			siblings[p] = map[string]bool{}
		}
		if siblings[p][label] {
			add("label.duplicate-sibling", n.ID, Warning, "%q has the same label as a sibling (%q)", n.ID, n.Label)
		}
		siblings[p][label] = true
		if len(n.Evidence) == 0 {
			add("evidence.missing", n.ID, Info, "%q cites no evidence", n.ID)
		}
		if profile != nil {
			lintNode(ix, n, *profile, add)
		}
	}

	seen := map[string]bool{}
	for _, e := range m.Edges {
		key := e.From + "\x00" + e.To + "\x00" + strings.ToLower(strings.TrimSpace(e.Label)) + "\x00" + e.Kind
		if seen[key] {
			add("edge.duplicate", e.ID, Warning, "%q repeats an earlier relationship from %q to %q", e.ID, e.From, e.To)
		}
		seen[key] = true
		if e.From != e.To && (contains(ix.Ancestors(e.From), e.To) || contains(ix.Ancestors(e.To), e.From)) {
			add("edge.ancestor", e.ID, Warning, "%q joins an area to one that contains it; containment is already the parent field", e.ID)
		}
		if len(e.Evidence) == 0 {
			add("evidence.missing", e.ID, Info, "%q cites no evidence", e.ID)
		}
		if profile != nil {
			lintEdge(ix, e, *profile, add)
		}
	}

	for _, v := range m.Views {
		var stale []string
		check := func(id string) {
			if _, ok := ix.Node(id); !ok && id != "" && !contains(stale, id) {
				stale = append(stale, id)
			}
		}
		check(v.Root)
		for _, id := range v.Collapsed {
			check(id)
		}
		for _, id := range model.SortedKeys(v.Positions) {
			check(id)
		}
		for _, id := range model.SortedKeys(v.Sizes) {
			check(id)
		}
		if len(stale) > 0 {
			add("view.stale", v.ID, Info, "view %q names nodes that no longer exist: %s", v.ID, strings.Join(stale, ", "))
		}
	}
	return out
}

func lintNode(ix *model.Index, n model.Node, p model.Profile, add addFunc) {
	kind, ok := p.NodeKinds[n.Kind]
	switch {
	case n.Kind == "":
		if p.RequireKinds {
			add("profile.kind-required", n.ID, Error, "%q has no kind; profile %s requires one", n.ID, p.ID)
		}
		return
	case !ok:
		add("profile.kind-unknown", n.ID, Error, "%q has kind %q, which profile %s does not declare", n.ID, n.Kind, p.ID)
		return
	}
	if parent, ok := ix.Node(ix.Parent(n.ID)); ok {
		if pk, ok := p.NodeKinds[parent.Kind]; ok && len(pk.Children) > 0 && !contains(pk.Children, n.Kind) {
			add("profile.child", n.ID, Error, "a %s cannot contain a %s (%q in %q)", parent.Kind, n.Kind, n.ID, parent.ID)
		}
	}
	lintProperties(n.ID, n.Properties, kind.Properties, add)
}

func lintEdge(ix *model.Index, e model.Edge, p model.Profile, add addFunc) {
	kind, ok := p.EdgeKinds[e.Kind]
	switch {
	case e.Kind == "":
		if p.RequireKinds {
			add("profile.kind-required", e.ID, Error, "%q has no kind; profile %s requires one", e.ID, p.ID)
		}
		return
	case !ok:
		add("profile.kind-unknown", e.ID, Error, "%q has kind %q, which profile %s does not declare", e.ID, e.Kind, p.ID)
		return
	}
	from, _ := ix.Node(e.From)
	to, _ := ix.Node(e.To)
	if (len(kind.From) > 0 && !contains(kind.From, from.Kind)) || (len(kind.To) > 0 && !contains(kind.To, to.Kind)) {
		add("profile.edge-ends", e.ID, Error, "a %s relationship cannot run from a %q to a %q", e.Kind, from.Kind, to.Kind)
	}
	lintProperties(e.ID, e.Properties, kind.Properties, add)
}

type addFunc func(rule, element string, sev Severity, format string, args ...any)

func lintProperties(id string, have model.Properties, specs map[string]model.PropertySpec, add addFunc) {
	for _, k := range model.SortedKeys(specs) {
		if _, ok := have[k]; !ok && specs[k].Required {
			add("profile.property-required", id, Error, "%q needs property %q", id, k)
		}
	}
	for _, k := range model.SortedKeys(have) {
		spec, ok := specs[k]
		if !ok {
			add("profile.property-unknown", id, Warning, "%q has property %q, which its kind does not declare", id, k)
			continue
		}
		v := have[k]
		if !typeMatches(spec.Type, v) {
			add("profile.property-type", id, Error, "%q property %q must be a %s", id, k, spec.Type)
			continue
		}
		if len(spec.Enum) > 0 && !inEnum(spec.Enum, v) {
			add("profile.property-enum", id, Error, "%q property %q is not one of the allowed values", id, k)
		}
	}
}

func typeMatches(t string, v any) bool {
	switch v.(type) {
	case string:
		return t == "string"
	case bool:
		return t == "bool"
	}
	return t == "number" && model.ScalarValue(v)
}

func inEnum(enum []any, v any) bool {
	for _, e := range enum {
		if fmt.Sprint(e) == fmt.Sprint(v) {
			return true
		}
	}
	return false
}
