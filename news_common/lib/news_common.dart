library news_common;

export 'feed_encode.dart';

abstract class NewsItem {
  String get text;
  String get title;
  String get url;
  String? get imageUrl;
  int get id;
}
