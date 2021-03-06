import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_common/tweet_encode.dart';
import 'package:rss_feed_reader/providers/tweet_list.dart';
import 'package:rss_feed_reader/utils/color_constants.dart';
import 'package:rss_feed_reader/utils/misc_functions.dart';

class TwitterWidget extends ConsumerWidget {
  const TwitterWidget({Key? key}) : super(key: key);
  static const double twitterListWidth = 400;

  static Widget tweetContainer(BuildContext context, Reader read, TweetEncodeBase tweet, {bool isRetweet = false}) => Stack(
        children: [
          Positioned(
            child: Container(
              margin: const EdgeInsets.only(bottom: 5, left: 25),
              decoration: BoxDecoration(
                border: Border.all(width: 2),
                borderRadius: BorderRadius.circular(5),
                color: tweet.isRetweet ? ColorContants.bodyTweetRetweet : ColorContants.bodyTweet,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    constraints: const BoxConstraints.tightFor(width: twitterListWidth - 80),
                    color: tweet.isRetweet ? ColorContants.titleTweetRetweet : ColorContants.titleTweet,
                    child: Row(
                      children: [
                        Flexible(child: Center(child: Text('${tweet.parentUser.name}(${tweet.parentUser.username})', style: Theme.of(context).textTheme.subtitle2))),
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Text(
                            smartDateTime(tweet.createdAt),
                            style: Theme.of(context).textTheme.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tweet.isRetweet) tweetContainer(context, read, tweet.retweet!, isRetweet: true),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        constraints: const BoxConstraints.tightFor(width: twitterListWidth - 80),
                        margin: const EdgeInsets.only(left: 2),
                        child: Linkify(
                          text: tweet.text,
                          onOpen: (link) => launchURL(link.text),
                          style: Theme.of(context).textTheme.caption,
                        ),
                      ),
                      if (!isRetweet)
                        ClipOval(
                          child: Container(
                            height: 35,
                            width: 35,
                            decoration: BoxDecoration(
                              color: Colors.green[900],
                            ),
                            child: IconButton(
                              onPressed: () => read(providerTweetHeader).removeTweet(tweet.id),
                              icon: const Icon(Icons.playlist_add_check),
                              color: Colors.green[100],
                              splashRadius: 20,
                              iconSize: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (tweet.parentUser.profileImageUrl.isNotEmpty)
            Positioned(
              child: ClipOval(
                child: GestureDetector(
                  onTap: () => launchURL(tweet.tweetWebUrl),
                  child: CachedNetworkImage(
                    imageUrl: tweet.parentUser.profileImageUrl,
                    height: 35,
                    fit: BoxFit.scaleDown,
                    placeholder: (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      debugPrint('tweetUserContainer-invalidProfilePic(${tweet.parentUser.username}, $url,$error)');
                      if (!tweet.parentUser.invalidUrl) {
                        tweet.parentUser.invalidUrl = true;
                        read(providerTweetHeader).checkAndUpdateUserInfo(tweet.parentUser);
                      }
                      return const Icon(Icons.error, color: Colors.red);
                    },
                  ),
                ),
              ),
            ),
        ],
      );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twitterHead = ref.watch(providerTweetHeader);
    debugPrint('${twitterHead.tweets.length}, twitterHead.fetchUserInfo(twitterHead.tweets[index].tweetUserId)');
    return AnimatedList(
      reverse: true,
      initialItemCount: twitterHead.tweets.length,
      itemBuilder: (BuildContext context, int index, animation) {
        return SizeTransition(sizeFactor: animation, child: tweetContainer(context, ref.read, twitterHead.tweets[index]));
      },
      key: twitterHead.tweetKey,
    );
  }
}
