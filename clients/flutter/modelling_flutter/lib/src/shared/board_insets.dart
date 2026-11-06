// board_insets.dart: how a renderer fills a full-bleed board. The editor
// hands each renderer its whole board and says, through BoardInsets, how
// far the content should keep from the edges; the renderer applies that
// inside its own scrollables and surfaces, so backdrops, rows and
// highlights reach the edges. With no BoardInsets (the workspace) a
// renderer lays out as before.

import 'package:flutter/widgets.dart';

/// The content inset of a full-bleed board.
class BoardInsets extends InheritedWidget {
  const BoardInsets({super.key, required this.padding, required super.child});

  final EdgeInsets padding;

  /// The nearest board's inset, or null when the renderer is not on a
  /// full-bleed board.
  static EdgeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardInsets>()?.padding;

  @override
  bool updateShouldNotify(BoardInsets oldWidget) => oldWidget.padding != padding;
}
