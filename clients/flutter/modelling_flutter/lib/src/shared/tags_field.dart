// tags_field.dart: a tags input. Tags show as removable chips before the
// text; Enter or a comma turns the typed text into a tag, Backspace in an
// empty input removes the last one, duplicates are ignored, and leaving
// the field keeps what was typed. Every change goes out as the whole new
// list, so the caller commits it as one undoable edit.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chrome/model_chrome.dart';
import '../theme/model_theme.dart';

/// [tags] with [typed] added: each comma-separated piece trimmed, blanks
/// and duplicates dropped, order kept.
List<String> addTags(List<String> tags, String typed) => {
  ...tags,
  for (final piece in typed.split(','))
    if (piece.trim().isNotEmpty) piece.trim(),
}.toList();

/// Edits a list of tags as chips; [onChanged] gets each new list.
class TagsField extends StatefulWidget {
  const TagsField({
    super.key,
    required this.tags,
    required this.onChanged,
    this.label,
    this.hint = 'Add a tag',
    this.dense = false,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String? label;
  final String hint;

  /// Smaller, for a table cell.
  final bool dense;

  @override
  State<TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<TagsField> {
  final _text = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _key)..addListener(_focusChanged);

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(List<String> next) {
    if (next.length != widget.tags.length || !next.indexed.every((e) => widget.tags[e.$1] == e.$2)) {
      widget.onChanged(next);
    }
  }

  /// Turns the typed text into tags and clears the input.
  void _commit() {
    if (_text.text.trim().isEmpty) {
      _text.clear();
      return;
    }
    final next = addTags(widget.tags, _text.text);
    _text.clear();
    _set(next);
  }

  void _remove(String tag) => _set([
    for (final t in widget.tags)
      if (t != tag) t,
  ]);

  void _focusChanged() {
    if (!mounted) return;
    if (!_focus.hasFocus) _commit();
    setState(() {});
  }

  void _typed(String text) {
    final cut = text.lastIndexOf(',');
    if (cut < 0) return;
    final next = addTags(widget.tags, text.substring(0, cut));
    _text.value = TextEditingValue(
      text: text.substring(cut + 1).trimLeft(),
      selection: TextSelection.collapsed(offset: text.substring(cut + 1).trimLeft().length),
    );
    _set(next);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _text.text.isEmpty &&
        widget.tags.isNotEmpty) {
      _remove(widget.tags.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final gap = widget.dense ? t.spacing.xxs : t.spacing.xxs + 2;
    final input = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 64),
      child: IntrinsicWidth(
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            key: const ValueKey('tags-input'),
            controller: _text,
            focusNode: _focus,
            style: (widget.dense ? t.small.copyWith(color: t.text) : t.standard),
            textInputAction: TextInputAction.done,
            onChanged: _typed,
            onSubmitted: (_) => _commit(),
            // Enter adds the tag and keeps typing in the field.
            onEditingComplete: () {},
            decoration: InputDecoration.collapsed(
              hintText: widget.tags.isEmpty || _focus.hasFocus ? widget.hint : null,
              hintStyle: t.small,
            ),
          ),
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focus.requestFocus,
      child: chrome.fieldFrame(
        label: widget.label,
        focused: _focus.hasFocus,
        empty: false,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in widget.tags)
              chrome.tagChip(key: ValueKey('tag-$tag'), label: tag, onRemove: () => _remove(tag)),
            input,
          ],
        ),
      ),
    );
  }
}
