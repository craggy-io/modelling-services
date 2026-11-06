// page_fragment_web.dart: the browser's address bar, and the browser's own
// inflater.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The page address's fragment, without the `#`.
String pageFragment() => Uri.base.fragment;

/// Drops the fragment from the address bar without reloading, so a reload
/// does not open the linked model again over the user's edits.
void clearPageFragment() => web.window.history.replaceState(null, '', Uri.base.removeFragment().toString());

/// [data] inflated from raw DEFLATE (no zlib header) by the browser's
/// DecompressionStream.
Future<Uint8List> inflateRaw(Uint8List data) async {
  final inflater = web.DecompressionStream('deflate-raw');
  final stream = web.Blob(
    <web.BlobPart>[data.toJS].toJS,
  ).stream().pipeThrough(web.ReadableWritablePair(readable: inflater.readable, writable: inflater.writable));
  final bytes = await web.Response(stream).arrayBuffer().toDart;
  return bytes.toDart.asUint8List();
}
