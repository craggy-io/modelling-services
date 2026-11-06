// inline_rename.dart: the text field that replaces a label while renaming
// in place: Enter or leaving the field commits, Escape cancels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';

class InlineRenameField extends StatelessWidget {
  const InlineRenameField({super.key, required this.controller, required this.onCommit, required this.onCancel});

  final TextEditingController controller;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (has) {
      if (!has) onCommit();
    },
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ModelChrome.of(context).textField(
      key: const ValueKey('rename-field'),
      controller: controller,
      autofocus: true,
      dense: true,
      onSubmitted: (_) => onCommit(),
    ),
  );
}

/// Rename-in-place state for a renderer: which area is being renamed and
/// its text; committing runs a rename op. [renameDone] returns focus to the
/// renderer.
mixin InlineRenameState<T extends StatefulWidget> on State<T> {
  ModelController get controller;

  /// Where keyboard focus goes back after renaming.
  FocusNode get renameReturnFocus;

  final renameText = TextEditingController();
  String? _renaming;

  String? get renaming => _renaming;

  void startRename(String id) {
    final n = controller.index.node(id);
    if (n == null || controller.readOnly) return;
    controller.focus(id);
    setState(() {
      _renaming = id;
      renameText.text = n.label;
      renameText.selection = TextSelection(baseOffset: 0, extentOffset: n.label.length);
    });
  }

  void commitRename() {
    final id = _renaming;
    if (id == null) return;
    final n = controller.index.node(id);
    if (n != null && renameText.text.trim() != n.label) controller.rename(ModelElementRef.node(id), renameText.text);
    _end();
  }

  void cancelRename() => _end();

  void _end() {
    if (!mounted || _renaming == null) return;
    setState(() => _renaming = null);
    renameReturnFocus.requestFocus();
  }

  @override
  void dispose() {
    renameText.dispose();
    super.dispose();
  }
}
