# rss_feed_reader

Reader that shows you RSS feeds and tweets (with quotes and retweet) from gived sources

## Getting Started

When starting it up you can add the RSS feeds and/or tweet users that you want to follow.
You must create a secret.dart file with a tweeter bearer like "const twitterBearerToken = 'bearerToken';"
Check: "https://developer.twitter.com/en/docs/authentication/oauth-2-0/bearer-tokens"

### Version 1.1.0

Added server socket listener that will listen for client that can fetch unread feeds/tweets
Client not yet created/started on

### Version 1.0.1

Tweets are stored localy and only requesting new tweets from the given users
Tweets and Feeds have a data layer between UI and database
Animated lists for new/removed items
