import 'package:news_common/news_common.dart';
import 'package:news_common/tweet_encode.dart';

class SocketResponse {
  SocketResponse({required this.code, required this.numberOfArticles, required this.currentArticle, required this.numberOfTweets, required this.currentTweet, this.newsItem, this.running});
  final int code, numberOfArticles, currentArticle, numberOfTweets, currentTweet;
  final bool? running;
  NewsItem? newsItem;
  // ArticleEncodeBase? articleEncodeBase;
  // TweetEncode? tweetEncodeBase;
  factory SocketResponse.fromJson(Map<String, dynamic> json) {
    final ret = SocketResponse(code: json['code'], numberOfArticles: json['articleCount'], currentArticle: json['articleIndex'], numberOfTweets: json['tweetCount'], currentTweet: json['tweetIndex'], running: json['running']);
    if (ret.code == 1 && ret.numberOfArticles > 0) {
      ret.newsItem = ArticleEncodeBase.fromJson(json['data']);
    } else if (ret.code == 2 && ret.numberOfTweets > 0) {
      ret.newsItem = TweetEncodeBase.fromJSON(json['data']);
    }
    return ret;
  }
}
