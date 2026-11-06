// model_renderer.dart: the renderer contract (design §7.2). A renderer
// draws the controller's model and sends intents to it; it keeps no model
// state, so switching renderer keeps the user's place. Add one by
// implementing this and listing it in ModelWorkspace.renderers.

import 'package:flutter/widgets.dart';

import '../controller/model_controller.dart';
import '../theme/model_theme.dart';

/// One way of drawing a model (blocks, outline, graph, matrix, table, …).
abstract class ModelRenderer {
  const ModelRenderer();

  /// Stable id, also used as a saved view's `renderer`.
  String get id;

  /// Shown in the workspace's renderer switcher.
  String get label;
  IconData get icon;

  /// The renderer's widget for [controller].
  Widget build(BuildContext context, ModelController controller);

  /// How many areas it currently shows, for the workspace status line.
  /// Defaults to every area the search and filter include.
  int shownAreas(ModelController controller, ModelTheme theme) => controller.visibility.included.length;
}
