import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rss_feed_reader/database/database.dart';

class CategoryPopup extends StatelessWidget {
  final CategoryData category;
  final int id;
  const CategoryPopup(this.id, this.category, {Key? key}) : super(key: key);
  static const heroTag = 'popupHeroCategoryPopup';

  @override
  Widget build(BuildContext context) {
    int? _color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Hero(
          tag: '$heroTag$id${category.name}',
          child: Material(
            color: Colors.purple,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints.tightFor(width: 600, height: 500),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Velg farge for ${category.name}'),
                      LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 500 ? ColorPicker(pickerColor: category.color != null ? Color(category.color!) : Colors.black, onColorChanged: (color) => _color = color.value) : Container()),
                      ElevatedButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Endre farge')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
