// material_chrome.dart: ModelChrome built from Material widgets, coloured
// from the nearest ModelTheme so it suits the board in light and dark.

import 'package:flutter/material.dart';

import '../theme/model_theme.dart';
import 'material_menu.dart';
import 'model_chrome.dart';

/// The default [ModelChrome].
class MaterialModelChrome extends ModelChrome {
  const MaterialModelChrome();

  static Widget _material(Widget child) => Material(type: MaterialType.transparency, child: child);

  @override
  Widget button({
    Key? key,
    required String label,
    IconData? icon,
    required VoidCallback? onPressed,
    ModelButtonVariant variant = ModelButtonVariant.secondary,
    ModelButtonSize size = ModelButtonSize.md,
    String? tooltip,
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      final small = size == ModelButtonSize.sm;
      final (Color? fill, Color fg) = switch (variant) {
        ModelButtonVariant.primary => (t.focus, t.surface),
        ModelButtonVariant.secondary => (t.raised, t.text),
        ModelButtonVariant.ghost => (null, t.text),
        ModelButtonVariant.link => (null, t.changed),
      };
      final style = TextButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: fg,
        disabledBackgroundColor: fill == null ? null : t.raised,
        disabledForegroundColor: t.muted,
        minimumSize: Size(0, small ? 28 : 32),
        padding: EdgeInsets.symmetric(horizontal: variant == ModelButtonVariant.link ? 4 : (small ? 10 : 12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: (small ? t.small : t.standard).copyWith(
          fontWeight: variant == ModelButtonVariant.primary ? FontWeight.w600 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius)),
      );
      final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
      final Widget b = icon == null
          ? TextButton(onPressed: onPressed, style: style, child: text)
          : TextButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: small ? 16 : t.iconSize),
              label: text,
            );
      return _material(tooltip == null ? b : Tooltip(message: tooltip, child: b));
    },
  );

  @override
  Widget iconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
    ModelButtonSize size = ModelButtonSize.sm,
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      final small = size == ModelButtonSize.sm;
      final side = small ? 28.0 : 32.0;
      // A fixed square with no padding, so the glyph sits on its centre
      // whatever the density or the hover shape.
      return _material(
        IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: small ? 16 : t.iconSize),
          color: color ?? t.muted,
          padding: EdgeInsets.zero,
          alignment: Alignment.center,
          constraints: BoxConstraints.tightFor(width: side, height: side),
          style: IconButton.styleFrom(
            fixedSize: Size.square(side),
            minimumSize: Size.square(side),
            maximumSize: Size.square(side),
            padding: EdgeInsets.zero,
            hoverColor: t.hover,
            highlightColor: t.hover,
            disabledForegroundColor: t.muted.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.innerRadius(2))),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          ),
        ),
      );
    },
  );

  @override
  Widget filterChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    String? tooltip,
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      return _material(
        FilterChip(
          label: Text(label, style: t.small.copyWith(color: selected ? t.text : t.muted)),
          selected: selected,
          showCheckmark: false,
          tooltip: tooltip,
          onSelected: onPressed == null ? null : (_) => onPressed(),
          backgroundColor: t.raised,
          selectedColor: t.focus.withValues(alpha: 0.16),
          side: BorderSide(color: selected ? t.focus : t.raised),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    },
  );

  InputDecoration _decoration(
    ModelTheme t, {
    String? label,
    String? hint,
    String? error,
    Widget? prefix,
    bool dense = true,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    prefixIcon: prefix,
    prefixIconConstraints: prefix == null ? null : const BoxConstraints(minWidth: 36, minHeight: 32),
    isDense: dense,
    filled: true,
    fillColor: t.raised,
    labelStyle: t.small,
    hintStyle: t.small,
    contentPadding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs + 2),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.radius), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(t.radius),
      borderSide: BorderSide(color: t.focus, width: 1.5),
    ),
  );

  @override
  Widget searchField({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    String hint = 'Search',
    ValueChanged<String>? onChanged,
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      return _material(
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          style: t.standard,
          decoration: _decoration(
            t,
            hint: hint,
            prefix: Icon(Icons.search, size: t.iconSize, color: t.muted),
          ),
        ),
      );
    },
  );

  @override
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
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      return _material(
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          minLines: multiline ? 2 : 1,
          maxLines: multiline ? 6 : 1,
          keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
          textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: dense ? t.heading : t.standard,
          decoration: _decoration(t, label: label, hint: hint, error: error),
        ),
      );
    },
  );

  @override
  Widget select<T>({
    Key? key,
    required T value,
    required List<ModelOption<T>> options,
    required ValueChanged<T>? onChanged,
    String? label,
    String hint = 'Choose',
  }) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      final at = options.indexWhere((o) => o.value == value);
      return _material(
        InputDecorator(
          decoration: _decoration(t, label: label),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: at < 0 ? null : at,
              isDense: true,
              isExpanded: true,
              hint: Text(hint, style: t.small),
              style: t.standard,
              dropdownColor: t.surface,
              items: [
                for (var i = 0; i < options.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(options[i].label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged == null ? null : (i) => i == null ? null : onChanged(options[i].value),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget menuButton({Key? key, required IconData icon, required String tooltip, required List<ModelMenuItem> items}) =>
      MaterialMenuAnchor(
        key: key,
        entries: items,
        trigger: (open) => iconButton(icon: icon, tooltip: tooltip, size: ModelButtonSize.md, onPressed: open),
      );

  @override
  Widget menu({Key? key, required String label, required List<ModelMenuEntry> entries}) => MaterialMenuAnchor(
    key: key,
    entries: entries,
    trigger: (open) =>
        button(label: label, variant: ModelButtonVariant.ghost, size: ModelButtonSize.sm, onPressed: open),
  );

  @override
  Widget tagChip({Key? key, required String label, VoidCallback? onRemove}) => Builder(
    key: key,
    builder: (context) {
      final t = ModelTheme.of(context);
      return Container(
        height: 22,
        padding: EdgeInsets.only(left: t.spacing.xs, right: onRemove == null ? t.spacing.xs : 2),
        decoration: BoxDecoration(
          color: t.focus.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(t.innerRadius(4)),
          border: Border.all(color: t.focus.withValues(alpha: 0.35), width: t.borderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: t.text, height: 1.2),
              ),
            ),
            if (onRemove != null)
              _material(
                InkResponse(
                  onTap: onRemove,
                  radius: 10,
                  child: Tooltip(
                    message: 'Remove $label',
                    child: SizedBox.square(
                      dimension: 18,
                      child: Center(child: Icon(Icons.close_rounded, size: 12, color: t.muted)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget fieldFrame({Key? key, required Widget child, required bool focused, required bool empty, String? label}) =>
      Builder(
        key: key,
        builder: (context) {
          final t = ModelTheme.of(context);
          return _material(
            InputDecorator(
              isFocused: focused,
              isEmpty: empty,
              decoration: _decoration(t, label: label),
              child: child,
            ),
          );
        },
      );

  @override
  Widget statusDot({Key? key, required Color color, String? tooltip, double? size}) => Builder(
    key: key,
    builder: (context) {
      final d = size ?? ModelTheme.of(context).markerSize;
      final dot = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
      return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
    },
  );

  @override
  Widget tooltip({Key? key, required String message, required Widget child}) =>
      Tooltip(key: key, message: message, child: child);

  @override
  Future<void> showInspector(
    BuildContext context, {
    required String title,
    String subtitle = '',
    List<Widget> Function(BuildContext context)? actions,
    required WidgetBuilder body,
  }) {
    final t = ModelTheme.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialog) => ModelThemeScope(
        theme: t,
        child: Dialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius * 2)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: Padding(
              padding: EdgeInsets.all(t.spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: t.heading.copyWith(fontSize: (t.heading.fontSize ?? 15) + 3)),
                  if (subtitle.isNotEmpty) ...[SizedBox(height: t.spacing.xxs), Text(subtitle, style: t.small)],
                  SizedBox(height: t.spacing.md),
                  Flexible(child: SingleChildScrollView(child: body(dialog))),
                  SizedBox(height: t.spacing.md),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: t.spacing.xs,
                    runSpacing: t.spacing.xs,
                    children: [
                      ...?actions?.call(dialog),
                      button(
                        label: 'Close',
                        variant: ModelButtonVariant.ghost,
                        onPressed: () => Navigator.of(dialog).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final t = ModelTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => ModelThemeScope(
        theme: t,
        child: AlertDialog(
          backgroundColor: t.surface,
          title: Text(title, style: t.heading),
          content: Text(message, style: t.standard),
          actions: [
            button(
              label: 'Cancel',
              variant: ModelButtonVariant.ghost,
              onPressed: () => Navigator.of(dialog).pop(false),
            ),
            button(
              label: confirmLabel,
              variant: ModelButtonVariant.primary,
              onPressed: () => Navigator.of(dialog).pop(true),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }
}
