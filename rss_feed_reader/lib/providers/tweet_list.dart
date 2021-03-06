import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:moor/moor.dart';
import 'package:news_common/tweet_encode.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/models/tweet_encoding.dart';
import 'package:rss_feed_reader/providers/network.dart' as network;
import 'package:rss_feed_reader/screens/widgets/twitter_widget.dart';
import 'package:rss_feed_reader/secret.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';

final providerTweetHeader = Provider<TweetListHeader>((ref) {
  return TweetListHeader(ref.read);
});
const int twitterCheckInterval = 600000;

class TweetListHeader {
  static final _log = Logger('TweetListHeader');
  final _listTweetKey = GlobalKey<AnimatedListState>(), _listTweetUserKey = GlobalKey<AnimatedListState>();
  // final AppDb db;
  // final List<int> readIds = [];
  final Reader _read;
  final List<TweetEncode> tweets = [];
  final List<TweetUserEncode> tweetUsers = [];
  bool isInitialized = false;

  TweetListHeader(this._read) {
    _init();
  }
  Future<void> _init() async {
    isInitialized = false;
    final db = _read(rssDatabase);
    tweetUsers.addAll((await (db.select(db.tweetUser)..orderBy([(tbl) => OrderingTerm.asc(tbl.username)])).get()).map((e) => e.toTweetUserEncode()));
    debugPrint('_init(), tweetusers from db: ${tweetUsers.length}');
    final undreadTweets = await db.tweets();
    debugPrint('_init(), unread tweets from db: ${undreadTweets.length}');
    for (var i = 0; i < undreadTweets.length; i++) {
      _insertNewTweetToList(TweetEncode.fromDB(undreadTweets[i], tweetUsers, undreadTweets[i].retweetId != null ? (await (db.select(db.retweet)..where((tbl) => tbl.tweetId.equals(undreadTweets[i].retweetId))).getSingleOrNull()) : null));
    }
    // tweets.addAll(.map((e) => await _createTweetObject(e)).toList());
    // tweets.addAll(.map((e) => TweetEncode.fromDB(e, tweetUsers, e.retweetId!=null?await (db.select(db.retweet)..where((tbl)=>tbl.tweetId.equals(e.retweetId))) :null)));
    isInitialized = true;
  }

  // void _newTweetUserListReceived(List<TweetUserData> newTweetUserList) {
  //   debugPrint('_newTweetUserListReceived($newTweetUserList)');
  //   if (tweetUsers.length == 0)
  //     tweetUsers.addAll(newTweetUserList);
  //   else {
  //     final List<int> idsThatWasNotFound = tweetUsers.map((e) => e.id!).toList();
  //     newTweetUserList.forEach((newUser) {
  //       final foundExistingUserIndex = tweetUsers.indexWhere((existingUser) => existingUser.tweetUserId == newUser.tweetUserId);
  //       if (foundExistingUserIndex >= 0) {
  //         idsThatWasNotFound.remove(tweetUsers[foundExistingUserIndex]);
  //       } else
  //         _addNewSortedUser(newUser);
  //     });
  //     idsThatWasNotFound.forEach((id) {
  //       final foundIndex = tweetUsers.indexWhere((element) => element.id! == id);
  //       if (foundIndex >= 0) {
  //         _listTweetUserKey.currentState?.removeItem(foundIndex, (context, animation) => TwitterUserWidget.tweetUserContainer(context, tweetUsers[foundIndex]));
  //         tweetUsers.removeAt(foundIndex);
  //       }
  //     });
  //   }
  // }

  int _addNewSortedUser(TweetUserEncode newUser) {
    final sortIndex = tweetUsers.indexWhere((existingUser) => existingUser.username.compareTo(newUser.username) > 0);
    if (sortIndex >= 0) {
      tweetUsers.insert(sortIndex, newUser);
      _listTweetUserKey.currentState?.insertItem(sortIndex - 1);
      return sortIndex;
    } else {
      tweetUsers.add(newUser);
      _listTweetUserKey.currentState?.insertItem(tweetUsers.length - 1);
    }
    return tweetUsers.length - 1;
  }

  Future<bool> checkAndUpdateTweet({bool isAuto = false}) async {
    if (twitterBearerToken.isNotEmpty) {
      final tweetUser = tweetUsers.fold(
        null,
        (TweetUserEncode? previousValue, element) => previousValue == null
            ? element
            : element.id != null && element.lastCheck < previousValue.lastCheck
                ? element
                : previousValue,
      );
      if (tweetUser?.id != null) {
        if (tweetUser!.lastCheck + twitterCheckInterval < DateTime.now().millisecondsSinceEpoch) {
          await refreshTweetsFromUser(tweetUser, isAuto: isAuto);
          return true;
        } else {
          _log.fine('No need to update twitter: $tweetUser');
        }
      } else {
        _log.warning('checkAndUpdateTweet()-illegal tweet: $tweetUser');
      }
    } else {
      _log.warning('checkAndUpdateTweet()-illegal bearer');
    }
    return false;
  }

  Future<TweetFullDecode?> fetchUserTweets(TweetUserEncode tweetUserData) async {
    assert(tweetUserData.id != null, 'Invalid tweetUser: $tweetUserData');
    final url = 'https://api.twitter.com/2/users/${tweetUserData.tweetUserId}/tweets?user.fields=id,username,name,profile_image_url&expansions=referenced_tweets.id.author_id&tweet.fields=created_at&exclude=replies' + (tweetUserData.sinceId > 0 ? '&since_id=${tweetUserData.sinceId}' : '');
    _log.info('fetchUserTweets($tweetUserData):$url');
    final response = await network.getResponse(url, headers: {'Authorization': 'Bearer $twitterBearerToken'});
    if (response != null && response['data'] is List) {
      return TweetFullDecode(response, tweetUserData);
    }
    return null;
  }

  Future<void> checkAndUpdateUserInfo(TweetUserEncode tweet) async {
    _log.info('checkAndUpdateUserInfo($tweet)');
    final found = await fetchTweetUsername(id: tweet.tweetUserId);
    if (found != null) {
      if (found.profileImageUrl != tweet.profileImageUrl) {
        _log.warning('checkAndUpdateUserInfo-changed: ${found.profileImageUrl}');
        final db = _read(rssDatabase);
        (db.update(db.tweetUser)..where((tbl) => tbl.tweetUserId.equals(tweet.tweetUserId))).write(TweetUserCompanion(profileUrl: Value(found.profileImageUrl))).then((value) => _log.fine('checkAndUpdateUserInfo-changed: $value'));
        tweet.profileImageUrl = found.profileImageUrl;
        tweet.invalidUrl = false;
      }
    }
  }

  Future<TweetUserEncode?> fetchTweetUsername({int? id, String? username}) async {
    _log.fine('fetchTweetUsername($id, $username)');
    assert(id != null || username != null, 'fetchTweetUsername-id or username must be valid');
    final url = 'https://api.twitter.com/2/users/${id ?? "by/username/$username"}?user.fields=profile_image_url';
    final response = await network.getResponse(url, headers: {'Authorization': 'Bearer $twitterBearerToken'});
    if (response != null && response['data'] != null) {
      try {
        _log.info('fetchTweetUsername()-Adding user: ${response['data']}');
        return TweetUserEncode.fromJSON(response['data'] as Map<String, dynamic>);
      } catch (err) {
        _log.warning('fetchTweetUsername($url)-Error decode: $response, $err');
      }
    } else {
      _log.warning('fetchTweetUsername($url)-Err response: $response');
    }
    return null;
  }

  Future<void> refreshTweetsFromUser(TweetUserEncode tweetUser, {bool isAuto = false}) async {
    tweetUser.lastCheck = DateTime.now().millisecondsSinceEpoch;
    final allTweetsFromUser = await fetchUserTweets(tweetUser);
    final hadTweets = tweets.isNotEmpty;
    if (allTweetsFromUser != null) {
      await updateTweetsFromUser(allTweetsFromUser);
      final lastId = allTweetsFromUser.tweets.fold(tweetUser.sinceId, (int previousValue, element) => element.id > previousValue ? element.id : previousValue);
      if (lastId > tweetUser.sinceId) {
        debugPrint('since_id update: $lastId(${tweetUser.sinceId})');
        tweetUser.sinceId = lastId;
        final db = _read(rssDatabase);
        (db.update(db.tweetUser)..where((tbl) => tbl.tweetUserId.equals(tweetUser.tweetUserId))).write(TweetUserCompanion(sinceId: Value(lastId))).then((value) => debugPrint('Updated db: $value'));
        if (!hadTweets) playSound(soundFile: SOUND_FILE.soundNewTweet);
      } else {
        debugPrint('since_id, no update: $lastId');
      }
    }
  }

  Future<void> addNewUser(TweetUserEncode newUser) async {
    if (!tweetUsers.any((element) => element.id == newUser.id)) {
      _addNewSortedUser(newUser);
      newUser.id = await _read(rssDatabase).insertTweetUser(newUser.toTweetUserCompanionInsert());
    } else {
      debugPrint('addNewUser($newUser)-exist');
    }
  }

  Future<void> updateTweetsFromUser(TweetFullDecode tweetFullDecode) async {
    // var newItems = 0;
    for (var i = 0; i < tweetFullDecode.tweets.length; i++) {
      // if (!readIds.contains(tweetFullDecode.tweets[i].id)) { This can now be ignored since using since_id in query
      if (!tweets.any((element) => tweetFullDecode.tweets[i].id == element.id)) {
        // if (newItems++ == 0 && Platform.isWindows) debugPrint('powershellBeep()');
        _log.info('updateTweetsFromUser(${tweetFullDecode.tweets[i]})-new');
        // tweets.insert(0, newTweetsReceived[i]);
        _read(rssDatabase).insertTweet(tweetFullDecode.tweets[i]).then((value) => _insertNewTweetToList(tweetFullDecode.tweets[i]));
        // _listTweetKey.currentState!.insertItem(tweets.length - 1, duration: Duration(milliseconds: 500));
        // await Future.delayed(Duration(milliseconds: 200));
      } else {
        _log.fine('updateTweetsFromUser(${tweetFullDecode.tweets[i]})-in list');
      }
      // } else
      //   _log.fine('updateTweetsFromUser(${tweetFullDecode.tweets[i]})-ignored');
    }
  }

  void _insertNewTweetToList(TweetEncode newTweet, {int index = -1}) {
    if (index < 0) {
      tweets.add(newTweet);
    } else {
      tweets.insert(index, newTweet);
    }
    _listTweetKey.currentState!.insertItem(index < 0 ? tweets.length - 1 : index, duration: const Duration(milliseconds: 500));
  }

  Future<void> removeTweet(int twitterId) async {
    _read(rssDatabase).updateTweetStatus(twitterId);
    final index = tweets.indexWhere((element) => element.id == twitterId);
    if (index >= 0) {
      _log.info('removeTweet($twitterId)-removed');
      final cachedItem = tweets[index];
      _listTweetKey.currentState!.removeItem(index, (context, animation) => SizeTransition(sizeFactor: animation, child: TwitterWidget.tweetContainer(context, _read, cachedItem)), duration: const Duration(milliseconds: 500));
      tweets.removeAt(index);
    } else {
      _log.warning('removeTweet($twitterId)-Invalid id');
    }
  }

  TweetUserEncode? fetchUserInfo(int tweetUserId) => tweetUsers.firstWhereOrNull((element) => element.tweetUserId == tweetUserId);

  GlobalKey<AnimatedListState> get tweetKey => _listTweetKey;
  GlobalKey<AnimatedListState> get tweetUserKey => _listTweetUserKey;
}
