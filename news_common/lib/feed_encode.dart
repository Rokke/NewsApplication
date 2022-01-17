import 'package:flutter/material.dart';
import 'package:news_common/news_common.dart';

class FeedEncodeBase {
  FeedEncodeBase({required this.title, required this.url, required this.ttl, required this.lastCheck, required this.lastBuildDate, required this.pubDate, this.description, this.link, this.id, this.category, this.feedFav, this.language});
  static const TTL_DEFAULT = 30;
  int? id;
  final int lastBuildDate, pubDate;
  String title, url;
  final String? category, link, language;
  String? feedFav, description, lastError;
  int ttl, lastCheck;
  int get earliestMillisecondsSinceEpoch => lastCheck + ttl * 60000;
  factory FeedEncodeBase.fromJson(Map<String, dynamic> json) {
    try {
      return FeedEncodeBase(
        title: json['title'],
        url: json['url'],
        ttl: json['ttl'],
        lastCheck: json['lastCheck'],
        lastBuildDate: json['lastBuildDate'],
        pubDate: json['pubDate'],
        description: json['description'],
        link: json['link'],
        id: json['id'],
        category: json['category'],
        feedFav: json['feedFav'],
        language: json['language'],
      );
    } catch (err) {
      debugPrint('ERR: $json');
      throw err;
    }
  }
  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'ttl': ttl,
        'lastCheck': lastCheck,
        'lastBuildDate': lastBuildDate,
        'pubDate': pubDate,
        'description': description,
        'link': link,
        'id': id,
        'category': category,
        'language': language,
        'feedFav': feedFav,
      };
  // Widget? fetchFeedFavImage({double? height, double? width}) => feedFav == null
  //     ? null
  //     : CachedNetworkImage(
  //         imageUrl: feedFav!,
  //         fit: BoxFit.scaleDown,
  //         alignment: Alignment.center,
  //         width: width,
  //         height: height,
  //         errorWidget: (_, __, ___) => Container(),
  //       );
  @override
  String toString() {
    return 'FeedEncodeBase($id,$title,$url,$link,$lastBuildDate)';
  }
}

class ArticleEncodeBase extends NewsItem {
  ArticleEncodeBase({required this.id, required this.parent, required this.title, required this.pubDate, required this.url, this.creator, this.description, this.encoded, this.category, required this.guid, this.active = true});
  int id;
  final String title, guid, url;
  final String? creator, encoded, category;
  String? description;
  final FeedEncodeBase parent;
  final int pubDate;
  bool active;
  factory ArticleEncodeBase.fromJson(Map<String, dynamic> json) {
    // Used by client
    try {
      // debugPrint('TEST: $json');
      return ArticleEncodeBase(
        id: json['id'],
        parent: FeedEncodeBase.fromJson(json['parent']),
        title: json['title'],
        pubDate: json['pubDate'],
        url: json['url'],
        guid: json['guid'],
        creator: json['creator'],
        description: json['description'],
        encoded: json['encoded'],
        category: json['category'],
        active: json['active'],
      );
    } catch (err) {
      debugPrint('Err: $json');
      throw err;
    }
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'parent': parent.toJson(),
        'title': title,
        'guid': guid,
        'url': url,
        'description': description,
        'creator': creator,
        'encoded': encoded,
        'category': category,
        'pubDate': pubDate,
        'active': active,
      };
  @override
  String toString() {
    return 'ArticleEncodeBase($id,$title,$guid,${parent.id},$creator)';
  }

  @override
  String get text => description ?? '';

  @override
  String? get imageUrl => parent.feedFav;
}
