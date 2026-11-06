/// Renders and edits block models (design §7) on Flutter desktop and web,
/// on top of the pure-Dart `modelling` package.
///
/// - [ModelController]: the open model, edit history, diff and view state.
/// - [ModelWorkspace]: toolbar, status line and the active [ModelRenderer]
///   ([BlocksRenderer], [OutlineRenderer], [GraphRenderer],
///   [MatrixRenderer], [TableRenderer], or a host's own).
/// - [ModelTheme] and [ModelChrome]: the host's tokens and widgets.
/// - [ModelSource]: [MemoryModelSource], [FileModelSource], or a host's.
library;

export 'src/chrome/material_chrome.dart' show MaterialModelChrome;
export 'src/chrome/model_chrome.dart'
    show ModelChrome, ModelChromeScope, ModelButtonVariant, ModelButtonSize, ModelOption, ModelMenuItem;
export 'src/controller/model_controller.dart' show ModelController;
export 'src/controller/model_editing.dart' show ModelEditing;
export 'src/controller/model_types.dart' show ModelElementKind, ModelElementRef, OverlayMark, ModelOverlay;
export 'src/inspector/field_editors.dart'
    show CommitField, PropertiesEditor, parseProperty, parseTags, propertyText, propertyEditor;
export 'src/inspector/inspector.dart' show inspectElement, confirmDeleteNode;
export 'src/inspector/inspector_sections.dart'
    show InspectorSection, InspectorValue, EvidenceSection, RelationshipsSection, ChangesSection, LintSection;
export 'src/renderers/blocks/blocks_board.dart' show BlocksBoard;
export 'src/renderers/blocks/blocks_layout.dart' show BlockArea, BlocksLayout, layoutBlocks;
export 'src/renderers/blocks/blocks_renderer.dart' show BlocksRenderer;
export 'src/renderers/graph/graph_layout.dart' show GraphBox, GraphLayout, GraphMetrics, layoutGraph;
export 'src/renderers/graph/graph_renderer.dart' show GraphRenderer, GraphView;
export 'src/renderers/matrix/matrix_layout.dart' show MatrixCell, MatrixLayout, MatrixMetrics, layoutMatrix;
export 'src/renderers/matrix/matrix_renderer.dart' show MatrixRenderer, MatrixView;
export 'src/renderers/model_renderer.dart' show ModelRenderer;
export 'src/renderers/outline/outline_renderer.dart' show OutlineRenderer, OutlineView;
export 'src/renderers/outline/outline_rows.dart' show OutlineRow, outlineRows;
export 'src/renderers/table/table_renderer.dart' show TableRenderer, TableView;
export 'src/shared/inline_rename.dart' show InlineRenameField, InlineRenameState;
export 'src/shared/model_canvas.dart' show ModelCanvas, CanvasBuilder;
export 'src/shared/markers.dart' show ChangeMarker, ModelBadge, elementMarks, changeColour, severityColour;
export 'src/shared/model_diff.dart' show ModelDiff;
export 'src/shared/new_relationship.dart' show promptRelationship;
export 'src/shared/relationship_colours.dart' show relationshipSlots;
export 'src/shared/relationship_row.dart' show RelationshipRow, relationshipEnds, relationshipColour;
export 'src/shared/shown_elements.dart' show ShownNode, shownNodes, shownEdges;
export 'src/shared/visibility.dart' show ModelVisibility;
export 'src/sources/file_source.dart' show FileModelSource;
export 'src/sources/memory_source.dart' show MemoryModelSource;
export 'src/sources/model_source.dart' show ModelSource, ModelSummary, LoadedModel;
export 'src/theme/model_theme.dart' show ModelTheme, ModelThemeScope, ModelSpacing, ModelMotion, reducedMotion;
export 'src/workspace/model_export.dart' show ModelExport, runExport, captureBoundaryPng, exportStem;
export 'src/workspace/model_hooks.dart'
    show ModelHooks, ModelHooksScope, ModelEvidenceHook, ModelAttachHook, ModelLinkHook, captureModelScopes;
export 'src/workspace/model_workspace.dart' show ModelWorkspace, ModelSaveHook;
export 'src/workspace/workspace_status.dart' show statusLine, WorkspaceStatus;
