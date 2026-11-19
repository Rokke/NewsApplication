# Socket protocol (desktop ↔ mobile)

Code: `rss_feed_reader/lib/providers/server_provider.dart`, `rss_feed_reader/lib/providers/ipchecks.dart`, `news_client_application/lib/providers/socket_provider.dart`, `news_client_application/lib/models/socket_response.dart`, `news_common/lib/frame_decoder.dart`, `rss_feed_reader/test/providers/server_provider_test.dart`, `news_client_application/test/providers/socket_provider_test.dart`, `news_common/test/frame_decoder_test.dart`

The desktop app is the server (`SocketServerHandler`, provider
`providerSocketServer`, `defaultPort` 3344); the mobile app is the client
(`SocketProvider`, provider `providerSocket`, port 3344). Plain TCP,
authenticated by one shared secret.

## Handshake (plain text, not framed)
1. On accept the server writes `socketHeadHello` followed by `socketVersion`.
2. The client answers `socketHeadHello`, its own `socketVersion`, a dot and
   the secret: `CONNECTED:<version>.<secret>`.
3. The server buffers what it receives until it starts with `socketHeadHello`
   and ends with `.<secret>`; what lies between is the client's version. A
   buffer that cannot become a handshake, or grows past 500 characters, drops
   the connection at once. A wrong secret never matches and runs into the
   auth timeout.
4. `_authenticated` drops a client whose major version differs from the
   server's. The client keeps the server's version without checking it.
5. The server then sends the current article unasked.

## Frames
After the handshake every message in both directions is one frame,
`<length>:<json>`, built by `encodeFrame` and split again by `FrameDecoder`
(both in `news_common`). A read can hold several frames or part of one. On a
bad frame (`FormatException`) the server drops the client, and the client
closes the connection and reconnects.

## Commands (client → server)
A JSON object with a `command` field, handled by `_handleCommand` in
`server_provider.dart`:

- `feed`, `previous_feed`, `next_feed` — reply with the article selected in
  the desktop's list, after moving that selection back or forward. Phone and
  desktop window share the selection (`FeedListHeader`).
- `article_read` with `id` — marks the article read
  (`changeArticleStatusById`), then replies like `feed`
- `tweet`, `previous_tweet`, `next_tweet` — reply with the tweet at
  `currentTweetIndex`, after moving it (it wraps around)
- `tweet_read` with `id` — `TweetListHeader.removeTweet`, then replies like
  `tweet`
- `start_monitor` — starts monitoring on the desktop; no reply

Anything else is logged as an invalid command. A frame that is not a JSON
object drops the client.

## Replies (server → client)
Built by `_createJSON`, read by `SocketResponse.fromJson`
(`news_client_application/lib/models/socket_response.dart`):

- `code` and `data`:
  - `1` — an article; `data` is `ArticleEncodeBase.toJson()`
  - `2` — a tweet; `data` is `TweetEncodeBase.toJson()`
  - `-1` — no unread articles; `data` is a text
  - `-2` — no unread tweets; `data` is a text
- `articleCount`, `articleIndex`, `tweetCount`, `tweetIndex` — sizes of and
  positions in the desktop's lists
- `running` — whether monitoring is on

`codeAlreadyConnected` is the exception: only `code` and `data`, the address of
the device that took over. The client handles it before
`SocketResponse.fromJson`, which needs the counts.

## Connection rules (server)
- No listener while `socketSecret` is empty; `isConnected` is then null.
- An address on the block list (`providerIPChecks`, `IPChecks.isBlocked`) is
  closed on accept.
- One authenticated client, the newest wins. From the same address it replaces
  the old one silently; from another address the old one first gets
  `codeAlreadyConnected` as its last message.
- A connection that has not authenticated within the auth timeout is dropped.
  At `_maxPending` waiting ones, a new connection pushes out the oldest of the
  address that has the most (`_evictionCandidate`).
- A reply goes only to the connection that asked, and only while it is still
  the client (`_clientSendData`).
- A listener that fails to bind or ends is started again after a growing delay
  (`_retryListenerLater`).

## Reconnecting (client)
- `providerSocket` gives `SocketProvider` the internal address, then the
  external one, leaving out an empty one. Without an address or without a
  secret (`isValid`) it never connects.
- `_tryConnect` tries the addresses in turn. After a round without a
  connection it waits `_initialRetryMs`, doubling per round up to
  `_maxRetryMs`; a handshake resets that (`_resetBackoff`).
- After `codeAlreadyConnected` the status is `SocketStatus.serverInUse` and
  nothing reconnects until `reconnect()`, which takes the server back and gets
  the other device told to stop in turn.
- Writes are queued (`_send`), because a write while a flush is pending
  throws.

## Gotchas
- `socketHeadHello`, `socketVersion` and `codeAlreadyConnected` are declared
  twice, in `server_provider.dart` and in `socket_provider.dart`, and must
  match.
- The frame length counts the JSON's UTF-16 units (`String.length`), not
  bytes.
- A change the other side's older app cannot read raises the major of
  `socketVersion` on both sides and is a major version bump of both apps
  (CLAUDE.md, "Version bump on every build").
- The port is fixed: `defaultPort` on the server, the default of
  `SocketProvider.port` on the client. No setting changes it.
- The tests use loopback only, so Windows Firewall does not prompt:
  `server_provider_test.dart` runs the real server, `socket_provider_test.dart`
  the client against a scripted `_FakeServer`.
