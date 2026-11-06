// file_platform_web.dart: the browser file half: saving downloads through
// an anchor, and recents live in window.localStorage.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Whether files can be written back where they were opened.
const canWriteInPlace = false;

const _recentsKey = 'modelling_flutter.recents';

/// Downloads [bytes] as [name]; returns the name.
Future<String?> saveBytes(
  String name,
  Uint8List bytes, {
  required String mimeType,
  required List<String> extensions,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return name;
}

/// Browsers cannot write a file in place.
Future<void> writePath(String path, Uint8List bytes) =>
    throw UnsupportedError('Browsers cannot write files in place; save downloads a copy');

/// Recently opened file names, newest first.
List<String> readRecents() {
  final raw = web.window.localStorage.getItem(_recentsKey);
  if (raw == null) return const [];
  try {
    return [for (final x in jsonDecode(raw) as List<Object?>) '$x'];
  } on FormatException {
    return const [];
  }
}

/// Stores the recent file names.
void writeRecents(List<String> ids) => web.window.localStorage.setItem(_recentsKey, jsonEncode(ids));
