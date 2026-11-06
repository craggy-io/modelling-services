// file_platform_io.dart: the desktop file half: save dialogs through
// file_selector and writes through dart:io. The only dart:io in the package.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Whether files can be written back where they were opened.
const canWriteInPlace = true;

List<String> _recents = const [];

/// Asks where to save and writes [bytes]; returns the path, or null when
/// cancelled.
Future<String?> saveBytes(
  String name,
  Uint8List bytes, {
  required String mimeType,
  required List<String> extensions,
}) async {
  final at = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: extensions.first, extensions: extensions, mimeTypes: [mimeType]),
    ],
  );
  if (at == null) return null;
  await writePath(at.path, bytes);
  return at.path;
}

/// Overwrites the file at [path].
Future<void> writePath(String path, Uint8List bytes) => File(path).writeAsBytes(bytes, flush: true);

/// Recently opened file paths, newest first (kept for the session).
List<String> readRecents() => _recents;

/// Stores the recent file paths.
void writeRecents(List<String> ids) => _recents = List.unmodifiable(ids);
