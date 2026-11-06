package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	mcpsdk "github.com/modelcontextprotocol/go-sdk/mcp"
)

// TestHTTP drives the server as a hosted agent would: a stateless
// streamable HTTP client lists the tools, imports an outline and opens it.
func TestHTTP(t *testing.T) {
	server, stop, err := newServer("https://models.example/")
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	ts := httptest.NewServer(handler(server))
	defer ts.Close()

	ctx := context.Background()
	client := mcpsdk.NewClient(&mcpsdk.Implementation{Name: "test", Version: "1"}, nil)
	cs, err := client.Connect(ctx, &mcpsdk.StreamableClientTransport{Endpoint: ts.URL + "/mcp"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer cs.Close()
	if got := cs.InitializeResult().Instructions; !strings.Contains(got, "model_open") {
		t.Fatalf("instructions: %q", got)
	}

	list, err := cs.ListTools(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tool := range list.Tools {
		names = append(names, tool.Name)
	}
	if got := strings.Join(names, " "); got != "model_apply model_check model_diff model_export model_import model_open model_query" {
		t.Fatalf("tools: %s", got)
	}

	imported := callTool(t, cs, "model_import", map[string]any{"format": "outline", "source": "# Shop\n\nWeb shop\n\n- **Web** `web`\n- **Db** `db`\n"})
	opened := callTool(t, cs, "model_open", map[string]any{"document": imported["document"]})
	if url, _ := opened["url"].(string); !strings.HasPrefix(url, "https://models.example/#m=") {
		t.Fatalf("open: %v", opened)
	}

	res, err := cs.CallTool(ctx, &mcpsdk.CallToolParams{Name: "model_export", Arguments: map[string]any{"document": imported["document"], "format": "nope"}})
	if err != nil || !res.IsError {
		t.Fatalf("bad format should be a tool error: %v %v", res, err)
	}
}

func callTool(t *testing.T, cs *mcpsdk.ClientSession, name string, args map[string]any) map[string]any {
	t.Helper()
	res, err := cs.CallTool(context.Background(), &mcpsdk.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("%s: %s", name, res.Content[0].(*mcpsdk.TextContent).Text)
	}
	var out map[string]any
	raw, _ := json.Marshal(res.StructuredContent)
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestHTTPEdges(t *testing.T) {
	server, stop, err := newServer("https://models.example/")
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	ts := httptest.NewServer(handler(server))
	defer ts.Close()

	health, err := http.Get(ts.URL + "/health")
	if err != nil || health.StatusCode != http.StatusOK {
		t.Fatalf("health: %v %v", health, err)
	}

	pre, _ := http.NewRequest(http.MethodOptions, ts.URL+"/mcp", nil)
	res, err := http.DefaultClient.Do(pre)
	if err != nil || res.StatusCode != http.StatusNoContent || res.Header.Get("Access-Control-Allow-Origin") != "*" {
		t.Fatalf("preflight: %v %v", res, err)
	}

	big := strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"pad":"` + strings.Repeat("x", int(maxBody)) + `"}}`)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/mcp", big)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/event-stream")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode < 400 {
		t.Fatalf("oversized body accepted: %d %s", res.StatusCode, body)
	}
}
