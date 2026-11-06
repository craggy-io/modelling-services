// field_editors.dart: inspector editors that commit through operations as
// the user types (consecutive label edits merge into one undo step), and
// typed property editors driven by the profile.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';
import '../theme/model_theme.dart';

/// Returns an error to show, or null when the value was committed.
typedef CommitValue = String? Function(String value);

/// A text field that commits each change and follows outside changes
/// (undo, a new revision) while it is not being edited.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.value,
    required this.onCommit,
    this.label,
    this.hint,
    this.multiline = false,
  });

  final String value;
  final CommitValue onCommit;
  final String? label;
  final String? hint;
  final bool multiline;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  String? _error;

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModelChrome.of(context).textField(
    controller: _text,
    focusNode: _focus,
    label: widget.label,
    hint: widget.hint,
    error: _error,
    multiline: widget.multiline,
    onChanged: (v) {
      final error = widget.onCommit(v);
      if (error != _error) setState(() => _error = error);
    },
  );
}

/// Tags as a comma-separated list.
List<String> parseTags(String text) => {
  for (final t in text.split(','))
    if (t.trim().isNotEmpty) t.trim(),
}.toList();

/// Shows a property value as text.
String propertyText(Object? v) => switch (v) {
  null => '',
  double d when d == d.truncateToDouble() && d.abs() < 1e15 => d.toInt().toString(),
  _ => '$v',
};

/// Reads typed text as a value of [type] ('string', 'number', 'bool');
/// without a type it keeps the [previous] value's type, and a new value
/// that reads as a number or true/false becomes one.
Object? parseProperty(String text, {String? type, Object? previous}) {
  final t =
      type ??
      switch (previous) {
        num _ => 'number',
        bool _ => 'bool',
        String _ => 'string',
        _ =>
          num.tryParse(text.trim()) != null
              ? 'number'
              : (text.trim() == 'true' || text.trim() == 'false')
              ? 'bool'
              : 'string',
      };
  return switch (t) {
    'number' => num.tryParse(text.trim()),
    'bool' => switch (text.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    },
    _ => text,
  };
}

/// The property specs for an element's kind under the controller's profile.
Map<String, PropertySpec> propertySpecs(ModelController c, ModelElementRef ref, String kind) {
  final p = c.profile;
  if (p == null) return const {};
  return (ref.isNode ? p.nodeKinds[kind]?.properties : p.edgeKinds[kind]?.properties) ?? const {};
}

/// Every property of an element, with typed editors for the ones its
/// profile kind declares and an "Add property" row.
class PropertiesEditor extends StatelessWidget {
  const PropertiesEditor({
    super.key,
    required this.controller,
    required this.element,
    required this.kind,
    required this.properties,
  });

  final ModelController controller;
  final ModelElementRef element;
  final String kind;
  final Properties properties;

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final specs = propertySpecs(controller, element, kind);
    final keys = [
      ...(specs.keys.toList()..sort()),
      ...(properties.keys.where((k) => !specs.containsKey(k)).toList()..sort()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in keys)
          Padding(
            padding: EdgeInsets.only(bottom: t.spacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: propertyEditor(
                    chrome,
                    controller,
                    element,
                    k,
                    specs[k],
                    properties[k],
                    label: specs[k] == null || specs[k]!.label.isEmpty ? k : '${specs[k]!.label} ($k)',
                  ),
                ),
                if (properties.containsKey(k))
                  chrome.iconButton(
                    icon: Icons.close,
                    tooltip: 'Remove $k',
                    onPressed: () => controller.setProperty(element, k, null),
                  ),
              ],
            ),
          ),
        _AddProperty(onAdd: (key, value) => controller.setProperty(element, key, parseProperty(value))),
      ],
    );
  }
}

/// An editor for property [key] of [element] (currently [have]): a choice
/// for enums and bools, else a field that commits typed values as [spec]
/// (or the current value) says.
Widget propertyEditor(
  ModelChrome chrome,
  ModelController controller,
  ModelElementRef element,
  String key,
  PropertySpec? spec,
  Object? have, {
  String? label,
}) {
  final choices = spec == null
      ? null
      : spec.enumValues.isNotEmpty
      ? spec.enumValues
      : spec.type == 'bool'
      ? const [true, false]
      : null;
  if (choices != null || have is bool) {
    return chrome.select<Object?>(
      key: ValueKey('prop-$key'),
      label: label,
      value: have,
      options: [
        const ModelOption<Object?>(null, '(not set)'),
        for (final v in choices ?? const [true, false]) ModelOption<Object?>(v, propertyText(v)),
      ],
      onChanged: (v) => controller.setProperty(element, key, v),
    );
  }
  return CommitField(
    key: ValueKey('prop-$key'),
    label: label,
    value: propertyText(have),
    onCommit: (text) {
      if (text.isEmpty) {
        controller.setProperty(element, key, null);
        return null;
      }
      final v = parseProperty(text, type: spec?.type, previous: have);
      if (v == null) return 'Enter a ${spec?.type ?? (have is bool ? 'bool' : 'number')}';
      return controller.setProperty(element, key, v) ? null : controller.notice.value;
    },
  );
}

class _AddProperty extends StatefulWidget {
  const _AddProperty({required this.onAdd});

  final bool Function(String key, String value) onAdd;

  @override
  State<_AddProperty> createState() => _AddPropertyState();
}

class _AddPropertyState extends State<_AddProperty> {
  final _key = TextEditingController();
  final _value = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _add() {
    if (_key.text.trim().isEmpty) return;
    if (widget.onAdd(_key.text.trim(), _value.text)) {
      _key.clear();
      _value.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    return Row(
      children: [
        Expanded(
          child: chrome.textField(key: const ValueKey('new-property-key'), controller: _key, hint: 'New property'),
        ),
        SizedBox(width: t.spacing.xs),
        Expanded(
          child: chrome.textField(
            key: const ValueKey('new-property-value'),
            controller: _value,
            hint: 'Value',
            onSubmitted: (_) => _add(),
          ),
        ),
        chrome.iconButton(icon: Icons.add, tooltip: 'Add property', onPressed: _add),
      ],
    );
  }
}
