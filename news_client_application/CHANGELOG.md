# Changelog — news_client_application

Every fix or feature adds a line under `## Unreleased`, ending with its issue
number. `tool/release.dart` moves them under the released version.

## Unreleased

- Keep the screen following when replies arrive together (#8)
- Keep the home screen on the new socket after saving Settings (#9)
- Queue socket writes so flushes never overlap (#12)
- Frame commands as `<length>:<json>` on both sides (#13)
