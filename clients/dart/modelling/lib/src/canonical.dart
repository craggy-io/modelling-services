// canonical.dart: the canonical JSON form (foundation-kit canonjson) and the
// few Go standard-library text behaviours the ports rely on, so Dart output
// is byte-identical to Go's.

/// Encodes a JSON value (null, bool, num, String, List, Map with String keys)
/// as canonical JSON, byte-identical to Go's `canonjson.Marshal`: compact,
/// object keys sorted bytewise by UTF-8, numbers as exact decimals with no
/// exponent and no trailing fractional zeros, strings escaped as Go's
/// encoding/json escapes them.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

/// Whether [a] and [b] have the same canonical JSON encoding.
bool jsonEquals(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);

void _write(StringBuffer out, Object? v) {
  switch (v) {
    case null:
      out.write('null');
    case bool b:
      out.write(b ? 'true' : 'false');
    case num n:
      out.write(formatNumber(n));
    case String s:
      writeJsonString(out, s);
    case List<Object?> list:
      out.write('[');
      for (var i = 0; i < list.length; i++) {
        if (i > 0) out.write(',');
        _write(out, list[i]);
      }
      out.write(']');
    case Map<Object?, Object?> map:
      final sorted = [for (final k in map.keys) k is String ? k : throw ArgumentError('JSON key $k is not a string')]
        ..sort(compareUtf8);
      out.write('{');
      for (var i = 0; i < sorted.length; i++) {
        if (i > 0) out.write(',');
        writeJsonString(out, sorted[i]);
        out.write(':');
        _write(out, map[sorted[i]]);
      }
      out.write('}');
    case (num, num) p:
      out.write('[${formatNumber(p.$1)},${formatNumber(p.$2)}]');
    default:
      throw ArgumentError('${v.runtimeType} is not a JSON value');
  }
}

const _maxExactInt = 9007199254740992; // 2^53

/// The canonical decimal for [n]. Numbers are float64 in Go, so an int beyond
/// 2^53 is first rounded to a double, as Go would have it.
String formatNumber(num n) {
  if (n is int && n.abs() <= _maxExactInt) return n.toString();
  final d = n.toDouble();
  if (!d.isFinite) throw ArgumentError('$n is not a JSON number');
  if (d == 0) return '0';
  final (digits, point) = _shortestDigits(d);
  final sign = d < 0 ? '-' : '';
  if (point <= 0) return '${sign}0.${'0' * -point}$digits';
  if (point >= digits.length) return '$sign$digits${'0' * (point - digits.length)}';
  return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
}

/// The shortest round-trip decimal digits of |d| (no leading or trailing
/// zeros) and the decimal point's position: value = 0.digits × 10^point.
(String, int) _shortestDigits(double d) {
  var s = d.abs().toString();
  var exp = 0;
  final e = s.indexOf('e');
  if (e >= 0) {
    exp = int.parse(s.substring(e + 1));
    s = s.substring(0, e);
  }
  final dot = s.indexOf('.');
  var point = (dot < 0 ? s.length : dot) + exp;
  var digits = s.replaceFirst('.', '');
  var lead = 0;
  while (lead < digits.length - 1 && digits.codeUnitAt(lead) == 0x30) {
    lead++;
  }
  digits = digits.substring(lead);
  point -= lead;
  var end = digits.length;
  while (end > 1 && digits.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  return (digits.substring(0, end), point);
}

/// [d] as Go's `fmt.Sprint` prints a float64 (`%g` with the shortest
/// precision: an exponent below -4 or at 6 and above uses `e±XX` form).
String goFormatFloat(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? '+Inf' : '-Inf';
  if (d == 0) return d.isNegative ? '-0' : '0';
  final (digits, point) = _shortestDigits(d);
  final sign = d < 0 ? '-' : '';
  final exp = point - 1;
  if (exp < -4 || exp >= 6) {
    final mantissa = digits.length > 1 ? '${digits[0]}.${digits.substring(1)}' : digits;
    final e = exp.abs().toString().padLeft(2, '0');
    return '$sign${mantissa}e${exp < 0 ? '-' : '+'}$e';
  }
  if (point <= 0) return '${sign}0.${'0' * -point}$digits';
  if (point >= digits.length) return '$sign$digits${'0' * (point - digits.length)}';
  return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
}

/// [v] as Go's `fmt.Sprint` prints a decoded JSON value.
String goSprint(Object? v) => switch (v) {
      null => '<nil>',
      bool b => b ? 'true' : 'false',
      num n => goFormatFloat(n.toDouble()),
      String s => s,
      List<Object?> l => '[${l.map(goSprint).join(' ')}]',
      Map<Object?, Object?> m =>
        'map[${(m.keys.map((k) => '$k').toList()..sort(compareUtf8)).map((k) => '$k:${goSprint(m[k])}').join(' ')}]',
      _ => '$v',
    };

/// Writes [s] as a JSON string escaped as Go's encoding/json escapes it.
void writeJsonString(StringBuffer out, String s) {
  out.write('"');
  for (final r in runesOf(s)) {
    switch (r) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x3c || 0x3e || 0x26 || 0x2028 || 0x2029:
        out.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
      default:
        if (r < 0x20) {
          out.write('\\u00${r.toRadixString(16).padLeft(2, '0')}');
        } else {
          out.writeCharCode(r);
        }
    }
  }
  out.write('"');
}

/// The code points of [s], with each unpaired surrogate replaced by U+FFFD
/// (as Go decodes invalid UTF-8).
Iterable<int> runesOf(String s) sync* {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      final d = s.codeUnitAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) {
        yield 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
        i++;
        continue;
      }
    }
    yield (c >= 0xd800 && c <= 0xdfff) ? 0xfffd : c;
  }
}

/// Orders strings as Go does: bytewise by UTF-8, which is code point order.
int compareUtf8(String a, String b) {
  final x = runesOf(a).iterator, y = runesOf(b).iterator;
  while (true) {
    final hasX = x.moveNext(), hasY = y.moveNext();
    if (!hasX || !hasY) return hasX ? 1 : (hasY ? -1 : 0);
    if (x.current != y.current) return x.current < y.current ? -1 : 1;
  }
}

/// The keys of [m] in Go's byte order.
List<String> sortedKeys(Map<String, Object?> m) => m.keys.toList()..sort(compareUtf8);

/// The UTF-8 length of [s] in bytes.
int utf8Length(String s) {
  var n = 0;
  for (final r in runesOf(s)) {
    n += r < 0x80
        ? 1
        : r < 0x800
            ? 2
            : r < 0x10000
                ? 3
                : 4;
  }
  return n;
}

/// Go's unicode.IsSpace.
bool goIsSpace(int r) =>
    r == 0x20 ||
    (r >= 0x09 && r <= 0x0d) ||
    r == 0x85 ||
    r == 0xa0 ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200a) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202f ||
    r == 0x205f ||
    r == 0x3000;

/// Go's strings.TrimSpace.
String goTrimSpace(String s) {
  var start = 0, end = s.length;
  while (start < end && goIsSpace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && goIsSpace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

/// Go's strings.Fields.
List<String> goFields(String s) {
  final out = <String>[];
  var start = -1;
  for (var i = 0; i < s.length; i++) {
    if (goIsSpace(s.codeUnitAt(i))) {
      if (start >= 0) out.add(s.substring(start, i));
      start = -1;
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) out.add(s.substring(start));
  return out;
}

/// Go's strings.Join(strings.Fields(s), " "): [s] on one line.
String oneLine(String s) => goFields(s).join(' ');

/// [s] quoted as Go's `%q` quotes it (used only in messages).
String goQuote(String s) {
  final out = StringBuffer('"');
  for (final r in runesOf(s)) {
    switch (r) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x07:
        out.write(r'\a');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x0b:
        out.write(r'\v');
      default:
        if (r < 0x20 || r == 0x7f) {
          out.write('\\x${r.toRadixString(16).padLeft(2, '0')}');
        } else if ((r >= 0x80 && r < 0xa0) || r == 0xad || r == 0x2028 || r == 0x2029 || r == 0xfeff) {
          out.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(r);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Go's strings.EqualFold: equal under simple Unicode case folding.
bool goEqualFold(String a, String b) {
  final x = runesOf(a).toList(), y = runesOf(b).toList();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] == y[i]) continue;
    final r = String.fromCharCode(x[i]), s = String.fromCharCode(y[i]);
    if (r.toLowerCase() != s.toLowerCase() && r.toUpperCase() != s.toUpperCase()) return false;
  }
  return true;
}
