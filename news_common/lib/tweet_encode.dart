import 'package:flutter/foundation.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:news_common/news_common.dart';

class TweetEncodeBase extends NewsItem {
  @override
  final int id; //, tweetUserId;
  @override
  final String text;
  final DateTime createdAt;
  TweetEncodeBase? retweet;
  // final List<TweetReferencedTweet> referenced_tweets;
  TweetUserEncode parentUser;

  TweetEncodeBase({required this.id, required this.parentUser, required this.text, required this.createdAt, this.retweet});
  factory TweetEncodeBase.fromJSON(Map<String, dynamic> data) {
    try {
      debugPrint('date: ${data['created_at']}');
      // if (parentUser == null) ;
      final ret = TweetEncodeBase(
        id: int.parse(data['id'].toString()),
        parentUser: TweetUserEncode.fromJSON(data['user']),
        text: HtmlUnescape().convert(data['text'].toString()),
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['created_at']),
      );
      return ret;
    } catch (err) {
      debugPrint('TweetEncodeBase.fromJSON exception: $data');
      rethrow;
    }
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'created_at': createdAt.millisecondsSinceEpoch,
        'user': parentUser.toJson(),
      };
  String get tweetWebUrl => 'https://twitter.com/i/web/status/$id';
  // bool get isReply => referenced_tweets.any((element) => element.type == 'replied_to');
  bool get isRetweet => retweet != null;
  // int get firstRetweetId => referenced_tweets.indexWhere((element) => element.type == 'retweeted');
  @override
  String toString() {
    return 'TweetEncodeBase($id,${parentUser.tweetUserId},$text,$createdAt,${retweet?.id})';
  }

  @override
  String get title => '${parentUser.name}(${parentUser.username})';

  @override
  String get imageUrl => parentUser.profileImageUrl;

  @override
  String get url => tweetWebUrl;
}

class TweetUserEncode {
  int? id;
  final int tweetUserId;
  final String username, name;
  String profileImageUrl;
  int sinceId;
  int lastCheck = 0;
  bool invalidUrl = false;

  TweetUserEncode({this.id, required this.tweetUserId, required this.username, required this.name, this.profileImageUrl = '', this.sinceId = 0});
  factory TweetUserEncode.fromJSON(Map<String, dynamic> json) => TweetUserEncode(
        tweetUserId: int.parse(json['id'].toString()),
        username: json['username'] as String,
        name: json['name'] as String,
        profileImageUrl: json['profile_image_url'] as String,
        sinceId: json['since_id'] as int? ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'id': tweetUserId,
        'name': name,
        'profile_image_url': profileImageUrl,
        'tweet_user_id': tweetUserId,
        'username': username,
      };
  @override
  String toString() {
    return 'TweetUserEncode($id,$tweetUserId,$username,$name,$sinceId)';
  }
}
