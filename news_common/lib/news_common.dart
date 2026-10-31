library news_common;

export 'feed_encode.dart';
export 'frame_decoder.dart';

abstract class NewsItem {
  String get text;
  String get title;
  String get url;
  String? get imageUrl;
  int get id;
}
