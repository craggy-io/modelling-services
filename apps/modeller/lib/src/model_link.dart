// model_link.dart: models carried in the page address, as the modelling
// MCP server's open links write them (Go modelcap.Link): the canonical
// document, raw-deflated and base64url-encoded without padding, in the "m"
// fragment parameter.

import 'dart:convert';

import 'package:modelling/modelling.dart' hide View;

import 'platform/page_fragment.dart';

export 'platform/page_fragment.dart';

/// The model in [fragment]'s `m` parameter (a leading `#` and other
/// `&`-separated parameters are allowed), decoded and validated like any
/// opened document; null when there is no `m`. Throws [FormatException]
/// when the data is corrupt.
Future<Model?> decodeModelFragment(String fragment) async {
  final data = Uri.splitQueryString(fragment.startsWith('#') ? fragment.substring(1) : fragment)['m'];
  if (data == null) return null;
  try {
    final raw = await inflateRaw(base64Url.decode(base64Url.normalize(data)));
    return Model.decode(utf8.decode(raw))..validate();
  } on Object catch (e) {
    throw FormatException('the linked model is corrupt ($e)');
  }
}

/// What the page address linked: a model, or why it could not open.
typedef LinkedModel = ({Model? model, String? error});

/// Reads the model linked in [fragment] (the page address's), then drops the link from
/// the address so a reload keeps the user's edits.
Future<LinkedModel> readLinkedModel(String fragment) async {
  try {
    final model = await decodeModelFragment(fragment);
    if (model != null) clearPageFragment();
    return (model: model, error: null);
  } on FormatException catch (e) {
    clearPageFragment();
    return (model: null, error: 'Could not open the linked model: ${e.message}');
  }
}
