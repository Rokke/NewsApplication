# Agent docs — index

Entry point for agents. One line per area → its doc. Check a doc against the
code before relying on it; a change touching a doc's `Code:` paths updates
that doc in the same change.

- Desktop app (`rss_feed_reader`): RSS monitoring, Drift database, providers → [rss-feed-reader.md](rss-feed-reader.md)
- Desktop app's logging and diagnostics: log file, frame watch, display and power events from the Windows runner → [rss-feed-reader-diagnostics.md](rss-feed-reader-diagnostics.md)
- Socket protocol between desktop server and mobile client (`news_client_application`), port 3344 → [socket-protocol.md](socket-protocol.md)
- Mobile client (`news_client_application`): start-up, providers, home screen, logging, tests → [news-client.md](news-client.md)
- Shared models and framing (`news_common`) → [news-common.md](news-common.md)
- Release script (`tool/`): how `tool/release.dart` works inside → [release-tool.md](release-tool.md)
