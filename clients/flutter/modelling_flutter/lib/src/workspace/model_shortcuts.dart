// model_shortcuts.dart: what the workspace and the editor share around a
// renderer: Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z / Ctrl+S, the host's own keys
// (Ctrl+N, Ctrl+O, Ctrl+Shift+S in the modeller), how menus show a key,
// and saving through the host's hook.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:modelling/modelling.dart' hide View;

import '../controller/model_controller.dart';

/// Saves the pending operations and their result; completes when stored.
typedef ModelSaveHook = Future<void> Function(List<Op> ops, Model result);

/// Saves [c]'s pending edits through [save]; marks the controller saved
/// when the model has not moved on meanwhile, and reports a failure through
/// its notice.
Future<void> saveThrough(ModelController c, ModelSaveHook save) async {
  final ops = c.pendingOps;
  final result = c.model;
  try {
    await save(ops, result);
    if (identical(c.model, result) || c.model == result) c.markSaved();
    c.notice.value = null;
  } catch (e) {
    c.notice.value = 'Could not save: $e';
  }
}

/// The keys the editor binds, and the ones hosts bind for their file
/// commands; menus show them through [shortcutLabel].
abstract final class ModelKeys {
  static const undo = SingleActivator(LogicalKeyboardKey.keyZ, control: true);
  static const redo = SingleActivator(LogicalKeyboardKey.keyY, control: true);
  static const redoShift = SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true);
  static const save = SingleActivator(LogicalKeyboardKey.keyS, control: true);
  static const saveAs = SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true);
  static const newModel = SingleActivator(LogicalKeyboardKey.keyN, control: true);
  static const open = SingleActivator(LogicalKeyboardKey.keyO, control: true);
}

/// How a menu shows [key]: "Ctrl+Shift+S" (with Mac symbols on macOS).
String shortcutLabel(SingleActivator key, {TargetPlatform? platform}) {
  final mac = (platform ?? defaultTargetPlatform) == TargetPlatform.macOS;
  final name = key.trigger.keyLabel.length == 1 ? key.trigger.keyLabel.toUpperCase() : key.trigger.keyLabel;
  final parts = [
    if (key.control) mac ? '⌃' : 'Ctrl',
    if (key.alt) mac ? '⌥' : 'Alt',
    if (key.shift) mac ? '⇧' : 'Shift',
    if (key.meta) mac ? '⌘' : 'Meta',
    name,
  ];
  return parts.join(mac ? '' : '+');
}

/// Undo, redo and save keys for [controller] over [child], plus the host's
/// [bindings]. Undo and redo step aside while a text field has focus, so
/// the field keeps its own.
class ModelShortcuts extends StatelessWidget {
  const ModelShortcuts({
    super.key,
    required this.controller,
    required this.onSave,
    this.bindings = const {},
    required this.child,
  });

  final ModelController controller;

  /// Null when there is no save.
  final VoidCallback? onSave;

  /// The host's own keys (new, open, save as).
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final Widget keyed = Shortcuts(
      shortcuts: const {
        ModelKeys.undo: _Undo(),
        ModelKeys.redo: _Redo(),
        ModelKeys.redoShift: _Redo(),
        ModelKeys.save: _Save(),
      },
      child: Actions(
        actions: {
          _Undo: _WhenNotTyping<_Undo>(() => !c.readOnly && c.canUndo, c.undo),
          _Redo: _WhenNotTyping<_Redo>(() => !c.readOnly && c.canRedo, c.redo),
          _Save: _WhenNotTyping<_Save>(() => onSave != null && c.dirty, () => onSave?.call(), whileTyping: true),
        },
        child: child,
      ),
    );
    return bindings.isEmpty ? keyed : CallbackShortcuts(bindings: bindings, child: keyed);
  }
}

class _Undo extends Intent {
  const _Undo();
}

class _Redo extends Intent {
  const _Redo();
}

class _Save extends Intent {
  const _Save();
}

/// A shortcut action that steps aside while a text field has focus (so
/// the field keeps its own undo), unless [whileTyping].
class _WhenNotTyping<T extends Intent> extends Action<T> {
  _WhenNotTyping(this.enabled, this.run, {this.whileTyping = false});

  final bool Function() enabled;
  final VoidCallback run;
  final bool whileTyping;

  @override
  bool isEnabled(T intent) =>
      enabled() && (whileTyping || FocusManager.instance.primaryFocus?.context?.widget is! EditableText);

  @override
  Object? invoke(T intent) {
    run();
    return null;
  }
}
