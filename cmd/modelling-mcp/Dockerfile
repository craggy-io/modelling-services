# The hosted MCP server. Build from the repository root:
#   docker build -f cmd/modelling-mcp/Dockerfile --build-arg VERSION=$(git rev-parse --short HEAD) .
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.release=${VERSION}" -o /modelling-mcp ./cmd/modelling-mcp

FROM gcr.io/distroless/static:nonroot
COPY --from=build /modelling-mcp /modelling-mcp
USER nonroot
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/modelling-mcp"]
