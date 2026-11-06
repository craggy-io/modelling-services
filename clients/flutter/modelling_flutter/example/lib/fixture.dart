// Copies of conformance/fixtures/app.json and android-profile.json, so the
// example builds for the web without reading files.

const appJson = r'''{
  "format": "craggy.model",
  "version": 2,
  "title": "Payment app",
  "subject": "com.example.pay 4.2.1",
  "profile": "craggy.profile/android-app@1",
  "nodes": [
    {"id": "app", "label": "Application", "kind": "app"},
    {"id": "ui", "label": "UI layer", "parent": "app", "kind": "component", "properties": {"language": "kotlin"}},
    {"id": "net", "label": "Network layer", "parent": "app", "kind": "component", "notes": "OkHttp with pinning.", "tags": ["attack-surface"],
      "properties": {"language": "kotlin", "exported": false},
      "evidence": [{"id": "ev1", "caption": "Pinner config", "ref": {"scheme": "artifact", "id": "a1", "selector": "/res/xml/nsc.xml"}}]},
    {"id": "pinner", "label": "Certificate pinner", "parent": "net", "kind": "class"},
    {"id": "native", "label": "Native libraries", "kind": "component", "link": {"model": "m-native"}},
    {"id": "server", "label": "Payment server"}
  ],
  "edges": [
    {"id": "e1", "from": "ui", "to": "net", "label": "calls", "kind": "calls"},
    {"id": "e2", "from": "net", "to": "server", "label": "talks to", "kind": "calls",
      "evidence": [{"id": "ev1", "caption": "Traffic capture", "ref": {"scheme": "artifact", "id": "a2"}}]},
    {"id": "e3", "from": "pinner", "to": "native", "label": "loads"},
    {"id": "e4", "from": "ui", "to": "native", "label": "shares data with", "undirected": true}
  ],
  "views": [
    {"id": "overview", "title": "Overview", "renderer": "blocks", "collapsed": ["net"]}
  ]
}''';

const profileJson = r'''{
  "id": "craggy.profile/android-app",
  "version": 1,
  "title": "Android application",
  "requireKinds": true,
  "nodeKinds": {
    "app": {"label": "Application", "children": ["component"]},
    "component": {"label": "Component", "children": ["component", "class"],
      "properties": {
        "language": {"type": "string", "enum": ["java", "kotlin", "native"]},
        "exported": {"type": "bool"}
      }},
    "class": {"label": "Class"}
  },
  "edgeKinds": {
    "calls": {"label": "calls", "from": ["component", "class"], "to": ["component", "class"]}
  }
}''';
