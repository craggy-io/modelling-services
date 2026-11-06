// file_platform_stub.dart: the file half for platforms with neither
// dart:io nor the browser. Everything is unsupported.

import 'dart:typed_data';

/// Whether files can be written back where they were opened.
const canWriteInPlace = false;

/// Asks where to save and writes [bytes]; returns the path or name, or null
/// when cancelled.
Future<String?> saveBytes(String name, Uint8List bytes, {required String mimeType, required List<String> extensions}) =>
    throw UnsupportedError('Saving files is not supported on this platform');

/// Overwrites the file at [path].
Future<void> writePath(String path, Uint8List bytes) =>
    throw UnsupportedError('Writing files is not supported on this platform');

/// Recently opened file ids, newest first.
List<String> readRecents() => const [];

/// Stores the recent file ids.
void writeRecents(List<String> ids) {}
