# rss_feed_reader (desktop app)

Code: `rss_feed_reader/lib/`, `make.ps1`

Windows-focused desktop app: fetches RSS feeds and tweets, stores them in a
Drift (SQLite) database, and serves unread items to the mobile client over a
socket (see [socket-protocol.md](socket-protocol.md)).

## State management
Flutter Riverpod. Most providers are in `lib/providers/`; `rssProvider` is
declared next to its class in `lib/models/rss_tree.dart`.

- `rssProvider` (`lib/models/rss_tree.dart`) — RSS monitoring lifecycle
- `providerFeedHeader` (`lib/providers/feed_list.dart`) — feed list and article management
- `providerTweetHeader` (`lib/providers/tweet_list.dart`) — tweet management
- `providerSocketServer` (`lib/providers/server_provider.dart`) — socket server and client connections
- `providerConfig` (`lib/providers/config_provider.dart`) — app configuration (`ApplicationConfiguration`, stored in SharedPreferences)

## RSS monitoring
`RSSHead` in `lib/models/rss_tree.dart` is the core monitoring class: it
periodically polls the RSS feeds and manages article state.

## Database
Drift ORM. Tables are in `lib/database/tables.drift`, the database class
`AppDb` (provider `rssDatabase`) in `lib/database/database.dart`.
`database.g.dart` is generated: after changing the schema run
`fvm dart run build_runner build --delete-conflicting-outputs` in
`rss_feed_reader`.

## Gotchas
- `make.ps1` changes into `rss_feed_reader` before doing anything, so
  `./make.ps1 build apk` builds this app's APK, not the mobile client's.
  `build` also runs `flutter pub upgrade` first.
- `./make.ps1 generate` runs `build_runner build` without
  `--delete-conflicting-outputs`; pass `./make.ps1 generate build del` for it
  (`generate watch [del]` runs the watcher).
