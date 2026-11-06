// material_chrome.dart: ModelChrome built from Material widgets, coloured
// from the nearest ModelTheme so it suits the board in light and dark.

import 'package:flutter/material.dart';

import '../theme/model_theme.dart';
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
        minimumSize: Size(0, small ? 28 : 32),
        padding: EdgeInsets.symmetric(horizontal: variant == ModelButtonVariant.link ? 4 : (small ? 10 : 12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: (small ? t.small : t.standard).copyWith(fontWeight: FontWeight.w500),
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
      return _material(
        IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: small ? 16 : t.iconSize),
          color: color ?? t.muted,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.all(small ? 4 : 6),
          constraints: BoxConstraints.tightFor(width: small ? 28 : 32, height: small ? 28 : 32),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      Builder(
        key: key,
        builder: (context) {
          final t = ModelTheme.of(context);
          return _material(
            PopupMenuButton<int>(
              tooltip: tooltip,
              icon: Icon(icon, size: t.iconSize, color: t.muted),
              color: t.surface,
              onSelected: (i) => items[i].onSelected(),
              itemBuilder: (_) => [
                for (var i = 0; i < items.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(
                      children: [
                        if (items[i].icon != null) ...[
                          Icon(items[i].icon, size: 16, color: t.muted),
                          SizedBox(width: t.spacing.xs),
                        ],
                        Flexible(
                          child: Text(items[i].label, style: t.standard, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
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
