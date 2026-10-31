import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_common/frame_decoder.dart';

/// A frame as encodeFrame builds it: the length counts the json's UTF-16 units, the bytes are UTF-8.
List<int> _frame(String json) => utf8.encode('${json.length}:$json');

void main() {
  const a = '{"code":1,"data":{"title":"First: one"}}';
  const b = '{"code":1,"data":{"title":"Second"}}';

  test('encodeFrame builds what the decoder reads back', () {
    final message = {'command': 'article_read', 'id': 7, 'title': 'Blåbær 🦊'};
    final frame = encodeFrame(message);
    expect(frame, startsWith('${jsonEncode(message).length}:'));
    expect(FrameDecoder().add(utf8.encode(frame)).map(jsonDecode), [message]);
  });

  test('one frame in one read', () {
    expect(FrameDecoder().add(_frame(a)), [a]);
  });

  test('two frames in one read', () {
    expect(FrameDecoder().add([..._frame(a), ..._frame(b)]), [a, b]);
  });

  test('the tail of one frame together with the head of the next', () {
    final decoder = FrameDecoder();
    final bytes = [..._frame(a), ..._frame(b)];
    final cut = _frame(a).length - 5;
    expect(decoder.add(bytes.sublist(0, cut)), isEmpty);
    expect(decoder.add(bytes.sublist(cut, cut + 10)), [a]);
    expect(decoder.add(bytes.sublist(cut + 10)), [b]);
    expect(decoder.buffered, 0);
  });

  test('a frame arriving one byte at a time', () {
    final decoder = FrameDecoder();
    final frames = <String>[];
    for (final byte in _frame(a)) {
      frames.addAll(decoder.add([byte]));
    }
    expect(frames, [a]);
  });

  test('a read that splits a multi-byte character, counted in UTF-16 units', () {
    const json = '{"title":"Blåbær og 🦊"}';
    final bytes = _frame(json);
    final decoder = FrameDecoder();
    // Inside 'å' (2 bytes) and inside the emoji (4 bytes)
    final inA = utf8.encode('${json.length}:{"title":"Bl').length + 1;
    final inEmoji = bytes.length - 3;
    expect(decoder.add(bytes.sublist(0, inA)), isEmpty);
    expect(decoder.add(bytes.sublist(inA, inEmoji)), isEmpty);
    expect(decoder.add(bytes.sublist(inEmoji)), [json]);
  });

  test('a bad length header throws', () {
    expect(() => FrameDecoder().add(utf8.encode('x1:{}')), throwsFormatException);
    expect(() => FrameDecoder().add(utf8.encode('{"no":"header at all"}')), throwsFormatException);
  });

  test('too much buffered without a complete frame throws', () {
    expect(() => FrameDecoder(maxBuffered: 100).add(utf8.encode('500:${'x' * 200}')), throwsFormatException);
  });

  test('reset() drops a partial frame', () {
    final decoder = FrameDecoder();
    decoder.add(utf8.encode('500:{"code":1,"data":'));
    decoder.reset();
    expect(decoder.buffered, 0);
    expect(decoder.add(_frame(b)), [b]);
  });

  test('reset() drops half a character', () {
    final decoder = FrameDecoder();
    decoder.add(utf8.encode('5:"').followedBy(utf8.encode('æ').take(1)).toList());
    decoder.reset();
    expect(decoder.add(_frame(b)), [b]);
  });
}
