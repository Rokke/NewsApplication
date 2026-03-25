# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Multi-project Flutter monorepo for RSS feed and tweet aggregation with a client-server architecture:

- **rss_feed_reader** — Desktop app (Windows-focused) that fetches RSS feeds and tweets, manages a Drift (SQLite) database, and runs a socket server on port 3344 for mobile clients
- **news_client_application** — Mobile client that connects to the rss_feed_reader server via sockets to display unread articles and tweets
- **news_common** — Shared Dart package (local path dependency) with base data models (`NewsItem`, `FeedEncodeBase`, `ArticleEncodeBase`, `TweetEncodeBase`)

## Build & Development Commands

### Flutter operations (run from each project directory)
```bash
flutter pub get          # Install dependencies
flutter run              # Run the app
flutter test             # Run tests
flutter analyze          # Run linter
```

### Code generation (rss_feed_reader — required after changing Drift schema)
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Build script (PowerShell, from project root)
```powershell
./make.ps1 generate      # Run build_runner
./make.ps1 build apk     # Build Android APK
./make.ps1 build web     # Build web
./make.ps1 build win     # Build Windows EXE
./make.ps1 build msi     # Build Windows MSI installer
./make.ps1 build all     # Build all targets
```

### VS Code launch configs
Debug configurations for all three projects are defined in `.vscode/launch.json`.

## Architecture

### State Management
All projects use **Flutter Riverpod** for state management. Providers are in `lib/providers/` in each project.

### Socket Protocol (port 3344)
The desktop app acts as a server (`rss_feed_reader/lib/providers/server_provider.dart`), the mobile app as a client (`news_client_application/lib/providers/socket_provider.dart`). Communication uses a command-based JSON protocol with commands like `start_monitor`, `feed`, `tweet`, `article_read`, `next_feed`, `previous_feed`.

### Database (rss_feed_reader only)
Uses **Drift** ORM (SQLite) with schema in `rss_feed_reader/lib/database/`. Changes to database tables require running `build_runner` to regenerate code.

### RSS Monitoring
`rss_feed_reader/lib/models/rss_tree.dart` contains `RSSHead` — the core monitoring class that periodically polls RSS feeds and manages article state.

### Key Provider Responsibilities (rss_feed_reader)
- `rssProvider` — RSS monitoring lifecycle
- `providerFeedHeader` — Feed list and article management
- `providerTweetHeader` — Tweet management
- `providerSocketServer` — Socket server and client connections
- `providerConfig` — App configuration (SharedPreferences)

### Shared Package
`news_common` is referenced via path dependency in pubspec.yaml files. All shared model types live here.
