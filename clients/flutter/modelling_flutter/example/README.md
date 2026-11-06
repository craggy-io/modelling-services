# modelling_flutter example

`ModelWorkspace` with every renderer (blocks, outline, graph, matrix, table) over `conformance/fixtures/app.json` (copied into `lib/fixture.dart`) with its
profile, loaded from a `MemoryModelSource` and compared against a base revision so diff mode shows.

```bash
flutter run -d chrome   # or -d windows
flutter build web
```
