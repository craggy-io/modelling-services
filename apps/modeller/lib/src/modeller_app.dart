// modeller_app.dart: the MaterialApp with light and dark themes, over the
// bundled templates and profiles.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'modeller_home.dart';
import 'samples.dart';

class ModellerApp extends StatelessWidget {
  const ModellerApp({super.key, required this.bundled});

  final Bundled bundled;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Modeller',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true, colorSchemeSeed: const Color(0xFFD9700F)),
    darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorSchemeSeed: const Color(0xFFFF9A3C)),
    builder: (context, child) =>
        ModelThemeScope(theme: ModelTheme.fallback(Theme.of(context).brightness), child: child!),
    home: ModellerHome(bundled: bundled),
  );
}
