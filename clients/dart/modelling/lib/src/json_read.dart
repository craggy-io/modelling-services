// json_read.dart: decoding decoded JSON (maps and lists) into model types
// with Go encoding/json's rules: a type mismatch is an error, null leaves a
// field at its zero value, and, when strict (Go's DisallowUnknownFields), an
// unknown field is an error at every level.

import 'canonical.dart';

/// A document, profile or operation that cannot be decoded.
class ModelFormatException extends FormatException {
  const ModelFormatException(super.message);

  @override
  String toString() => 'ModelFormatException: $message';
}

/// Base of every model value type: value equality and hashing over the
/// canonical encoding of [toJson], which is how Go compares them.
abstract class JsonValue {
  const JsonValue();

  /// The JSON form, with Go's field order and omit rules.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType && jsonEquals(toJson(), (other as JsonValue).toJson()));

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;

  @override
  String toString() => '$runtimeType${canonicalJson(toJson())}';
}

/// One JSON object being read into one Go struct.
class JsonObject {
  /// Reads [value] (null reads as an empty object, as Go leaves the struct at
  /// its zero value) at [path], refusing members outside [fields] when
  /// [strict].
  JsonObject(Object? value, this.path, {required bool strict, required Set<String> fields})
      : _m = _object(value, path) {
    if (strict) {
      for (final k in _m.keys) {
        if (!fields.contains(k)) throw ModelFormatException('$path: unknown field ${goQuote(k)}');
      }
    }
  }

  final Map<String, Object?> _m;

  /// Where this object is in the document, for messages.
  final String path;

  static Map<String, Object?> _object(Object? value, String path) {
    if (value == null) return const {};
    if (value is Map) {
      return {
        for (final e in value.entries) _key(e.key, path): e.value,
      };
    }
    throw ModelFormatException('$path: want an object, got ${_kind(value)}');
  }

  /// Whether [key] is present and not null.
  bool has(String key) => _m[key] != null;

  /// The raw member [key], or null.
  Object? raw(String key) => _m[key];

  String str(String key) => readString(_m[key], '$path.$key');

  bool flag(String key) {
    final v = _m[key];
    if (v == null) return false;
    if (v is bool) return v;
    throw ModelFormatException('$path.$key: want a bool, got ${_kind(v)}');
  }

  int integer(String key) {
    final v = _m[key];
    if (v == null) return 0;
    if (v is int) return v;
    throw ModelFormatException('$path.$key: want an integer, got ${_kind(v)}');
  }

  List<String> strings(String key) => list(key, readString);

  List<T> list<T>(String key, T Function(Object? value, String path) read) {
    final v = _m[key];
    if (v == null) return const [];
    if (v is! List) throw ModelFormatException('$path.$key: want an array, got ${_kind(v)}');
    return List.unmodifiable([for (var i = 0; i < v.length; i++) read(v[i], '$path.$key[$i]')]);
  }

  /// A map member whose values are read with [read].
  Map<String, T> map<T>(String key, T Function(Object? value, String path) read) {
    final m = JsonObject(_m[key], '$path.$key', strict: false, fields: const {})._m;
    return Map.unmodifiable({for (final e in m.entries) e.key: read(e.value, '$path.$key.${e.key}')});
  }

  /// A properties member: any JSON values (validation refuses non-scalars).
  Map<String, Object?> properties(String key) => map(key, (v, _) => v);

  /// An optional object member: null when absent or null.
  T? optional<T>(String key, T Function(Object? value, String path) read) =>
      _m[key] == null ? null : read(_m[key], '$path.$key');
}

String _key(Object? key, String path) => key is String ? key : throw ModelFormatException('$path: non-string key');

/// [v] as a Go string field: null reads as "".
String readString(Object? v, String path) {
  if (v == null) return '';
  if (v is String) return v;
  throw ModelFormatException('$path: want a string, got ${_kind(v)}');
}

/// [v] as a Go float64: null reads as 0.
double readNumber(Object? v, String path) {
  if (v == null) return 0;
  if (v is num && v.isFinite) return v.toDouble();
  throw ModelFormatException('$path: want a number, got ${_kind(v)}');
}

String _kind(Object? v) => switch (v) {
      String _ => 'a string',
      num _ => 'a number',
      bool _ => 'a bool',
      List _ => 'an array',
      Map _ => 'an object',
      _ => '${v.runtimeType}',
    };
