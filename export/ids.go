package export

import (
	"strconv"
	"strings"

	"github.com/craggy-io/modelling-services/model"
)

// ids turns names read from text into unique, valid model ids.
type ids struct {
	nodes map[string]string // raw name -> id
	used  map[string]bool
	edges map[string]bool
}

func newIDs() *ids {
	return &ids{nodes: map[string]string{}, used: map[string]bool{}, edges: map[string]bool{}}
}

// node is the id for a raw node name: the name without an "n_" prefix when
// that is a valid id, else its slug; the same raw name always maps to the
// same id.
func (x *ids) node(raw string) string {
	if id, ok := x.nodes[raw]; ok {
		return id
	}
	id := strings.TrimPrefix(raw, "n_")
	if !model.ValidID(id) {
		id = Slug(id)
	}
	id = unique(id, x.used)
	x.nodes[raw] = id
	return id
}

// fresh is a new unique node id slugged from label.
func (x *ids) fresh(label string) string { return unique(Slug(label), x.used) }

// claim reserves an explicit node id, returning false if it is taken or
// invalid.
func (x *ids) claim(id string) bool {
	if !model.ValidID(id) || x.used[id] {
		return false
	}
	x.used[id] = true
	x.nodes[id] = id
	return true
}

// edge is a new unique edge id "<from>--<to>".
func (x *ids) edge(from, to string) string { return unique(cut(from+"--"+to), x.edges) }

func unique(id string, used map[string]bool) string {
	out := id
	for n := 2; used[out]; n++ {
		suffix := "-" + strconv.Itoa(n)
		out = cut(id[:min(len(id), 64-len(suffix))]) + suffix
	}
	used[out] = true
	return out
}

// Slug is s lower-cased, with every run of characters other than a-z and
// 0-9 turned into "-", trimmed of "-" and cut to 64 characters; "node" when
// nothing is left.
func Slug(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			dash = false
		} else if !dash && b.Len() > 0 {
			b.WriteByte('-')
			dash = true
		}
	}
	out := cut(strings.TrimRight(b.String(), "-"))
	if out == "" {
		return "node"
	}
	return out
}

func cut(s string) string {
	if len(s) > 64 {
		s = s[:64]
	}
	return strings.TrimRight(s, "-_")
}
