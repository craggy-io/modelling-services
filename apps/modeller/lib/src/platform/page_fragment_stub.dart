// page_fragment_stub.dart: desktop has no page address; inflating uses
// dart:io (also what the VM tests run).

import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// The page address's fragment, without the `#`; empty off the web.
String pageFragment() => '';

/// Drops the fragment from the address bar without reloading.
void clearPageFragment() {}

/// [data] inflated from raw DEFLATE (no zlib header).
Future<Uint8List> inflateRaw(Uint8List data) async => Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
