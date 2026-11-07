// model_chrome.dart: the few host-styled pieces the renderers and the
// workspace are built from (design §7.4). Labs implements this with its
// Craggy* widgets; ModelChrome.material() is the default.

import 'package:flutter/widgets.dart';

import 'material_chrome.dart';

/// How prominent a button is.
enum ModelButtonVariant { primary, secondary, ghost, link }

/// Button and icon-button sizes.
enum ModelButtonSize { sm, md }

/// One choice in [ModelChrome.select].
@immutable
class ModelOption<T> {
  const ModelOption(this.value, this.label);

  final T value;
  final String label;
}

/// One row of a menu: an item, a submenu or a divider.
@immutable
sealed class ModelMenuEntry {
  const ModelMenuEntry();
}

/// A choice in a menu ([ModelChrome.menuButton], [ModelChrome.menu]).
class ModelMenuItem extends ModelMenuEntry {
  const ModelMenuItem({required this.label, this.icon, required this.onSelected, this.shortcut});

  final String label;
  final IconData? icon;
  final VoidCallback onSelected;

  /// The key that also runs it, shown as a hint (the menu does not bind
  /// it; the host does, e.g. through ModelEditor.shortcuts).
  final SingleActivator? shortcut;
}

/// A menu row that opens [entries] beside it.
class ModelSubmenu extends ModelMenuEntry {
  const ModelSubmenu({required this.label, this.icon, required this.entries});

  final String label;
  final IconData? icon;
  final List<ModelMenuEntry> entries;
}

/// A hairline between groups of menu rows.
class ModelMenuDivider extends ModelMenuEntry {
  const ModelMenuDivider();
}

/// Builders for the host-styled pieces. Implementations must keep these
/// defaults, because Dart takes default values from the implementation.
abstract class ModelChrome {
  const ModelChrome();

  /// Material widgets coloured from the nearest [ModelTheme].
  const factory ModelChrome.material() = MaterialModelChrome;

  /// The nearest [ModelChromeScope]'s chrome, else [ModelChrome.material].
  static ModelChrome of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModelChromeScope>()?.chrome ?? const ModelChrome.material();

  /// A labelled button; null [onPressed] disables it.
  Widget button({
    Key? key,
    required String label,
    IconData? icon,
    required VoidCallback? onPressed,
    ModelButtonVariant variant = ModelButtonVariant.secondary,
    ModelButtonSize size = ModelButtonSize.md,
    String? tooltip,
  });

  /// An icon-only button; [tooltip] is also its accessible label.
  Widget iconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
    ModelButtonSize size = ModelButtonSize.sm,
  });

  /// A toggle chip (theme.md §5.7 filter chip).
  Widget filterChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    String? tooltip,
  });

  /// A search box.
  Widget searchField({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    String hint = 'Search',
    ValueChanged<String>? onChanged,
  });

  /// A text input for inline rename, notes and property values.
  Widget textField({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    String? label,
    String? hint,
    String? error,
    bool multiline = false,
    bool autofocus = false,
    bool dense = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  });

  /// A dropdown over [options]; a [value] not among them shows [hint].
  Widget select<T>({
    Key? key,
    required T value,
    required List<ModelOption<T>> options,
    required ValueChanged<T>? onChanged,
    String? label,
    String hint = 'Choose',
  });

  /// An icon that opens a menu of [items]. A [badge] (an account's
  /// initials) shows in a round accent disc in place of the icon.
  Widget menuButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required List<ModelMenuItem> items,
    String? badge,
  });

  /// A labelled menu (a host's File menu): a ghost button that opens
  /// [entries], with leading icons, shortcut hints, dividers and submenus.
  Widget menu({Key? key, required String label, required List<ModelMenuEntry> entries});

  /// A removable tag badge; null [onRemove] hides its ×.
  Widget tagChip({Key? key, required String label, VoidCallback? onRemove});

  /// The frame of a composite input (the tags field): the text field's
  /// fill, border, focus ring and [label] around [child].
  Widget fieldFrame({Key? key, required Widget child, required bool focused, required bool empty, String? label});

  /// A small coloured dot (change markers, lint, legends).
  Widget statusDot({Key? key, required Color color, String? tooltip, double? size});

  /// Wraps [child] with a hover tooltip.
  Widget tooltip({Key? key, required String message, required Widget child});

  /// A content dialog: title, subtitle, a scrolling [body] and [actions]
  /// (built in the dialog's context, so they can pop it) beside Close.
  Future<void> showInspector(
    BuildContext context, {
    required String title,
    String subtitle = '',
    List<Widget> Function(BuildContext context)? actions,
    required WidgetBuilder body,
  });

  /// Asks a yes/no question; true when confirmed.
  Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  });
}

/// Provides a [ModelChrome] to the renderers below it.
class ModelChromeScope extends InheritedWidget {
  const ModelChromeScope({super.key, required this.chrome, required super.child});

  final ModelChrome chrome;

  @override
  bool updateShouldNotify(ModelChromeScope oldWidget) => !identical(chrome, oldWidget.chrome);
}
