// Takes secrets and the person's home folder out of text that leaves a window:
// the diagnostics, the chat excerpt and what the person typed.
//
// Adapted from Scratch's feedback report (app/lib/feedback/report.dart, the
// `redact` function), with more patterns: 64+ character hex runs, pairing keys
// and home paths.

/// What replaces anything secret.
const redacted = '[redacted]';

/// How many values [redacted] marks in [text].
int redactedCount(String text) => redacted.allMatches(text).length;

/// [text] without bearer values, token, key, secret and password URL
/// parameters, hex runs of 64 or more characters (hashes and keys) and
/// pairing keys. [home] shows as `~`.
String redact(String text, {String? home}) {
  var out = text.replaceAllMapped(_urlParam, (m) => '${m[1]}$redacted');
  out = out.replaceAllMapped(_bearer, (m) => '${m[1]} $redacted');
  out = out.replaceAllMapped(_pairing, (m) => '${m[1]}$redacted');
  out = out.replaceAll(_longHex, redacted);
  return _tilde(out, home);
}

/// [text] with the home folder [home] written as `~`, for both slash
/// directions. A blank [home] changes nothing.
String _tilde(String text, String? home) {
  final h = home?.trim() ?? '';
  if (h.isEmpty || h == '/' || h == '\\') return text;
  final trimmed = h.replaceFirst(RegExp(r'[\/\\]+$'), '');
  if (trimmed.isEmpty) return text;
  final forward = trimmed.replaceAll('\\', '/');
  final back = trimmed.replaceAll('/', '\\');
  final names = {forward, back}.map(RegExp.escape).join('|');
  // Only whole path segments: the match must end at a separator, the end or
  // a character that cannot continue a folder name.
  final pattern = RegExp(
    '(?:$names)'
    r'(?=[\/\\]|$|[^\w.-])',
    caseSensitive: false,
  );
  return text.replaceAllMapped(pattern, (_) => '~');
}

final _urlParam = RegExp(
  r'([?&][\w.\-]*(?:token|key|secret|password)[\w.\-]*=)[^&\s#"<>]*',
  caseSensitive: false,
);
final _bearer = RegExp(
  r'(\bBearer)\s+(?!\[redacted\])[^\s"<>]+',
  caseSensitive: false,
);
final _pairing = RegExp(
  r'(\bpairing[ _-]?key\s*[:=]?\s+)(?!\[redacted\])[^\s"<>]+',
  caseSensitive: false,
);
final _longHex = RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{64,}(?![0-9a-fA-F])');
