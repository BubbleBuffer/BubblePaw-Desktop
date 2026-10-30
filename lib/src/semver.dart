// Semantic versions: parsing, ordering with prerelease identifiers, and the
// range of Core versions this app works with.

/// A version such as `0.3.1`, `0.2.0-rc.1` or
/// `0.1.0-nightly.20261029+abc1234`. Build metadata after `+` is kept for
/// display and ignored when versions are ordered.
class SemVer implements Comparable<SemVer> {
  const SemVer(
    this.major,
    this.minor,
    this.patch, [
    this.pre = const [],
    this.build = '',
  ]);

  final int major;
  final int minor;
  final int patch;

  /// The dot-separated identifiers after `-`; empty for a release.
  final List<String> pre;

  /// The text after `+`, without it.
  final String build;

  static final _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  /// Null when [text] is not a version. A leading `v` is allowed.
  static SemVer? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final pre = match.group(4);
    return SemVer(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      pre == null ? const [] : pre.split('.'),
      match.group(5) ?? '',
    );
  }

  /// Throws a [FormatException] when [text] is not a version.
  static SemVer parse(String text) =>
      tryParse(text) ?? (throw FormatException('Not a version: $text'));

  bool get isPrerelease => pre.isNotEmpty;

  @override
  int compareTo(SemVer other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a < b ? -1 : 1;
    }
    // A release is newer than any prerelease of the same numbers.
    if (pre.isEmpty || other.pre.isEmpty) {
      if (pre.isEmpty && other.pre.isEmpty) return 0;
      return pre.isEmpty ? 1 : -1;
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final c = _compareIdentifier(pre[i], other.pre[i]);
      if (c != 0) return c;
    }
    return pre.length.compareTo(other.pre.length);
  }

  // Numbers compare as numbers and sort before words; words compare as text.
  static int _compareIdentifier(String a, String b) {
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer && compareTo(other) == 0 && other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(pre));

  @override
  String toString() =>
      '$major.$minor.$patch'
      '${pre.isEmpty ? '' : '-${pre.join('.')}'}'
      '${build.isEmpty ? '' : '+$build'}';
}

/// `>= min` and `< maxExclusive`.
class VersionRange {
  const VersionRange(this.min, this.maxExclusive);

  final SemVer min;
  final SemVer maxExclusive;

  bool contains(SemVer version) => version >= min && version < maxExclusive;

  /// For a message: `0.3.1 or newer, older than 0.5.0`.
  String describe() => '$min or newer, older than $maxExclusive';

  /// Why [version] is outside the range; null when it is inside.
  String? reasonOutside(SemVer version) {
    if (version < min) return '$version is older than $min.';
    if (version >= maxExclusive) {
      return '$version is $maxExclusive or newer, which this BubblePaw does '
          'not support yet.';
    }
    return null;
  }
}

/// The BubblePaw Core versions this Desktop works with. The one place to
/// change when Desktop moves to a new Core.
