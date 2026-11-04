# news_common (shared package)

Code: `news_common/lib/`

Shared Dart package, referenced from both apps as a path dependency
(`news_common: path: ../news_common` in their `pubspec.yaml`). All shared
model types live here:

- `NewsItem` (`news_common.dart`) — abstract base of articles and tweets
- `FeedEncodeBase`, `ArticleEncodeBase` (`feed_encode.dart`)
- `TweetEncodeBase`, `TweetUserEncode` (`tweet_encode.dart`)
- `encodeFrame`, `FrameDecoder` (`frame_decoder.dart`) — socket framing, see [socket-protocol.md](socket-protocol.md)
