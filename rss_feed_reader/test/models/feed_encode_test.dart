import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rss_feed_reader/models/xml_mapper/channel_mapper.dart';
import 'package:xml/xml.dart';

void main() {
  test('feed encode ...', () async {
    final artText = File('D:\\Temp\\test.raw').readAsStringSync();
    final art = artText.split(',').map((e) => e.trim()).toList();
    expect(art[3], 'Nature & Environment');
  });
  test('Read the Feed from the file /data/engageditem.xml', () async {
    final body = File('test/data/engageditem.xml').readAsStringSync();
    final xml = XmlDocument.parse(body);
    final item = ChannelMapper.fromXML(xml.rootElement);
    expect(item.category, 'Information Technology,Software,Mobile Apps,Technology & Electronics,Handheld & Connected Devices');
    // expect(item.items.length, 10);
    // expect(item.items.first.category, 'Information Technology,Software,Mobile Apps,Technology & Electronics,Handheld & Connected Devices');
  });
}
