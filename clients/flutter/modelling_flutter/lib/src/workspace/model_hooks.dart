// model_hooks.dart: the host callbacks (design §7.5) made available to
// renderers and the inspector, and a helper that carries the scopes into
// dialogs (which are built under the Navigator, outside the workspace).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:modelling/modelling.dart' hide View;

import '../chrome/model_chrome.dart';
import '../controller/model_types.dart';
import '../theme/model_theme.dart';

/// Opens a cited thing (an artifact, URL or file).
typedef ModelEvidenceHook = void Function(Ref ref);

/// Lets the user pick things to cite on an element; the host adds them
/// (for example with `controller.attachEvidence`).
typedef ModelAttachHook = FutureOr<void> Function(ModelElementRef element);

/// Opens the model a node links to.
typedef ModelLinkHook = void Function(Link link);

/// Shows an element in a docked inspector instead of a dialog.
typedef ModelInspectHook = void Function(ModelElementRef element);

/// The host callbacks renderers and the inspector call. A null hook hides
/// its action.
@immutable
class ModelHooks {
  const ModelHooks({
    this.onEvidence,
    this.onAttachEvidence,
    this.onOpenLink,
    this.onInspect,
    this.openLabel = 'Open',
    this.captureKey,
  });

  final ModelEvidenceHook? onEvidence;
  final ModelAttachHook? onAttachEvidence;
  final ModelLinkHook? onOpenLink;

  /// When set, inspecting selects the element and calls this (the editor's
  /// docked inspector) rather than opening a dialog.
  final ModelInspectHook? onInspect;

  /// The label of the inspector's open-link action.
  final String openLabel;

  /// Renderers put their whole drawing in a RepaintBoundary with this key
  /// so PNG export captures all of it, not just the visible part.
  final GlobalKey? captureKey;

  /// The nearest [ModelHooksScope]'s hooks, else none.
  static ModelHooks of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModelHooksScope>()?.hooks ?? const ModelHooks();
}

/// Provides [ModelHooks] to the renderers below it.
class ModelHooksScope extends InheritedWidget {
  const ModelHooksScope({super.key, required this.hooks, required super.child});

  final ModelHooks hooks;

  @override
  bool updateShouldNotify(ModelHooksScope oldWidget) => !identical(hooks, oldWidget.hooks);
}

/// Captures the theme, chrome and hooks at [context] and returns a
/// function that provides them again (for dialog contents).
Widget Function(Widget child) captureModelScopes(BuildContext context) {
  final theme = ModelTheme.of(context), chrome = ModelChrome.of(context), hooks = ModelHooks.of(context);
  return (child) => ModelThemeScope(
    theme: theme,
    child: ModelChromeScope(
      chrome: chrome,
      child: ModelHooksScope(hooks: hooks, child: child),
    ),
  );
}
