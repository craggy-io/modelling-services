package modellingservices_test

import (
	"strings"
	"testing"

	"github.com/craggy-io/foundation-kit/archtest"
)

// allow lets the from packages import only the listed in-module packages.
func allow(from []string, imports ...string) archtest.Rule {
	return archtest.Rule{
		Name:   "layers for " + strings.Join(from, ", "),
		Why:    "imports point down the layers in AGENTS.md; change the table there first",
		From:   from,
		Forbid: []string{"./..."},
		Allow:  imports,
	}
}

// TestLayering enforces the AGENTS.md layer table: format, then engines,
// then host adapters. Only modelcap may import capability-services, and only
// kinds the foundation-kit bundle packages.
func TestLayering(t *testing.T) {
	archtest.Check(t, archtest.Config{
		Packages: []string{"./model", "./diff", "./edit", "./query", "./export", "./modelcap", "./kinds"},
		Rules: []archtest.Rule{
			allow([]string{"./model"}),
			allow([]string{"./diff", "./edit", "./query", "./export"}, "./model"),
			allow([]string{"./modelcap"}, "./model", "./diff", "./edit", "./query", "./export"),
			allow([]string{"./kinds"}, "./model"),
			{
				Name: "only modelcap serves capabilities", Why: "engines are transport-free",
				From: []string{"./..."}, Except: []string{"./modelcap"},
				Forbid: []string{"github.com/craggy-io/capability-services/..."},
			},
			{
				Name: "only kinds reads bundles", Why: "the format does not depend on the loader",
				From: []string{"./..."}, Except: []string{"./kinds"},
				Forbid: []string{"github.com/craggy-io/foundation-kit/bundle/...", "github.com/craggy-io/foundation-kit/kind/..."},
			},
			{
				Name: "never the private app", Why: "this library is public; craggy-labs consumes it, not the reverse",
				From: []string{"./..."}, Forbid: []string{"github.com/craggy-io/craggy-labs/..."},
			},
		},
	})
}
