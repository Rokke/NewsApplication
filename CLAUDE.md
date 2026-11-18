# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Multi-project Flutter monorepo for RSS feed and tweet aggregation:
`rss_feed_reader` (desktop app and socket server), `news_client_application`
(mobile client) and `news_common` (shared package).

## Agent docs — start at docs/INDEX.md

What agents learn about this repo lives in `docs/`, not here. A question about
how something works starts at `docs/INDEX.md`, then checks the doc against the
code. A change touching an area's `Code:` paths updates its doc in the same
change; a wrong fact is fixed where it stands; a doc that no longer helps is
deleted.

## Build & Development Commands

### Flutter operations (run from each project directory, through fvm)
```bash
fvm flutter pub get      # Install dependencies
fvm flutter run          # Run the app
fvm flutter test         # Run tests
fvm flutter analyze      # Run linter
```

### Code generation (rss_feed_reader — required after changing Drift schema)
```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

### Build script (PowerShell, from project root; always works on rss_feed_reader)
```powershell
./make.ps1 generate build del   # Run build_runner (with --delete-conflicting-outputs)
./make.ps1 build apk     # Build Android APK
./make.ps1 build web     # Build web
./make.ps1 build win     # Build Windows EXE
./make.ps1 build msi     # Build Windows MSI installer
./make.ps1 build all     # Build all targets
```

### Version bump on every build
Every new build of an app gets a new version number — never ship two builds
with the same one. Before building, bump `version:` in that app's
`pubspec.yaml` (`rss_feed_reader` and/or `news_client_application`):

- Use semantic versioning `major.minor.patch+build`: **patch** for bug fixes,
  **minor** for new features, **major** for breaking changes (e.g. a socket
  protocol change that needs both apps updated together). Bumping minor resets
  patch to 0; bumping major resets minor and patch.
- Always increment the `+build` number too (Android `versionCode` comes from
  it and must keep increasing); it never resets.
- Bump only the app(s) actually being rebuilt. The msix package takes its
  version from `pubspec.yaml`, so no separate bump is needed there.
- The bump goes in the release commit that `tool/release.dart` makes (below),
  not in the fix/feature commits.

### CHANGELOG and releases
- Every fix or feature adds a line under `## Unreleased` in its app's
  `CHANGELOG.md` (`news_client_application/` and/or `rss_feed_reader/`),
  ending with the issue number, e.g. `- Keep the socket open (#12)`. A change
  to both apps adds a line to both.
- Releases go through the script, from the repo root, on a clean tree:
  ```bash
  fvm dart run tool/release.dart --app news_client_application --bump patch
  fvm dart run tool/release.dart --app rss_feed_reader --bump minor
  ```
  It bumps `version:` by the rule above, moves `## Unreleased` under
  `## x.y.z — <date>` (fails if it is empty), builds (`flutter build apk
  --release` / `flutter build windows --release`), commits
  "Release <app> x.y.z (#n, …)" and pushes the current branch. If the tree is
  dirty or the build fails it stops with nothing committed, printing
  `Release stopped: <why>`. Installing the build and the msix/web publish to
  mobcon stay manual.
- The orchestrator asks for each app's release on its own
  (`projects/newsapplication.yml` in Rokke/orchestrator, `release.apps`,
  orchestrator#114): an issue counts for an app when its commits touch the
  app's folder or `news_common`. A yes renames the app's `## Unreleased` to
  `## x.y.z (date)`, runs the script with `--no-git` (bump and build only,
  no tree check, no CHANGELOG move, no commit or push), then commits
  "Release <app> x.y.z (#n, …)" and pushes `Add-category-handling` itself.
- Tests for the script: `cd tool && fvm dart test`.

### VS Code launch configs
Debug configurations for all three projects are defined in `.vscode/launch.json`.
