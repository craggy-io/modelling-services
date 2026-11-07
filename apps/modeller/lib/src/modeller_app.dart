// modeller_app.dart: the MaterialApp with light and dark themes, over the
// bundled templates and profiles, opening the model in [ModellerApp.linked],
// inside the page's [ModellerApp.host], if any.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'host.dart';
import 'model_link.dart';
import 'modeller_home.dart';
import 'samples.dart';

class ModellerApp extends StatelessWidget {
  const ModellerApp({super.key, required this.bundled, this.linked = (model: null, error: null), this.host});

  final Bundled bundled;

  /// The model linked in the page address; see [ModellerHome.linked].
  final LinkedModel linked;

  /// The page hosting the app; see [ModellerHome.host].
  final ModellingHost? host;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Modelling · Craggy',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true, colorSchemeSeed: const Color(0xFFD9700F)),
    darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorSchemeSeed: const Color(0xFFFF9A3C)),
    builder: (context, child) =>
        ModelThemeScope(theme: ModelTheme.fallback(Theme.of(context).brightness), child: child!),
    home: ModellerHome(bundled: bundled, linked: linked, host: host),
  );
}
