import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:news_common/news_common.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/xml_mapper/channel_mapper.dart';
import 'package:rss_feed_reader/models/xml_mapper/item_mapper.dart';

class FeedEncode extends FeedEncodeBase {
  List<ArticleActiveRead> activeArticles = [];
  FeedEncode(
      {required super.title,
      required super.url,
      required super.ttl,
      required super.lastCheck,
      required super.lastBuildDate,
      required super.pubDate,
      super.description,
      super.link,
      super.id,
      super.category,
      super.feedFav,
      super.language});
  factory FeedEncode.fromChannel(ChannelMapper channel, String url) => FeedEncode(
        title: channel.title!,
        url: url,
        ttl: channel.ttl ?? FeedEncodeBase.ttlDefault,
        lastCheck: DateTime.now().millisecondsSinceEpoch,
        lastBuildDate: channel.lastBuildDate ?? 0,
        pubDate: channel.pubDate ?? 0,
        category: channel.category,
        link: channel.link ?? channel.atomlink,
        feedFav: channel.image,
      );
  factory FeedEncode.fromDB(FeedData data) {
    try {
      return FeedEncode(
        title: data.title,
        url: data.url,
        ttl: data.ttl ?? 30,
        lastCheck: data.lastCheck ?? 0,
        lastBuildDate: data.lastBuildDate ?? DateTime.now().millisecondsSinceEpoch,
        pubDate: data.pubDate ?? 0,
        description: data.description,
        link: data.link,
        id: data.id,
        category: data.category,
        language: data.language,
        feedFav: data.feedFav,
      );
    } catch (err) {
      debugPrint('FeedEncode.fromDB exception: $data');
      rethrow;
    }
  }
  FeedCompanion get toInsertCompanion => FeedCompanion(
        title: Value(title),
        description: Value(description),
        category: Value(category),
        ttl: Value(ttl),
        pubDate: Value(pubDate),
        link: Value(link),
        url: Value(url),
        lastBuildDate: Value(lastBuildDate),
        language: Value(language),
      );

  @override
  String toString() {
    return 'FeedEncode($id,$title,$url,$link,${DateTime.fromMillisecondsSinceEpoch(lastBuildDate)})';
  }
}

class ArticleActiveRead {
  final int id;
  final String url;
  int lastFoundEpoch;

  ArticleActiveRead({required this.id, required this.url, required this.lastFoundEpoch});
}

class ArticleEncode extends ArticleEncodeBase {
  ArticleEncode(
      {int? id,
      required super.parent,
      required super.title,
      required super.pubDate,
      required super.url,
      super.creator,
      super.description,
      super.encoded,
      super.category,
      required super.guid,
      super.active})
      : super(id: id ?? 0);
  Future<String?> articleDescription(AppDb db) async {
    // debugPrint('articleDescription($id): ${(await (db.select(db.article)..where((tbl) => tbl.id.equals(id))).getSingleOrNull())?.description}, $description');
    return description ??= (await (db.select(db.article)..where((tbl) => tbl.id.equals(id))).getSingleOrNull())?.description ?? '';
  }

  static String _removeDataTag(String? text) => text == null ? '' : RegExp(r'<!\[CDATA\[(.*)\]\]>', multiLine: true).firstMatch(text)?.group(1) ?? text;
  factory ArticleEncode.fromChannelItem(ItemMapper item, FeedEncode feed, {Logger? log}) {
    try {
      return ArticleEncode(
        parent: feed,
        title: item.title!,
        guid: item.guid ?? item.link!,
        url: item.link!,
        description: _removeDataTag(item.description),
        creator: item.author,
        encoded: item.encoded,
        category: item.category,
        pubDate: item.pubDate ?? feed.lastCheck,
      );
    } catch (err) {
      log?.warning('ArticleEncode.fromChannelItem exception: $item', err);
      rethrow;
    }
  }

  factory ArticleEncode.fromDB(ArticleData data, List<FeedEncode> feeds) {
    try {
      return ArticleEncode(
        id: data.id,
        parent: feeds.firstWhere((element) => element.id == data.parent),
        title: data.title,
        guid: data.guid,
        url: data.url,
        creator: data.creator,
        encoded: data.encoded,
        category: data.category,
        pubDate: data.pubDate ?? 0,
        active: data.active,
      );
    } catch (err) {
      debugPrint('ArticleEncode.fromDB exception: $data');
      rethrow;
    }
  }
  ArticleCompanion get toInsertCompanion => ArticleCompanion(
        parent: Value(parent.id!),
        title: Value(title),
        url: Value(url),
        guid: Value(guid),
        description: Value(description),
        creator: Value(creator),
        pubDate: Value(pubDate),
        category: Value(category),
        encoded: Value(encoded),
        active: Value(active),
      );
  @override
  String toString() {
    return 'ArticleEncode($id,$title,$guid,${parent.id},$creator,${'${active ? '' : '!'}active'})';
  }
}

class FeedFullDecode {
  final FeedEncode feed;
  final List<ArticleEncode> articles;
  final String url;

  FeedFullDecode({required this.feed, required this.articles, required this.url});
  factory FeedFullDecode.fromChannel(ChannelMapper channel, String url, {FeedEncode? parentFeed, Logger? log}) {
    try {
      final newFeed = FeedEncode.fromChannel(channel, url);
      return FeedFullDecode(
          feed: newFeed, articles: channel.items.where((element) => element.link != null).map((item) => ArticleEncode.fromChannelItem(item, parentFeed ?? newFeed, log: log)).toList(), url: url);
    } catch (err) {
      log?.warning('FeedFullDecode.fromChannel($url)', err);
      rethrow;
    }
  }
}

abstract class ArticleTableStatus {
  static const read = -1;
  static const unread = 0;
  static const favorite = 1;
}
