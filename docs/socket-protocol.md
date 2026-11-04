# Socket protocol (desktop ↔ mobile)

Code: `rss_feed_reader/lib/providers/server_provider.dart`, `news_client_application/lib/providers/socket_provider.dart`, `news_common/lib/frame_decoder.dart`

The desktop app is the server (`SocketServerHandler`, provider
`providerSocketServer`, `defaultPort` 3344); the mobile app is the client
(`SocketProvider`, port 3344). The mobile app uses Flutter Riverpod; its
providers are in `news_client_application/lib/providers/`.

Messages are JSON objects with a `command` field, framed with `encodeFrame`
and split again by `FrameDecoder` (both in `news_common`).

Commands the server handles (`_handleCommand` in `server_provider.dart`):
`start_monitor`, `feed`, `previous_feed`, `next_feed`, `article_read`,
`tweet`, `previous_tweet`, `next_tweet`, `tweet_read`. Anything else is
logged as an invalid command.
