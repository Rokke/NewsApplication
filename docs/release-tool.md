# Release tool

Code: `tool/`

`tool/release.dart` releases one app: version bump, CHANGELOG, build, commit,
push. When to use it and the version rules are in CLAUDE.md ("Version bump on
every build", "CHANGELOG and releases"); this is how it works inside.

- `tool/` is its own pure-Dart package (`tool/pubspec.yaml`, only `test` as a
  dev dependency). The script runs from the repo root, because it addresses
  `<app>/pubspec.yaml` and `<app>/CHANGELOG.md`; its tests run with
  `fvm dart test` in `tool`.
- `appBuilds` maps each app folder it can release to that app's `flutter`
  build arguments. A new app is added there, and needs a `version:` line in
  its `pubspec.yaml` and a `## Unreleased` section in its `CHANGELOG.md`.
- The text work is in pure functions, covered by `tool/test/release_test.dart`:
  - `bumpVersion` — the semver bump; `+build` always goes up by one
  - `bumpPubspec` — replaces only the `version:` line
  - `moveUnreleased` — moves the lines under `## Unreleased` to a new
    `## <version> — <date>` heading, leaves an empty `## Unreleased` on top
    and returns the issue numbers (`#n`) found in the moved lines
  - `commitMessage` — `Release <app> <version without +build> (#n, …)`

  A file with CRLF line endings keeps them.
- `_release` does the rest and has no tests. It checks that the tree is clean
  and HEAD is on a branch, writes the bumped `pubspec.yaml` and the moved
  `CHANGELOG.md`, runs `fvm flutter` with the app's `appBuilds` arguments in
  the app folder, commits exactly those two files and pushes the branch to
  `origin`.
- A failed build writes both files back (`restore`), a failed commit unstages
  them as well. A failed push leaves the release commit in place, unpushed.
  Other files the build changed are listed and not committed. A failure it checks for is a
  `ReleaseException`, printed as `Release stopped: <why>` with exit code 1.
- `--no-git` skips the tree and branch checks, leaves `CHANGELOG.md` alone and
  stops after the build; the caller has renamed `## Unreleased` already and
  commits and pushes itself (CLAUDE.md, "CHANGELOG and releases"). The two
  ways write different headings: the script `## x.y.z — <date>`, the
  orchestrator `## x.y.z (<date>)`. The rename leaves the file without
  `## Unreleased` until the next change adds the heading back, as in
  `rss_feed_reader/CHANGELOG.md` on 2026-11-19.
- For `rss_feed_reader` the build writes into the folder the live desktop app
  was started from, see the gotchas in
  [rss-feed-reader.md](rss-feed-reader.md).
