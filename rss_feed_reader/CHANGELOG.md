# Changelog — rss_feed_reader

Every fix or feature adds a line under `## Unreleased`, ending with its issue
number. `tool/release.dart` moves them under the released version.

## Unreleased

- Frame client commands as `<length>:<json>` on the server too (#13)
- Log the freeze and refresh the window on wake (#15)
- Select nothing after marking the last article as read (#19)
