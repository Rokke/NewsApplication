// Release one app of the monorepo: bump its version, close its CHANGELOG's
// Unreleased section, build it, commit and push.
//
//   fvm dart run tool/release.dart --app <app> --bump patch|minor|major
//
// Run from the repository root. Fails without committing anything if the
// working tree is not clean, the Unreleased section is empty or the build
// fails. Installing the build and the msix/web publish stay manual.
import 'dart:io';

/// Apps this script can release, with the build each one gets.
const Map<String, List<String>> appBuilds = {
  'news_client_application': ['build', 'apk', '--release'],
  'rss_feed_reader': ['build', 'windows', '--release'],
};

enum Bump { patch, minor, major }

class ReleaseException implements Exception {
  ReleaseException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _versionLine = RegExp(r'^version:[ \t]*(\S+)', multiLine: true);
final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');
final _unreleased = RegExp(r'^## Unreleased[ \t]*$', multiLine: true);
final _nextHeading = RegExp(r'^## ', multiLine: true);
final _issueRef = RegExp(r'#(\d+)');

/// Bumps `major.minor.patch+build` by semver; `+build` always goes up by one
/// and never resets (a missing `+build` counts as 0).
String bumpVersion(String version, Bump bump) {
  final m = _version.firstMatch(version.trim());
  if (m == null) {
    throw ReleaseException('Version "$version" is not major.minor.patch+build');
  }
  var major = int.parse(m[1]!);
  var minor = int.parse(m[2]!);
  var patch = int.parse(m[3]!);
  final build = int.parse(m[4] ?? '0') + 1;
  switch (bump) {
    case Bump.major:
      major++;
      minor = 0;
      patch = 0;
    case Bump.minor:
      minor++;
      patch = 0;
    case Bump.patch:
      patch++;
  }
  return '$major.$minor.$patch+$build';
}

/// Returns [pubspec] with its `version:` bumped, and the new version.
({String content, String version}) bumpPubspec(String pubspec, Bump bump) {
  final m = _versionLine.firstMatch(pubspec);
  if (m == null) throw ReleaseException('No "version:" line in pubspec.yaml');
  final version = bumpVersion(m[1]!, bump);
  final content = pubspec.replaceRange(m.start, m.end, 'version: $version');
  return (content: content, version: version);
}

/// Moves the body of `## Unreleased` under a new `## <version> — <date>`
/// heading, leaving an empty `## Unreleased` on top. Returns the new text and
/// the issue numbers referenced in the moved lines, in order, without repeats.
({String content, List<int> issues}) moveUnreleased(
  String changelog,
  String version,
  String date,
) {
  final crlf = changelog.contains('\r\n');
  if (crlf) changelog = changelog.replaceAll('\r\n', '\n');
  final head = _unreleased.firstMatch(changelog);
  if (head == null) throw ReleaseException('No "## Unreleased" section');
  final bodyStart = head.end;
  final next = _nextHeading.firstMatch(changelog.substring(bodyStart));
  final bodyEnd = next == null ? changelog.length : bodyStart + next.start;
  final body = changelog.substring(bodyStart, bodyEnd).trim();
  if (body.isEmpty) throw ReleaseException('"## Unreleased" is empty');

  final issues = <int>[];
  for (final m in _issueRef.allMatches(body)) {
    final n = int.parse(m[1]!);
    if (!issues.contains(n)) issues.add(n);
  }
  final rest = changelog.substring(bodyEnd);
  var content =
      '${changelog.substring(0, head.start)}## Unreleased\n\n'
      '## $version — $date\n\n$body\n${rest.isEmpty ? '' : '\n$rest'}';
  if (crlf) content = content.replaceAll('\n', '\r\n');
  return (content: content, issues: issues);
}

/// Version without `+build`, as used in headings and commit messages.
String displayVersion(String version) => version.split('+').first;

String commitMessage(String app, String version, List<int> issues) {
  final refs =
      issues.isEmpty ? '' : ' (${issues.map((n) => '#$n').join(', ')})';
  return 'Release $app ${displayVersion(version)}$refs';
}

String today() => DateTime.now().toIso8601String().substring(0, 10);

Future<void> main(List<String> args) async {
  try {
    await _release(args);
  } on ReleaseException catch (e) {
    stderr.writeln('release: $e');
    exitCode = 1;
  }
}

Future<void> _release(List<String> args) async {
  final opts = _parseArgs(args);
  final app = opts['app'];
  final bumpName = opts['bump'];
  if (app == null || !appBuilds.containsKey(app) || bumpName == null) {
    throw ReleaseException(
      'usage: dart run tool/release.dart '
      '--app ${appBuilds.keys.join('|')} --bump patch|minor|major',
    );
  }
  final bump = Bump.values.firstWhere(
    (b) => b.name == bumpName,
    orElse: () => throw ReleaseException('Unknown --bump "$bumpName"'),
  );

  final pubspecPath = '$app/pubspec.yaml';
  final changelogPath = '$app/CHANGELOG.md';
  if (!File(pubspecPath).existsSync()) {
    throw ReleaseException(
      'Run from the repository root ($pubspecPath not found)',
    );
  }

  final status = await _git(['status', '--porcelain']);
  if (status.trim().isNotEmpty) {
    throw ReleaseException('Working tree is not clean:\n$status');
  }
  final branch = (await _git(['rev-parse', '--abbrev-ref', 'HEAD'])).trim();
  if (branch == 'HEAD')
    throw ReleaseException('Detached HEAD, nothing to push');

  final pubspecFile = File(pubspecPath);
  final changelogFile = File(changelogPath);
  if (!changelogFile.existsSync())
    throw ReleaseException('$changelogPath not found');
  final oldPubspec = pubspecFile.readAsStringSync();
  final oldChangelog = changelogFile.readAsStringSync();

  final bumped = bumpPubspec(oldPubspec, bump);
  final moved = moveUnreleased(
    oldChangelog,
    displayVersion(bumped.version),
    today(),
  );

  void restore() {
    pubspecFile.writeAsStringSync(oldPubspec);
    changelogFile.writeAsStringSync(oldChangelog);
  }

  pubspecFile.writeAsStringSync(bumped.content);
  changelogFile.writeAsStringSync(moved.content);
  stdout.writeln('$app: ${bumped.version}');

  final buildArgs = ['flutter', ...appBuilds[app]!];
  stdout.writeln('Building: fvm ${buildArgs.join(' ')} (in $app)');
  final build = await Process.start(
    'fvm',
    buildArgs,
    workingDirectory: app,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final buildExit = await build.exitCode;
  if (buildExit != 0) {
    restore();
    throw ReleaseException('Build failed (exit $buildExit); nothing committed');
  }

  final message = commitMessage(app, bumped.version, moved.issues);
  try {
    await _git(['add', '--', pubspecPath, changelogPath]);
    await _git(['commit', '-m', message, '--', pubspecPath, changelogPath]);
  } on ReleaseException {
    await _gitOrNull(['reset', '-q', '--', pubspecPath, changelogPath]);
    restore();
    rethrow;
  }
  stdout.writeln('Committed: $message');

  final leftover = (await _git(['status', '--porcelain'])).trim();
  if (leftover.isNotEmpty) {
    stdout.writeln(
      'Note: the build left these changes, not committed:\n$leftover',
    );
  }

  await _git(['push', 'origin', branch]);
  stdout.writeln('Pushed $branch');
}

Map<String, String> _parseArgs(List<String> args) {
  final opts = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) throw ReleaseException('Unexpected argument "$a"');
    final eq = a.indexOf('=');
    if (eq > 0) {
      opts[a.substring(2, eq)] = a.substring(eq + 1);
    } else if (i + 1 < args.length) {
      opts[a.substring(2)] = args[++i];
    } else {
      throw ReleaseException('Missing value for $a');
    }
  }
  return opts;
}

Future<String> _git(List<String> args) async {
  final r = await Process.run('git', args);
  if (r.exitCode != 0) {
    throw ReleaseException('git ${args.join(' ')} failed:\n${r.stderr}');
  }
  return r.stdout as String;
}

Future<String?> _gitOrNull(List<String> args) async {
  try {
    return await _git(args);
  } on ReleaseException {
    return null;
  }
}
