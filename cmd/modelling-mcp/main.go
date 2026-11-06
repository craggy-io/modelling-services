// Command modelling-mcp serves the stateless model tools (modelcap.Tools) to
// agents over the Model Context Protocol. Agents keep their model documents;
// the server stores nothing.
//
//	modelling-mcp                 # stdio, for a local agent
//	modelling-mcp -http :8080     # streamable HTTP at /mcp, stateless, JSON responses
//
// With neither -http nor $PORT set it speaks stdio. $PORT (as Cloud Run sets
// it) serves HTTP on that port.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"syscall"
	"time"

	regmcp "github.com/craggy-io/capability-services/mcp"
	"github.com/craggy-io/capability-services/registry"
	mcpsdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/craggy-io/modelling-services/model"
	"github.com/craggy-io/modelling-services/modelcap"
)

// maxBody bounds one HTTP request: a diff carries two documents at the
// model size limit, plus the JSON-RPC envelope.
var maxBody = int64(2*model.DefaultLimits.MaxBytes + 64<<10)

const instructions = `Tools for block models: JSON documents of labelled areas nested by containment, labelled relationships between them, typed properties and cited evidence (format "craggy.model", version 2). Use them to sketch the architecture of a system, an app, an organisation or a process.

Nothing is stored: you keep the document and pass it to each tool. A good flow:
1. model_import an outline (or write the document and model_check it).
2. model_apply small operations to change it; each returns the new document and lint findings worth fixing.
3. model_export format=outline to read a large model back cheaply; mermaid, dot, svg or csv for other tools.
4. model_open returns a link that opens the model in the Craggy Modeller (https://models.craggy.io) for a person to view and edit visually. Share it with the user.`

func main() {
	addr := flag.String("http", "", "serve streamable HTTP on this address (e.g. :8080) instead of stdio")
	editor := flag.String("editor", "https://models.craggy.io/", "modeller address that model_open links to")
	flag.Parse()
	if *addr == "" && os.Getenv("PORT") != "" {
		*addr = ":" + os.Getenv("PORT")
	}

	server, stop, err := newServer(*editor)
	if err != nil {
		log.Fatal(err)
	}
	defer stop()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if *addr == "" {
		if err := server.Run(ctx, &mcpsdk.StdioTransport{}); err != nil && !errors.Is(err, context.Canceled) {
			log.Fatal(err)
		}
		return
	}
	if err := serveHTTP(ctx, *addr, server); err != nil {
		log.Fatal(err)
	}
}

// newServer is the MCP server with the model tools registered.
func newServer(editor string) (*mcpsdk.Server, func(), error) {
	tools := modelcap.NewTools(modelcap.ToolDeps{Prefix: "model", Editor: editor})
	r := registry.New()
	if err := r.AddGroup(tools.Group()); err != nil {
		r.Close()
		return nil, nil, err
	}
	if err := r.Add(tools.Capabilities()...); err != nil {
		r.Close()
		return nil, nil, err
	}
	server := mcpsdk.NewServer(
		&mcpsdk.Implementation{Name: "craggy-models", Title: "Craggy Models", Version: version()},
		&mcpsdk.ServerOptions{Instructions: instructions},
	)
	stopServe := regmcp.Serve(server, r.View(registry.All))
	return server, func() { stopServe(); r.Close() }, nil
}

// handler serves MCP at /mcp and a health check at /health (Cloud Run
// reserves paths ending in z, such as /healthz).
func handler(server *mcpsdk.Server) http.Handler {
	mcp := mcpsdk.NewStreamableHTTPHandler(
		func(*http.Request) *mcpsdk.Server { return server },
		// Stateless with JSON responses: any instance answers any request,
		// and proxies that buffer responses (Firebase Hosting) still work.
		&mcpsdk.StreamableHTTPOptions{Stateless: true, JSONResponse: true},
	)
	mux := http.NewServeMux()
	mux.Handle("/mcp", cors(http.MaxBytesHandler(mcp, maxBody)))
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "ok") })
	return mux
}

// cors lets browser-based MCP clients call the server. Nothing here uses
// cookies or credentials, so any origin may.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Methods", "POST, GET, DELETE, OPTIONS")
		h.Set("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id, Last-Event-ID")
		h.Set("Access-Control-Expose-Headers", "Mcp-Session-Id")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func serveHTTP(ctx context.Context, addr string, server *mcpsdk.Server) error {
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler(server),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(shutdown)
	}()
	log.Printf("modelling-mcp %s listening on %s", version(), addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// release is the version stamped at build time (see Dockerfile).
var release string

// version is the stamped release, else the module version or VCS revision
// this binary was built from.
func version() string {
	if release != "" {
		return release
	}
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "dev"
	}
	if v := info.Main.Version; v != "" && v != "(devel)" {
		return v
	}
	for _, s := range info.Settings {
		if s.Key == "vcs.revision" && len(s.Value) >= 7 {
			return s.Value[:7]
		}
	}
	return "dev"
}
