import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:sqlite3/open.dart';

bool _sqliteSetUp = false;

/// The test host has no `sqlite3.dll` next to the test runner; Windows ships
/// its own build as `winsqlite3.dll`, which has the same C API.
void _setUpSqlite() {
  if (_sqliteSetUp) return;
  _sqliteSetUp = true;
  if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, () {
      try {
        return DynamicLibrary.open('sqlite3.dll');
      } catch (_) {
        return DynamicLibrary.open('winsqlite3.dll');
      }
    });
  }
}

AppDb openTestDb() {
  _setUpSqlite();
  // Every test opens its own in-memory database.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDb.forTesting(NativeDatabase.memory());
}

/// One feed with [count] unread articles titled 'Article 0' .. 'Article n-1',
/// in that order (by pubDate). Returns the feed id.
Future<int> seedArticles(AppDb db, int count) async {
  final feedId = await db.into(db.feed).insert(FeedCompanion.insert(title: 'Feed', url: 'https://example.com/feed'));
  for (var i = 0; i < count; i++) {
    await db.into(db.article).insert(ArticleCompanion.insert(
          parent: feedId,
          title: 'Article $i',
          url: 'https://example.com/$i',
          guid: 'guid-$i',
          pubDate: Value(1000 + i),
          description: Value('Body $i'),
        ));
  }
  return feedId;
}
