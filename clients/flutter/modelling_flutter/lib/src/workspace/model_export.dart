// model_export.dart: exports from the workspace (design §7.6): Mermaid and
// outline text (copied or saved), the model document, and a PNG of the
// current renderer through its RepaintBoundary.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:modelling/modelling.dart' hide View;

import '../controller/model_controller.dart';
import '../sources/platform/file_platform.dart' as files;

/// What the export menu offers.
enum ModelExport {
  copyMermaid('Copy Mermaid'),
  copyOutline('Copy outline'),
  saveModel('Save model (.model.json)'),
  saveMermaid('Save Mermaid (.mmd)'),
  saveOutline('Save outline (.md)'),
  savePng('Save PNG');

  const ModelExport(this.label);
  final String label;
}

/// Draws what is inside the RepaintBoundary with [key] as PNG bytes.
Future<Uint8List?> captureBoundaryPng(GlobalKey key, {double pixelRatio = 2}) async {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderRepaintBoundary) return null;
  final image = await box.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Runs [what] for [c]; [stem] names saved files; [capture] is the
/// renderer's boundary for PNG. Reports the outcome through the
/// controller's notice.
Future<void> runExport(
  ModelController c,
  ModelExport what, {
  required String stem,
  required GlobalKey capture,
  double pixelRatio = 2,
}) async {
  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
  try {
    switch (what) {
      case ModelExport.copyMermaid:
        await Clipboard.setData(ClipboardData(text: toMermaid(c.model)));
        c.notice.value = 'Copied the model as Mermaid.';
      case ModelExport.copyOutline:
        await Clipboard.setData(ClipboardData(text: toOutline(c.model)));
        c.notice.value = 'Copied the model as an outline.';
      case ModelExport.saveModel:
        await _save(c, '$stem.model.json', utf8Bytes(c.model.encode()), 'application/json', ['json']);
      case ModelExport.saveMermaid:
        await _save(c, '$stem.mmd', utf8Bytes(toMermaid(c.model)), 'text/plain', ['mmd']);
      case ModelExport.saveOutline:
        await _save(c, '$stem.md', utf8Bytes(toOutline(c.model)), 'text/markdown', ['md']);
      case ModelExport.savePng:
        final png = await captureBoundaryPng(capture, pixelRatio: pixelRatio);
        if (png == null) {
          c.notice.value = 'Nothing to capture.';
          return;
        }
        await _save(c, '$stem.png', png, 'image/png', ['png']);
    }
  } on Object catch (e) {
    c.notice.value = 'Export failed: $e';
  }
}

Future<void> _save(ModelController c, String name, Uint8List bytes, String mime, List<String> extensions) async {
  final at = await files.saveBytes(name, bytes, mimeType: mime, extensions: extensions);
  if (at != null) c.notice.value = 'Saved $at.';
}

/// A file-name stem for [m]: a slug of its title.
String exportStem(Model m) {
  final s = slug(m.title);
  return s.isEmpty ? 'model' : s;
}
