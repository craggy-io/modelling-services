// The modeller app (design §7.7): open, edit and save block models on
// Windows and the web, with every modelling_flutter renderer.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/modeller_app.dart';
import 'src/samples.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ModellerApp(bundled: await Bundled.load(rootBundle)));
}
