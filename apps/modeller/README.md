# modeller

The standalone block-model editor ([design](../../docs/design.md) §7.7) for Windows and the web. It uses only
`modelling` and `modelling_flutter`; features belong in the package, not here.

- **File**: New blank, New from template (`assets/templates/`: the conformance `app.json` and a system
  context), Import Mermaid or outline (paste), Open (`.json` models, `.mmd`, `.md`), Save, Save as, Export
  (Mermaid, outline, model JSON, PNG through the package's `runExport`). Unsaved edits are confirmed before
  New, Import or Open discards them.
- **Profile**: the bundled `assets/profiles/android-profile.json`, or none; choosing one is an undoable edit
  of the model's `profile`.
- **Renderers**: blocks, outline, graph, matrix and table, switched in the workspace toolbar.
- **Gallery**: every renderer on each sample, including a diff (base vs revised) and a findings overlay.

```bash
flutter run -d windows   # or -d chrome
flutter analyze && flutter test && flutter build web && flutter build windows
```
