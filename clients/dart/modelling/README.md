# modelling (Dart)

The pure-Dart twin of modelling-services' Go packages: `model`, `diff`, `edit`, `query` and the Mermaid and
outline parts of `export` (design §4, §6). No Flutter dependency, so it runs in `dart test`, on the web and in a CLI.

```dart
import 'package:modelling/modelling.dart';

final model = Model.decode(json);                  // strict; upgrades version 1
model.validate();                                  // throws ModelValidationException
final (next, inverse) = apply(model, [Op.nodeAdd(Node(id: 'db', label: 'Database'))]);
final changes = compare(model, next);              // ChangeSet; toJson() matches Go
final hits = search(next.index, Filter(text: 'pinning'));
final text = toMermaid(next);                      // byte-identical to Go
```

Front door (`lib/modelling.dart`):

- **Model types** — `Model`, `Node`, `Edge`, `Evidence`, `Ref`, `Link`, `View`, `Filter`, `Profile`, `NodeKind`,
  `EdgeKind`, `PropertySpec`: immutable values with `fromJson`/`toJson`, `copyWith` and value equality.
- **Codec** — `Model.decode`, `Model.encode` (canonical JSON, byte-identical to Go's `canonjson`), `Profile.decode`,
  `canonicalJson`, `ModelFormatException`.
- **Validation** — `Model.issues([Limits])`, `Model.validate`, `Issue`, `Limits`, `ModelValidationException`.
- **Index** — `ModelIndex` (`model.index`): children, parent, ancestors, descendants, touching edges, depth.
- **Diff** — `compare(base, revision, views: false)` → `ChangeSet`.
- **Edit** — `Op` (14 operations, `Ops` names), `apply(model, ops, [limits])` → `(result, inverse)` or
  `EditException`; `EditHistory` for undo/redo, typing merge and `pendingOps` since `markSaved()`.
- **Query** — `search`, `haystack`, `neighbours`, `paths`, `impact`, `lint` (`Finding`, `Severity`).
- **Export** — `toMermaid`, `parseMermaid`, `toOutline`, `parseOutline`, `slug`.

## The contract

The shared vectors in `../../../conformance/` are the contract between the Go and Dart implementations.
`test/conformance_test.dart` runs every file there exactly as `conformance/conformance_test.go` does. A behaviour
change lands as a new vector first, then in both languages.

```sh
dart pub get
dart analyze
dart format --set-exit-if-changed .
dart test
```
