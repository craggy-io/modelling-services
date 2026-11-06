// material_menu.dart: the default chrome's menus, for menuButton and menu:
// a themed panel of compact rows with leading icons, right-aligned shortcut
// hints, dividers and same-styled submenus, on Material's MenuAnchor.

import 'package:flutter/material.dart';

import '../theme/model_theme.dart';
import '../workspace/model_shortcuts.dart';
import 'model_chrome.dart';

/// The default chrome's menus: a themed panel (surface, hairline border,
/// soft shadow, the editor's radius) of compact rows with leading icons,
/// right-aligned shortcut hints, dividers and same-styled submenus.
class MaterialMenuAnchor extends StatefulWidget {
  const MaterialMenuAnchor({super.key, required this.entries, required this.trigger});

  final List<ModelMenuEntry> entries;

  /// The button that opens the menu, given the toggle.
  final Widget Function(VoidCallback toggle) trigger;

  @override
  State<MaterialMenuAnchor> createState() => _MenuAnchorState();
}

class _MenuAnchorState extends State<MaterialMenuAnchor> {
  final _menu = MenuController();

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    return MenuAnchor(
      controller: _menu,
      style: _panelStyle(t),
      alignmentOffset: const Offset(0, 4),
      menuChildren: _rows(t, widget.entries),
      child: widget.trigger(_toggle),
    );
  }
}

/// The menu panel: the theme's surface with a hairline and a shadow.
MenuStyle _panelStyle(ModelTheme t) => MenuStyle(
  backgroundColor: WidgetStatePropertyAll(t.surface),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: WidgetStatePropertyAll(t.shadow),
  elevation: const WidgetStatePropertyAll(8),
  padding: WidgetStatePropertyAll(EdgeInsets.all(t.spacing.xxs)),
  minimumSize: const WidgetStatePropertyAll(Size(220, 0)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(t.radius),
      side: BorderSide(color: t.divider, width: t.borderWidth),
    ),
  ),
);

/// One compact menu row: hover fill, the theme's text, corners concentric
/// with the panel's.
ButtonStyle _rowStyle(ModelTheme t) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
  maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 30)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: t.spacing.xs)),
  visualDensity: VisualDensity.standard,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: WidgetStatePropertyAll(t.standard),
  iconSize: const WidgetStatePropertyAll(16),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.innerRadius(t.spacing.xxs))),
  ),
  foregroundColor: WidgetStatePropertyAll(t.text),
  iconColor: WidgetStatePropertyAll(t.muted),
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) || s.contains(WidgetState.pressed)
        ? t.hover
        : Colors.transparent,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
);

List<Widget> _rows(ModelTheme t, List<ModelMenuEntry> entries) {
  // Labels line up when any row in the panel has an icon.
  final iconed = entries.any(
    (e) => switch (e) {
      ModelMenuItem i => i.icon != null,
      ModelSubmenu m => m.icon != null,
      ModelMenuDivider _ => false,
    },
  );
  Widget? lead(IconData? icon) => icon != null ? Icon(icon) : (iconed ? const SizedBox(width: 16) : null);
  final style = _rowStyle(t);
  return [
    for (final e in entries)
      switch (e) {
        ModelMenuItem i => MenuItemButton(
          key: ValueKey('menu-${i.label}'),
          style: style,
          leadingIcon: lead(i.icon),
          trailingIcon: i.shortcut == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(left: t.spacing.xl),
                  child: Text(shortcutLabel(i.shortcut!), style: t.small),
                ),
          onPressed: i.onSelected,
          child: Text(i.label),
        ),
        ModelSubmenu m => SubmenuButton(
          key: ValueKey('menu-${m.label}'),
          style: style,
          menuStyle: _panelStyle(t),
          alignmentOffset: Offset(t.spacing.xxs, 0),
          leadingIcon: lead(m.icon),
          submenuIcon: WidgetStatePropertyAll(Icon(Icons.chevron_right_rounded, size: 16, color: t.muted)),
          menuChildren: _rows(t, m.entries),
          child: Text(m.label),
        ),
        ModelMenuDivider _ => Padding(
          padding: EdgeInsets.symmetric(vertical: t.spacing.xxs),
          child: Container(height: t.borderWidth, color: t.divider),
        ),
      },
  ];
}
