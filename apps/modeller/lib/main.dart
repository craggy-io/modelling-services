// The modeller app (design §7.7): open, edit and save block models on
// Windows and the web, with every modelling_flutter renderer. On the web a
// model linked in the address (`#m=...`) opens at start.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/model_link.dart';
import 'src/modeller_app.dart';
import 'src/samples.dart';

Future<void> main() async {
  // Read the link before Flutter starts: its URL strategy rewrites the fragment.
  final link = pageFragment();
  WidgetsFlutterBinding.ensureInitialized();
  final linked = await readLinkedModel(link);
  runApp(ModellerApp(bundled: await Bundled.load(rootBundle), linked: linked));
}
