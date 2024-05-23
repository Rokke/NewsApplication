import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_feed_reader/database/database.dart';
import 'package:rss_feed_reader/screens/widgets/popups/color_picker.dart';
import 'package:rss_feed_reader/utils/popup_card.dart';

final categoryProvider = FutureProviderFamily<CategoryData?, String>((ref, category) {
  final db = ref.watch(rssDatabase);
  return db.fetchCategoryByName(categoryName: category);
});

class CategoryWidget extends ConsumerWidget {
  final String categoryName;
  final int articleId;
  const CategoryWidget(this.articleId, this.categoryName, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryRef = ref.watch(categoryProvider(categoryName));
    // debugPrint('CategoryWidget.build: $categoryRef');
    return categoryRef.when(
      data: (category) {
        // debugPrint('CategoryWidget.build: $categoryName');
        final backgroundColor = category?.color != null ? Color(category!.color!) : Colors.black;
        final textColor = backgroundColor.computeLuminance() < 0.5 ? Colors.white : Colors.black;
        return Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
          child: InkWell(
            onTap: () async {
              final ret = await Navigator.of(context).push(
                HeroDialogRoute(
                  builder: (context) {
                    return CategoryPopup(articleId, category ?? CategoryData(id: 0, name: categoryName));
                  },
                ),
              );
              if (ret is int) {
                final reader = ref.read;
                if (category != null) {
                  await reader(rssDatabase).updateCategory(
                      categoryId: category.id, categoryCompanion: CategoryCompanion(name: drift.Value(categoryName), displayName: drift.Value(category.displayName), color: drift.Value(ret)));
                } else {
                  await reader(rssDatabase).insertCategory(CategoryCompanion.insert(name: categoryName, displayName: drift.Value(categoryName), color: drift.Value(ret)));
                }
                ref.invalidate(categoryProvider(categoryName));
              }
            },
            child: Material(
              color: backgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  margin: const EdgeInsets.all(2),
                  child: Text(
                    category?.displayName ?? categoryName,
                    style: TextStyle(color: textColor, fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      loading: () => Container(),
      error: (err, _) {
        debugPrint('Err: $err');
        return Container(color: Colors.red, child: Text(err.toString()));
      },
    );
  }
}
