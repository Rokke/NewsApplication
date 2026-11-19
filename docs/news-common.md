# news_common (shared package)

Code: `news_common/lib/`, `news_common/test/`

Shared Dart package, referenced from both apps as a path dependency
(`news_common: path: ../news_common` in their `pubspec.yaml`). All shared
model types live here:

- `NewsItem` (`news_common.dart`) — abstract base of articles and tweets
- `FeedEncodeBase`, `ArticleEncodeBase` (`feed_encode.dart`)
- `TweetEncodeBase`, `TweetUserEncode` (`tweet_encode.dart`)
- `encodeFrame`, `FrameDecoder` (`frame_decoder.dart`) — socket framing, see [socket-protocol.md](socket-protocol.md)

## Rules and gotchas
- It is a Flutter package (`flutter` SDK dependency, `flutter_test`): its
  tests run with `fvm flutter test` in `news_common`.
- `news_common.dart` exports `feed_encode.dart` and `frame_decoder.dart` only.
  `tweet_encode.dart` is imported by its own path,
  `package:news_common/tweet_encode.dart`.
- The desktop app subclasses the models with its database and XML mapping:
  `FeedEncode` and `ArticleEncode` in
  `rss_feed_reader/lib/models/feed_encode.dart`, `TweetEncode` in
  `rss_feed_reader/lib/models/tweet_encoding.dart`. The phone uses the base
  classes.
- The `toJson` keys are the wire format. The desktop sends
  `ArticleEncodeBase.toJson()` or `TweetEncodeBase.toJson()` as a reply's
  `data`; the phone reads it back with `ArticleEncodeBase.fromJson` and
  `TweetEncodeBase.fromJSON` (mind the different spelling). Renaming a key is
  a protocol change.
- `TweetUserEncode.fromJSON` reads both a Twitter API user and the wire form.
- `NewsItem` is all the phone shows of an item: `id`, `title`, `text`, `url`,
  `imageUrl`.
- `test/news_common_test.dart` is an empty placeholder; the tests are in
  `test/frame_decoder_test.dart`.
