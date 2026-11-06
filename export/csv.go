package export

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/craggy-io/foundation-kit/canonjson"

	"github.com/craggy-io/modelling-services/model"
)

var (
	nodeColumns = []string{"id", "label", "parent", "kind", "notes", "tags", "properties"}
	edgeColumns = []string{"id", "from", "to", "label", "kind", "undirected", "notes", "tags", "properties"}
)

// CSV writes m's nodes and edges as two tables. Tags are joined with ";";
// properties are one canonical JSON object. Evidence, links and views are not
// written.
func CSV(m model.Model) (nodes, edges []byte, err error) {
	var nb, eb bytes.Buffer
	nw, ew := csv.NewWriter(&nb), csv.NewWriter(&eb)
	_ = nw.Write(nodeColumns)
	for _, n := range m.Nodes {
		props, err := propsCell(n.Properties)
		if err != nil {
			return nil, nil, err
		}
		_ = nw.Write([]string{n.ID, n.Label, n.Parent, n.Kind, n.Notes, strings.Join(n.Tags, ";"), props})
	}
	_ = ew.Write(edgeColumns)
	for _, e := range m.Edges {
		props, err := propsCell(e.Properties)
		if err != nil {
			return nil, nil, err
		}
		_ = ew.Write([]string{e.ID, e.From, e.To, e.Label, e.Kind, strconv.FormatBool(e.Undirected), e.Notes, strings.Join(e.Tags, ";"), props})
	}
	nw.Flush()
	ew.Flush()
	if err := nw.Error(); err != nil {
		return nil, nil, err
	}
	return nb.Bytes(), eb.Bytes(), ew.Error()
}

// ParseCSV reads the two tables CSV writes (edges may be empty) into a model
// titled title. Columns are found by header name; only id and label (and
// from and to for edges) are required. The result is not validated.
func ParseCSV(title string, nodes, edges []byte) (model.Model, error) {
	m := model.New(title, "Imported from CSV")
	rows, col, err := readTable(nodes, "nodes", "id", "label")
	if err != nil {
		return m, err
	}
	for i, r := range rows {
		props, err := parseProps(col(r, "properties"))
		if err != nil {
			return m, fmt.Errorf("%w: nodes row %d: %v", model.ErrInvalid, i+2, err)
		}
		m.Nodes = append(m.Nodes, model.Node{ID: col(r, "id"), Label: col(r, "label"), Parent: col(r, "parent"),
			Kind: col(r, "kind"), Notes: col(r, "notes"), Tags: splitTags(col(r, "tags")), Properties: props})
	}
	if len(bytes.TrimSpace(edges)) == 0 {
		return m, nil
	}
	rows, col, err = readTable(edges, "edges", "id", "from", "to", "label")
	if err != nil {
		return m, err
	}
	for i, r := range rows {
		props, err := parseProps(col(r, "properties"))
		if err != nil {
			return m, fmt.Errorf("%w: edges row %d: %v", model.ErrInvalid, i+2, err)
		}
		m.Edges = append(m.Edges, model.Edge{ID: col(r, "id"), From: col(r, "from"), To: col(r, "to"), Label: col(r, "label"),
			Kind: col(r, "kind"), Undirected: col(r, "undirected") == "true", Notes: col(r, "notes"),
			Tags: splitTags(col(r, "tags")), Properties: props})
	}
	return m, nil
}

func readTable(data []byte, name string, required ...string) ([][]string, func([]string, string) string, error) {
	records, err := csv.NewReader(bytes.NewReader(data)).ReadAll()
	if err != nil {
		return nil, nil, fmt.Errorf("%w: %s csv: %v", model.ErrInvalid, name, err)
	}
	if len(records) == 0 {
		return nil, nil, fmt.Errorf("%w: %s csv has no header", model.ErrInvalid, name)
	}
	at := map[string]int{}
	for i, h := range records[0] {
		at[strings.ToLower(strings.TrimSpace(h))] = i
	}
	for _, r := range required {
		if _, ok := at[r]; !ok {
			return nil, nil, fmt.Errorf("%w: %s csv needs a %q column", model.ErrInvalid, name, r)
		}
	}
	col := func(row []string, name string) string {
		if i, ok := at[name]; ok && i < len(row) {
			return strings.TrimSpace(row[i])
		}
		return ""
	}
	return records[1:], col, nil
}

func propsCell(p model.Properties) (string, error) {
	if len(p) == 0 {
		return "", nil
	}
	raw, err := canonjson.Marshal(p)
	return string(raw), err
}

func parseProps(cell string) (model.Properties, error) {
	if cell == "" {
		return nil, nil
	}
	var p model.Properties
	if err := json.Unmarshal([]byte(cell), &p); err != nil {
		return nil, fmt.Errorf("properties must be a JSON object: %v", err)
	}
	return p, nil
}

func splitTags(cell string) []string {
	var out []string
	for _, t := range strings.Split(cell, ";") {
		if t = strings.TrimSpace(t); t != "" {
			out = append(out, t)
		}
	}
	return out
}
