// no_areas.dart: what a renderer shows when it draws no area.

import 'package:flutter/widgets.dart';

import '../controller/model_controller.dart';
import '../theme/model_theme.dart';

/// The empty state: how to start when the model has no areas, or that the
/// search and filters match none.
class NoAreas extends StatelessWidget {
  const NoAreas({super.key, required this.controller});

  final ModelController controller;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (controller.model.nodes.isNotEmpty) {
      text = 'No matching areas.';
    } else if (controller.readOnly) {
      text = 'This model has no areas.';
    } else {
      text = 'No areas yet. Use "Add area" to start.';
    }
    return Center(child: Text(text, style: ModelTheme.of(context).small));
  }
}
