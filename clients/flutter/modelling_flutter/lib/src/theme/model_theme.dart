// model_theme.dart: every token the renderers draw with (design §7.4). Hosts
// build one from their own design system (labs maps its ModelSpec and theme
// colours); ModelTheme.fallback makes the package work with no host.

import 'package:flutter/widgets.dart';

/// The spacing scale renderers use between pieces (theme.md §3.1).
@immutable
class ModelSpacing {
  const ModelSpacing({this.xxs = 4, this.xs = 8, this.sm = 12, this.md = 16, this.lg = 20, this.xl = 24});

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
}

/// Scales a motion duration for the host's reduced-motion setting.
typedef ModelMotion = Duration Function(BuildContext context, Duration duration);

/// Zero when the platform asks for reduced motion, else [duration].
Duration reducedMotion(BuildContext context, Duration duration) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : duration;

/// The tokens every renderer, the inspector and the workspace draw with.
/// Renderers never hard-code colours or sizes; they read this.
@immutable
class ModelTheme {
  const ModelTheme({
    required this.areaBackground,
    required this.areaBackgroundDeep,
    this.depthStep = 0.16,
    this.depthMax = 0.64,
    required this.border,
    this.borderWidth = 1,
    required this.selectedBorder,
    this.selectedBorderWidth = 2,
    this.radius = 10,
    this.rootPadding = 20,
    this.padding = 16,
    this.gap = 12,
    required this.labelBackground,
    this.minAreaWidth = 280,
    this.maxColumns = 2,
    this.dotSize = 16,
    this.maxDots = 4,
    this.connectorWidth = 2,
    this.arrowSize = 10,
    this.pageSize = 40,
    this.openDepth = 2,
    this.iconSize = 20,
    this.markerSize = 8,
    this.indent = 20,
    required this.heading,
    required this.standard,
    required this.small,
    required this.overline,
    this.spacing = const ModelSpacing(),
    required this.palette,
    required this.text,
    required this.surface,
    required this.raised,
    required this.hover,
    required this.muted,
    required this.focus,
    required this.added,
    required this.changed,
    required this.removed,
    required this.lintError,
    required this.lintWarning,
    required this.lintInfo,
    this.motionStandard = const Duration(milliseconds: 200),
    this.motion = reducedMotion,
  });

  /// A theme that reads well on its own in light or dark mode. The dark
  /// one matches craggy-labs' theme.yaml (theme.md §3.4, §5.17).
  factory ModelTheme.fallback([Brightness brightness = Brightness.dark]) {
    final dark = brightness == Brightness.dark;
    final text = dark ? const Color(0xFFECECEF) : const Color(0xFF1D1D20);
    final muted = dark ? const Color(0xFFA0A0AA) : const Color(0xFF5E5E68);
    const family = 'Segoe UI';
    return ModelTheme(
      areaBackground: dark ? const Color(0xFF1B2938) : const Color(0xFFF1F5F9),
      areaBackgroundDeep: dark ? const Color(0xFF42566B) : const Color(0xFFC3D2E0),
      border: dark ? const Color(0xFF4A6279) : const Color(0xFF94A9BD),
      selectedBorder: dark ? const Color(0xFFFF9A3C) : const Color(0xFFD9700F),
      labelBackground: dark ? const Color(0x331D1D20) : const Color(0x99FFFFFF),
      heading: TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w600, color: text, height: 1.3),
      standard: TextStyle(fontFamily: family, fontSize: 14, color: text, height: 1.4),
      small: TextStyle(fontFamily: family, fontSize: 12, color: muted, height: 1.35),
      overline: TextStyle(
        fontFamily: family,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: muted,
        height: 1.3,
      ),
      palette: dark
          ? const [
              Color(0xFFFF9A3C),
              Color(0xFF5AA9FF),
              Color(0xFFB57BFF),
              Color(0xFF3DDC97),
              Color(0xFFFF6FA8),
              Color(0xFFFFC857),
            ]
          : const [
              Color(0xFFD9700F),
              Color(0xFF1F78D1),
              Color(0xFF8A4FD6),
              Color(0xFF15965F),
              Color(0xFFD13F7A),
              Color(0xFFB98A00),
            ],
      text: text,
      surface: dark ? const Color(0xFF262628) : const Color(0xFFFFFFFF),
      raised: dark ? const Color(0xFF2E2E31) : const Color(0xFFF2F2F5),
      hover: dark ? const Color(0xFF36363A) : const Color(0xFFE6E6EB),
      muted: muted,
      focus: dark ? const Color(0xFFFF9A3C) : const Color(0xFFD9700F),
      added: dark ? const Color(0xFF3DDC97) : const Color(0xFF15965F),
      changed: dark ? const Color(0xFF5AA9FF) : const Color(0xFF1F78D1),
      removed: dark ? const Color(0xFFFF6B6B) : const Color(0xFFC93C3C),
      lintError: dark ? const Color(0xFFFF6B6B) : const Color(0xFFC93C3C),
      lintWarning: dark ? const Color(0xFFFFC857) : const Color(0xFFB98A00),
      lintInfo: dark ? const Color(0xFF5AA9FF) : const Color(0xFF1F78D1),
    );
  }

  /// The nearest [ModelThemeScope]'s theme, else the fallback for the
  /// platform brightness.
  static ModelTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModelThemeScope>()?.theme ??
      ModelTheme.fallback(MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark);

  /// Root area fill; nested areas move toward [areaBackgroundDeep] by
  /// [depthStep] per level, capped at [depthMax].
  final Color areaBackground;
  final Color areaBackgroundDeep;
  final double depthStep;
  final double depthMax;
  final Color border;
  final double borderWidth;
  final Color selectedBorder;
  final double selectedBorderWidth;
  final double radius;
  final double rootPadding;
  final double padding;
  final double gap;

  /// Fill of an area's label chip.
  final Color labelBackground;
  final double minAreaWidth;
  final int maxColumns;
  final double dotSize;

  /// Relationship circles listed per area before the count link.
  final int maxDots;
  final double connectorWidth;
  final double arrowSize;

  /// Areas drawn before "Show more areas".
  final int pageSize;

  /// Areas nested deeper than this start collapsed.
  final int openDepth;
  final double iconSize;

  /// Change, lint and status dots.
  final double markerSize;

  /// Outline indent per level.
  final double indent;

  final TextStyle heading;
  final TextStyle standard;
  final TextStyle small;
  final TextStyle overline;
  final ModelSpacing spacing;

  /// Categorical colours for relationships, applied in order.
  final List<Color> palette;
  final Color text;
  final Color surface;
  final Color raised;
  final Color hover;
  final Color muted;
  final Color focus;
  final Color added;
  final Color changed;
  final Color removed;
  final Color lintError;
  final Color lintWarning;
  final Color lintInfo;

  /// The standard transition length, before [motion] scales it.
  final Duration motionStandard;

  /// Scales durations for reduced motion (labs passes `craggyDuration`).
  final ModelMotion motion;

  /// Fill for an area [depth] levels below the root.
  Color areaAt(int depth) =>
      Color.lerp(areaBackground, areaBackgroundDeep, (depth * depthStep).clamp(0, depthMax).toDouble())!;

  /// The palette colour at [index], wrapping.
  Color paletteAt(int index) => palette.isEmpty ? selectedBorder : palette[index % palette.length];

  /// [motionStandard] after the reduced-motion hook.
  Duration standardDuration(BuildContext context) => motion(context, motionStandard);

  ModelTheme copyWith({
    Color? areaBackground,
    Color? areaBackgroundDeep,
    double? depthStep,
    double? depthMax,
    Color? border,
    double? borderWidth,
    Color? selectedBorder,
    double? selectedBorderWidth,
    double? radius,
    double? rootPadding,
    double? padding,
    double? gap,
    Color? labelBackground,
    double? minAreaWidth,
    int? maxColumns,
    double? dotSize,
    int? maxDots,
    double? connectorWidth,
    double? arrowSize,
    int? pageSize,
    int? openDepth,
    double? iconSize,
    double? markerSize,
    double? indent,
    TextStyle? heading,
    TextStyle? standard,
    TextStyle? small,
    TextStyle? overline,
    ModelSpacing? spacing,
    List<Color>? palette,
    Color? text,
    Color? surface,
    Color? raised,
    Color? hover,
    Color? muted,
    Color? focus,
    Color? added,
    Color? changed,
    Color? removed,
    Color? lintError,
    Color? lintWarning,
    Color? lintInfo,
    Duration? motionStandard,
    ModelMotion? motion,
  }) => ModelTheme(
    areaBackground: areaBackground ?? this.areaBackground,
    areaBackgroundDeep: areaBackgroundDeep ?? this.areaBackgroundDeep,
    depthStep: depthStep ?? this.depthStep,
    depthMax: depthMax ?? this.depthMax,
    border: border ?? this.border,
    borderWidth: borderWidth ?? this.borderWidth,
    selectedBorder: selectedBorder ?? this.selectedBorder,
    selectedBorderWidth: selectedBorderWidth ?? this.selectedBorderWidth,
    radius: radius ?? this.radius,
    rootPadding: rootPadding ?? this.rootPadding,
    padding: padding ?? this.padding,
    gap: gap ?? this.gap,
    labelBackground: labelBackground ?? this.labelBackground,
    minAreaWidth: minAreaWidth ?? this.minAreaWidth,
    maxColumns: maxColumns ?? this.maxColumns,
    dotSize: dotSize ?? this.dotSize,
    maxDots: maxDots ?? this.maxDots,
    connectorWidth: connectorWidth ?? this.connectorWidth,
    arrowSize: arrowSize ?? this.arrowSize,
    pageSize: pageSize ?? this.pageSize,
    openDepth: openDepth ?? this.openDepth,
    iconSize: iconSize ?? this.iconSize,
    markerSize: markerSize ?? this.markerSize,
    indent: indent ?? this.indent,
    heading: heading ?? this.heading,
    standard: standard ?? this.standard,
    small: small ?? this.small,
    overline: overline ?? this.overline,
    spacing: spacing ?? this.spacing,
    palette: palette ?? this.palette,
    text: text ?? this.text,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    hover: hover ?? this.hover,
    muted: muted ?? this.muted,
    focus: focus ?? this.focus,
    added: added ?? this.added,
    changed: changed ?? this.changed,
    removed: removed ?? this.removed,
    lintError: lintError ?? this.lintError,
    lintWarning: lintWarning ?? this.lintWarning,
    lintInfo: lintInfo ?? this.lintInfo,
    motionStandard: motionStandard ?? this.motionStandard,
    motion: motion ?? this.motion,
  );
}

/// Provides a [ModelTheme] to the renderers below it.
class ModelThemeScope extends InheritedWidget {
  const ModelThemeScope({super.key, required this.theme, required super.child});

  final ModelTheme theme;

  @override
  bool updateShouldNotify(ModelThemeScope oldWidget) => !identical(theme, oldWidget.theme);
}
