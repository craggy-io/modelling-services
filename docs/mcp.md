# MCP server

`cmd/modelling-mcp` serves the model tools to agents over the
[Model Context Protocol](https://modelcontextprotocol.io). The agent keeps the model document
and passes it to each tool; the server stores nothing, has no accounts and keeps no sessions.

## Connect

Hosted, nothing to install:

```bash
claude mcp add --transport http craggy-models https://models.craggy.io/mcp
```

Local, over stdio:

```bash
go install github.com/craggy-io/modelling-services/cmd/modelling-mcp@latest
claude mcp add craggy-models -- modelling-mcp
```

Other clients take the same two shapes in their JSON config:

```json
{ "mcpServers": { "craggy-models": { "type": "http", "url": "https://models.craggy.io/mcp" } } }
```

```json
{ "mcpServers": { "craggy-models": { "command": "modelling-mcp" } } }
```

The modeller's **Agent MCP** button shows these setup lines with copy buttons. Agents that
read https://models.craggy.io as text find the same in the page and in
[`/llms.txt`](https://models.craggy.io/llms.txt).

## Tools

| Tool | Does |
| --- | --- |
| `model_import` | Builds a document from a Markdown outline, a Mermaid flowchart or CSV |
| `model_check` | Validates a document and lints it, optionally against a profile |
| `model_apply` | Applies [edit operations](edit.md) all or nothing; returns the new document, lint findings and the inverse operations |
| `model_diff` | Compares two documents ([diff](diff.md)) |
| `model_query` | Neighbours, paths, impact and search ([query](query.md)) |
| `model_export` | Outline, Mermaid, DOT, SVG or CSV ([export](export.md)) |
| `model_open` | A link that opens the document in the [Craggy Modelling](https://models.craggy.io) |

Every tool that takes a document validates it against the [format](format.md) and the default
limits (512 KiB, 1,000 nodes, 2,000 edges). The tools are `modelcap.Tools`: a host that wants
them alongside its stored models can register them on its own capability registry.

A typical session: the agent writes an outline of a system, imports it, refines it with
`model_apply`, reads it back with `model_export format=outline`, and gives the user a
`model_open` link to look at and edit.

## Open links

`model_open` returns `https://models.craggy.io/#m=<data>`, where `<data>` is the canonical
document, raw-deflated and base64url-encoded without padding. It sits in the URL fragment, which
browsers don't send to the server. The modeller decodes it on load, opens it as a new unsaved
model and clears the fragment from the address bar. `conformance/link.json` is the shared
vector: the Go tests and the modeller's tests both decode it to `fixtures/app.json`.

## Run and deploy

```bash
modelling-mcp                       # stdio
modelling-mcp -http :8080           # streamable HTTP at /mcp, health at /health
modelling-mcp -editor http://localhost:5000/   # point model_open at another modeller
```

HTTP mode is stateless and answers with JSON rather than an event stream. Any instance can
answer any request, and it works behind proxies that buffer responses, such as Firebase Hosting.
Request bodies are capped at twice the model size limit. CORS is open because nothing uses
cookies or credentials. `$PORT`, when set, selects HTTP mode on that port, as Cloud Run expects.

The hosted server is the `cmd/modelling-mcp/Dockerfile` image on Cloud Run. models.craggy.io
rewrites `/mcp` to it (see the website repository's `firebase.json`).

```bash
docker build -f cmd/modelling-mcp/Dockerfile --build-arg VERSION=$(git rev-parse --short HEAD) -t modelling-mcp .
```
