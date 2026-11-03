import 'package:test/test.dart';

import '../release.dart';

void main() {
  group('bumpVersion', () {
    test('patch bumps patch and build', () {
      expect(bumpVersion('2.0.0+9', Bump.patch), '2.0.1+10');
    });
    test('minor resets patch, build keeps counting', () {
      expect(bumpVersion('2.3.4+9', Bump.minor), '2.4.0+10');
    });
    test('major resets minor and patch, build keeps counting', () {
      expect(bumpVersion('4.2.7+13', Bump.major), '5.0.0+14');
    });
    test('missing build number starts at 1', () {
      expect(bumpVersion('1.0.0', Bump.patch), '1.0.1+1');
    });
    test('rejects a malformed version', () {
      expect(
        () => bumpVersion('1.0', Bump.patch),
        throwsA(isA<ReleaseException>()),
      );
    });
  });

  group('bumpPubspec', () {
    test('replaces only the version line', () {
      const pubspec =
          'name: app\n\nversion: 2.0.0+9\n\nenvironment:\n'
          '  sdk: ^3.7.0\n  version: 9.9.9\n';
      final r = bumpPubspec(pubspec, Bump.minor);
      expect(r.version, '2.1.0+10');
      expect(r.content, pubspec.replaceFirst('2.0.0+9', '2.1.0+10'));
    });
    test('keeps CRLF line endings', () {
      final r = bumpPubspec('name: app\r\nversion: 1.0.0+1\r\n', Bump.patch);
      expect(r.content, 'name: app\r\nversion: 1.0.1+2\r\n');
    });
    test('fails without a version line', () {
      expect(
        () => bumpPubspec('name: app\n', Bump.patch),
        throwsA(isA<ReleaseException>()),
      );
    });
  });

  group('moveUnreleased', () {
    const changelog =
        '# Changelog\n\n## Unreleased\n\n'
        '- Fix one (#8)\n- Fix two (#9, #8)\n\n'
        '## 1.0.0 — 2026-01-01\n\n- Old (#1)\n';

    test('moves the lines under a dated version heading', () {
      final r = moveUnreleased(changelog, '1.0.1', '2026-11-03');
      expect(
        r.content,
        '# Changelog\n\n## Unreleased\n\n'
        '## 1.0.1 — 2026-11-03\n\n- Fix one (#8)\n- Fix two (#9, #8)\n\n'
        '## 1.0.0 — 2026-01-01\n\n- Old (#1)\n',
      );
    });
    test('collects the issue numbers in order without repeats', () {
      expect(moveUnreleased(changelog, '1.0.1', '2026-11-03').issues, [8, 9]);
    });
    test('works when Unreleased is the only section', () {
      final r = moveUnreleased('## Unreleased\n\n- A (#3)\n', '0.1.0', 'D');
      expect(r.content, '## Unreleased\n\n## 0.1.0 — D\n\n- A (#3)\n');
      expect(r.issues, [3]);
    });
    test('keeps CRLF line endings', () {
      final r = moveUnreleased(
        '## Unreleased\r\n\r\n- A (#3)\r\n',
        '0.1.0',
        'D',
      );
      expect(
        r.content,
        '## Unreleased\r\n\r\n## 0.1.0 — D\r\n\r\n- A (#3)\r\n',
      );
    });
    test('fails when Unreleased is empty', () {
      expect(
        () => moveUnreleased(
          '## Unreleased\n\n\n## 1.0.0 — X\n\n- Old\n',
          '1.0.1',
          'D',
        ),
        throwsA(isA<ReleaseException>()),
      );
    });
    test('fails when there is no Unreleased section', () {
      expect(
        () => moveUnreleased('## 1.0.0\n\n- Old\n', '1.0.1', 'D'),
        throwsA(isA<ReleaseException>()),
      );
    });
  });

  test('commitMessage lists the issues and drops the build number', () {
    expect(
      commitMessage('rss_feed_reader', '4.0.1+14', [13, 15]),
      'Release rss_feed_reader 4.0.1 (#13, #15)',
    );
    expect(
      commitMessage('rss_feed_reader', '4.0.1+14', []),
      'Release rss_feed_reader 4.0.1',
    );
  });
}
