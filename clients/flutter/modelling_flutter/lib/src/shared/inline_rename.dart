// inline_rename.dart: the text field that replaces a label while renaming
// in place: Enter or leaving the field commits, Escape cancels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chrome/model_chrome.dart';
import '../controller/model_controller.dart';
import '../controller/model_editing.dart';
import '../controller/model_types.dart';

class InlineRenameField extends StatefulWidget {
  const InlineRenameField({super.key, required this.controller, required this.onCommit, required this.onCancel});

  final TextEditingController controller;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  final _focus = FocusNode(debugLabel: 'rename');

  @override
  void initState() {
    super.initState();
    // Takes focus explicitly: autofocus is ignored while the renderer
    // (or the button that started the rename) still holds it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (has) {
      if (!has) widget.onCommit();
    },
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ModelChrome.of(context).textField(
      key: const ValueKey('rename-field'),
      controller: widget.controller,
      focusNode: _focus,
      dense: true,
      onSubmitted: (_) => widget.onCommit(),
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

  ModelController? _requests;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  // Follows controller.renameRequest, re-subscribing when the widget's
  // controller changes.
  void _listen() {
    if (identical(_requests, controller)) return;
    _requests?.renameRequest.removeListener(_onRenameRequest);
    _requests = controller..renameRequest.addListener(_onRenameRequest);
    _onRenameRequest();
  }

  // Starts renaming once the requested area has been built.
  void _onRenameRequest() {
    final id = controller.renameRequest.value;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.renameRequest.value != id) return;
      controller.renameRequest.value = null;
      startRename(id);
    });
  }

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
    _requests?.renameRequest.removeListener(_onRenameRequest);
    renameText.dispose();
    super.dispose();
  }
}
