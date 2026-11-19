# news_client_application (mobile client)

Code: `news_client_application/lib/`, `news_client_application/test/`

Phone app: shows one unread article or tweet at a time from the desktop app
and marks it read there. It stores no items itself; everything comes over the
socket (see [socket-protocol.md](socket-protocol.md)). Built with
`fvm flutter build apk --release` in `news_client_application`; `make.ps1`
never builds this app.

## Start-up
`main()` (`lib/main.dart`) initializes `LogService` and
`ApplicationConfiguration`, then overrides `logServiceProvider` and
`providerConfig` with them in the `ProviderScope`. Both providers throw when
they are not overridden, in tests too.

## Providers
Flutter Riverpod, in `lib/providers/`:

- `providerConfig` (`config_provider.dart`) — `ApplicationConfiguration`, a `ChangeNotifier` over the SharedPreferences keys `socketInternal`, `socketExternal`, `socketSecret` and `logFilepath`. Nothing uses `logFilepath`.
- `providerSocket` (`socket_provider.dart`) — the `SocketProvider`. It watches `providerConfig`: Save in `SettingsScreen` (`lib/settings_screen.dart`) disposes it and builds a new one, also when nothing was changed.
- `logServiceProvider` (`log_provider.dart`) — the `LogService`
- `appVersionProvider` (`lib/home.dart`) — the version shown in the app bar

## Home screen
`HomePage` (`lib/home.dart`) watches `providerSocket` and rebuilds on
`SocketProvider.status`. Its body is a `StreamBuilder` on
`SocketProvider.stream` that shows the latest `SocketResponse`.

- `SocketResponse.fromJson` (`lib/models/socket_response.dart`) turns a reply
  into the counts and a `NewsItem`: an `ArticleEncodeBase` for code 1, a
  `TweetEncodeBase` for code 2, none for the other codes.
- `showFeeds` says whether the screen is on articles or on tweets, and with
  that which command a button sends:
  - refresh, which also switches `showFeeds`: `feed` or `tweet`
  - previous and next: `previous_feed`, `next_feed` or `previous_tweet`,
    `next_tweet`
  - delete: `article_read` or `tweet_read` with the item's `id`
  - play, shown only in `connectedNotRunning`: `start_monitor`

  The browser button opens the item's `url` on the phone.
- `SocketStatus`: `disconnected`; `waiting` (connecting); `connected`
  (handshake sent, no reply yet); `connectedRunning` and
  `connectedNotRunning` (from a reply's `running`); `serverInUse` (another
  device took the server, the screen offers `reconnect()`).
- The stream is single-subscription and belongs to one `SocketProvider`. So
  the `StreamBuilder` has `key: ObjectKey(socketProvider)`, and the
  `serverInUse` screen is returned from inside its builder, not in its place.

## Logging
`LogService` (`lib/providers/log_provider.dart`) writes every
`package:logging` record to `logs/news_client.log` in the application support
directory, at `INFO` (`ALL` in debug builds). At start a file over 1 MB is
renamed to `news_client.log.old`, replacing the previous one.

"Send Log" in Settings flushes the file and hands it to
`StatsService.zipAndSendFile` from `statssender`, a path dependency outside
this repo (`pubspec.yaml`).

The log holds the socket secret without its last three characters:
`SocketProvider._onData` logs the auth response masked only that far.

## Tests
`fvm flutter test` in `news_client_application`; none opens a window.

- `test/providers/socket_provider_test.dart` — `SocketProvider` against
  `_FakeServer`, a loopback stand-in for the desktop. Its `_OnAuth` script
  says what each connection does after the handshake.
- `test/widget_test.dart` — `HomePage` with an empty configuration, so nothing
  connects; it overrides `providerConfig` and `appVersionProvider`.
