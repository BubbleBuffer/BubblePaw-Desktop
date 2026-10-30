// Versions: parsing, ordering with prerelease identifiers (nightly builds
// included) and the Core range.

import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:flutter_test/flutter_test.dart';

SemVer v(String text) => SemVer.parse(text);

void main() {
  group('parse', () {
    test('reads numbers, prerelease and build', () {
      final version = v('0.1.0-nightly.20261029+abc1234');
      expect([version.major, version.minor, version.patch], [0, 1, 0]);
      expect(version.pre, ['nightly', '20261029']);
      expect(version.build, 'abc1234');
      expect(version.isPrerelease, isTrue);
      expect('$version', '0.1.0-nightly.20261029+abc1234');
    });

    test('accepts a leading v and rejects what is not a version', () {
      expect(v('v0.3.1'), const SemVer(0, 3, 1));
      expect(SemVer.tryParse('0.3'), isNull);
      expect(SemVer.tryParse('latest'), isNull);
      expect(SemVer.tryParse('1.2.3.4'), isNull);
      expect(() => SemVer.parse('x'), throwsFormatException);
    });
  });

  group('order', () {
    test('numbers compare as numbers', () {
      expect(v('0.10.0') > v('0.9.9'), isTrue);
      expect(v('1.0.0') > v('0.99.99'), isTrue);
      expect(v('0.3.1') == v('0.3.1'), isTrue);
    });

    test('a release is newer than its prereleases', () {
      expect(v('0.2.0') > v('0.2.0-rc.1'), isTrue);
      expect(v('0.2.0') > v('0.2.0-nightly.20261029+abc1234'), isTrue);
    });

    test('prerelease identifiers follow semver', () {
      final ordered = [
        '0.2.0-alpha',
        '0.2.0-alpha.1',
        '0.2.0-alpha.beta',
        '0.2.0-beta',
        '0.2.0-beta.2',
        '0.2.0-beta.11',
        '0.2.0-rc.1',
        '0.2.0',
      ].map(v).toList();
      for (var i = 0; i < ordered.length - 1; i++) {
        expect(
          ordered[i] < ordered[i + 1],
          isTrue,
          reason: '${ordered[i]} < ${ordered[i + 1]}',
        );
      }
    });

    test('nightly builds order by their date', () {
      expect(
        v('0.1.0-nightly.20261029+aaa') > v('0.1.0-nightly.20261027+zzz'),
        isTrue,
      );
      // A nightly of a newer base is newer than the stable build of the
      // older base.
      expect(v('0.2.0-nightly.20261029+3a7f1c2') > v('0.1.0'), isTrue);
      // A nightly of the same base is older than that release.
      expect(v('0.1.0-nightly.20261029+3a7f1c2') > v('0.1.0'), isFalse);
    });

    test('build metadata does not change the order', () {
      expect(v('0.1.0+a').compareTo(v('0.1.0+b')), 0);
    });
  });

  group('Core range', () {
    test('is >=0.3.1 and <0.5.0', () {
      expect(coreCompatibleRange.contains(v('0.3.1')), isTrue);
      expect(coreCompatibleRange.contains(v('0.4.9')), isTrue);
      expect(coreCompatibleRange.contains(v('0.3.0')), isFalse);
      expect(coreCompatibleRange.contains(v('0.5.0')), isFalse);
      expect(coreCompatibleRange.contains(v('1.0.0')), isFalse);
    });

    test('says why a version is outside', () {
      expect(coreCompatibleRange.reasonOutside(v('0.2.4')), contains('older'));
      expect(coreCompatibleRange.reasonOutside(v('0.5.1')), contains('0.5.0'));
      expect(coreCompatibleRange.reasonOutside(v('0.4.0')), isNull);
      expect(
        coreCompatibleRange.describe(),
        '0.3.1 or newer, older than 0.5.0',
      );
    });
  });
}
