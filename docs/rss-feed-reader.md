# rss_feed_reader (desktop app)

Code: `rss_feed_reader/lib/`, `rss_feed_reader/test/`, `rss_feed_reader/windows/runner/`, `make.ps1`

Windows-focused desktop app: fetches RSS feeds and tweets, stores them in a
Drift (SQLite) database, and serves unread items to the mobile client over a
socket (see [socket-protocol.md](socket-protocol.md)). Its log file, frame
watch and display/power events are in
[rss-feed-reader-diagnostics.md](rss-feed-reader-diagnostics.md).

## State management
Flutter Riverpod. Most providers are in `lib/providers/`; the rest are
declared next to their class or widget.

- `providerConfig` (`lib/providers/config_provider.dart`) — `ApplicationConfiguration`, a `ChangeNotifier`. The provider itself throws; `main()` loads the configuration and overrides it.
- `rssDatabase` (`lib/database/database.dart`) — the `AppDb`
- `rssProvider` (`lib/models/rss_tree.dart`) — `RSSHead`, the monitoring timer
- `monitoringRunning` (`lib/models/rss_tree.dart`) — whether monitoring is on
- `providerFeedHeader` (`lib/providers/feed_list.dart`) — `FeedListHeader`: feeds, unread articles, the selected article, fetching
- `providerTweetHeader` (`lib/providers/tweet_list.dart`) — `TweetListHeader`: tweet users and unread tweets
- `providerSocketServer` (`lib/providers/server_provider.dart`) — `SocketServerHandler`. Only `CustomAppBarWidget` (`lib/screens/widgets/appbar_widget.dart`) reads it, with `ref.read`, so the server is created when the app bar builds.
- `providerIPChecks` (`lib/providers/ipchecks.dart`) — `IPChecks`, the block list for incoming connections; null when `dataFilepath` is empty
- With their screens: `applicationVersionProvider` (`lib/screens/home.dart`), `providerErrorReported` (`lib/screens/widgets/details_widget.dart`), `providerCategories` (`lib/screens/widgets/popups/update_feed.dart`)

`rssProvider`, `providerSocketServer` and `providerIPChecks` watch
`providerConfig`, so saving Settings (`ApplicationConfiguration.updateSettings`)
disposes the `RSSHead` and the socket server. The next app bar build creates
the new server.

## RSS monitoring
`RSSHead` (`lib/models/rss_tree.dart`) only runs the timer: `startMonitoring`
sets `monitoringRunning` and starts a 10-second periodic timer,
`stopMonitoring` cancels it. A tick, unless the previous one is still `busy`,
does one thing:

1. `FeedListHeader.findFeedToUpdate` takes the feed whose next check comes
   first (`FeedEncodeBase.earliestMillisecondsSinceEpoch`: `lastCheck` plus
   `ttl` minutes) and, when that time has passed, fetches it.
2. When no feed was due, `TweetListHeader.checkAndUpdateTweet` refreshes one
   tweet user.

A `NewsAppNetworkException` (from `getResponse` in `lib/providers/network.dart`,
which the tweet calls use) sets `tweetsFailing`: that `RSSHead` polls no more
tweets. Any other error stops monitoring.

Monitoring is started
- in release builds only, 20 s after launch: `applicationVersionProvider`
  (`lib/screens/home.dart`) calls `startMonitoring(postponeStart:)` under
  `kReleaseMode`. It watches `rssProvider`, so it starts the new `RSSHead`
  after Settings were saved too; a debug build then stays stopped while
  `monitoringRunning` keeps its old value.
- by `MonitorButton` (`lib/screens/widgets/monitor_button.dart`), which also
  stops it
- by the phone's `start_monitor` command

## Fetching a feed
`FeedListHeader.updateOrCreateFeed` serves the timer, the refresh button of a
feed and the add-feed popup (no feed, only a `url`):

1. `readFeed` (`lib/providers/network.dart`) downloads the XML and returns its
   first `channel` (RSS) or `feed` (Atom) element.
2. `ChannelMapper.fromXML` and `ItemMapper.fromXML` (`lib/models/xml_mapper/`)
   read the elements into plain fields.
3. `FeedFullDecode.fromChannel` (`lib/models/feed_encode.dart`) makes a
   `FeedEncode` and its `ArticleEncode` list; items without a link are dropped.
4. `FeedListHeader.addFetchedArticles` takes each item through these checks,
   in order:
   - the feed has categories (`feed_category`) and the item's `category`
     contains none of them: ignored
   - its url is among the feed's `activeArticles`: known, noted as still there
   - its guid, when no other item of the fetch has it, matches an article of
     the feed: the same article with a new link. `_reuseArticleWithGuid` moves
     the url; no row is added and the read status stays.
   - its `pubDate` is more than `oldItemAge` before the feed's newest known
     article: skipped
   - otherwise inserted and appended to `articles`

   Articles of the feed that were not in the fetch lose their `active` flag.

A fetch that fails gives null from `fetchFeedEncode`; the feed's `lastCheck` is
then set in memory, so it is tried again after its `ttl`.

## Tweets
`TweetListHeader` (`lib/providers/tweet_list.dart`) holds `tweetUsers` and the
unread `tweets`. `checkAndUpdateTweet` takes the user checked longest ago and,
when that is more than `twitterCheckInterval` back, calls
`refreshTweetsFromUser`: the Twitter API v2 with the user's `since_id`, decoded
by `TweetFullDecode` (`lib/models/tweet_encoding.dart`), new tweets stored with
`AppDb.insertTweet`. The token is `twitterBearerToken` in `lib/secret.dart`;
with an empty token nothing is fetched.

## Database
Drift ORM. Tables are in `lib/database/tables.drift`, the database class
`AppDb` (provider `rssDatabase`) in `lib/database/database.dart`.
`database.g.dart` is generated: after changing the schema run
`fvm dart run build_runner build --delete-conflicting-outputs` in
`rss_feed_reader`, raise `schemaVersion` and add the step to `migration`.

- File: `_openConnection` uses `D:\Temp\AppDB` when that folder exists, else
  the documents folder; `rss_db.sqlite` in release builds,
  `rss_db_debug.sqlite` otherwise.
- `article.status` is an `ArticleTableStatus`, `tweet.status` a
  `TweetTableStatus`. `article.active` says the article was in the feed's
  latest fetch; `AppDb.cleanOldData` deletes read articles that are no longer
  active, and read tweets.
- `article` is unique on parent and url (`idx_article_id`).
- `AppDb.forTesting` takes an executor, for the in-memory test database.

## Config
`ApplicationConfiguration` (`lib/providers/config_provider.dart`) keeps these
SharedPreferences keys; `lib/screens/settings_screen.dart` edits the first
three:

- `socketSecret` — shared with the phone; empty means no socket server
- `logDirectory` — log folder, default `defaultLogDirectory`, used from the
  next start
- `logFilepath` — despite its name the field `dataFilepath`: the folder of the
  IP block list. Default `D:\Temp` in debug builds, empty otherwise.
- `windowSize`, `windowPosition` (`checkWindowSize`), `firstPercentage`
  (`updatePercentage`, the divider between list and details)
- `socketInternal`, `socketExternal` — loaded, used by nothing in this app

The block list (`IPChecks`, `lib/providers/ipchecks.dart`) is
`rss_ipblocklist.json` in `dataFilepath`: address prefixes, each with a reason.
A missing file is created from the older `rss_ipconnections.json` or with two
default prefixes. `isBlocked` is a `startsWith` on the remote address.

## Tests
`fvm flutter test` in `rss_feed_reader`; none opens a window.

- `test/helpers/test_db.dart`: `openTestDb` gives an in-memory `AppDb`
  (through `winsqlite3.dll` when there is no `sqlite3.dll`), `seedArticles`
  fills it. `test/screens/details_test.dart` overrides `rssDatabase` with it.
- `test/providers/server_provider_test.dart` runs a real `SocketServerHandler`
  on loopback with `sendFeedOnAuth: false`; left on, the first authenticated
  client makes it open the real database.
- `test/data/` holds the fixtures of `test/models/feed_encode_test.dart`.

## Gotchas
- `make.ps1` changes into `rss_feed_reader` before doing anything, so
  `./make.ps1 build apk` builds this app's APK, not the mobile client's.
  `build` also runs `flutter pub upgrade` first.
- `./make.ps1 generate` runs `build_runner build` without
  `--delete-conflicting-outputs`; pass `./make.ps1 generate build del` for it
  (`generate watch [del]` runs the watcher).
- `make.ps1` is for a person at the machine. `build` runs `flutter` through
  `Start-Process` (a console window each time), `build all` ends with
  `Invoke-Item` on `pubspec.yaml`, and `build msi` and `build all` copy what
  they built to mobcon with `scp`. `build msi` runs `dart run msix:create`,
  but `msix` is not in `pubspec.yaml`. It calls `flutter` and `dart` directly,
  not through fvm. Agents build with `fvm flutter build windows --release` in
  `rss_feed_reader`.
- The root `.gitignore` lists `windows/`, while the files under
  `rss_feed_reader/windows/` are tracked: a new file there needs `git add -f`.
- `lib/secret.dart` and `lib/database/database.g.dart` are gitignored and
  needed to compile.
- `MyHttpOverrides` (`lib/providers/network.dart`, set in `main()`) accepts
  any TLS certificate and logs a warning.
- Nothing uses `lib/providers/shared_prefs.dart` (commented out in full) or
  `rss_feed_reader/update_db.cmd` (build_runner through bare `flutter`).
- The live instance on the author's PC is started at logon by a Startup-folder
  shortcut to `rss_feed_reader\build\windows\x64\runner\Release\rss_feed_reader.exe`,
  with that folder as working directory: a release build writes into the
  folder the running app was started from. (Not in the code. Source: agent
  memory note `desktop-app-restart`, 2026-10-30.)
