import 'dart:convert';

/// Splits the server's byte stream into `<length>:<json>` frames, where length counts the json's UTF-16 units.
///
/// A TCP read can hold several frames, part of one, or the tail of one and the head of the next, and can cut a
/// multi-byte character in two; everything not yet complete stays buffered for the next [add].
class FrameDecoder {
  FrameDecoder({this.maxBuffered = 5 * 1024 * 1024}) {
    reset();
  }

  /// Most characters held while waiting for a frame to complete; more means the stream is garbage.
  final int maxBuffered;
  // A length header is a few digits; anything longer without a ':' is not one
  static const _maxHeader = 12;
  final _decoded = StringBuffer();
  late ByteConversionSink _bytes;
  String _pending = '';

  /// Number of characters waiting for the rest of their frame.
  int get buffered => _pending.length + _decoded.length;

  /// Adds [data] and returns the json of every frame it completed, in order. Throws [FormatException] on a bad header
  /// or when more than [maxBuffered] characters pile up.
  List<String> add(List<int> data) {
    _bytes.add(data);
    if (_decoded.isNotEmpty) {
      _pending += _decoded.toString();
      _decoded.clear();
    }
    final frames = <String>[];
    var start = 0;
    while (true) {
      final colon = _pending.indexOf(':', start);
      if (colon < 0) {
        if (_pending.length - start > _maxHeader) throw FormatException('No length header', _preview(start));
        break;
      }
      final length = int.tryParse(_pending.substring(start, colon));
      if (length == null || length < 0) throw FormatException('Invalid length header', _preview(start));
      final end = colon + 1 + length;
      if (end > _pending.length) break;
      frames.add(_pending.substring(colon + 1, end));
      start = end;
    }
    _pending = _pending.substring(start);
    if (_pending.length > maxBuffered) throw FormatException('${_pending.length} characters buffered without a complete frame');
    return frames;
  }

  /// Drops a partial frame and any half-received character, e.g. when the connection is lost.
  void reset() {
    _decoded.clear();
    _pending = '';
    _bytes = const Utf8Decoder().startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
  }

  String _preview(int start) => _pending.substring(start, (start + 40).clamp(start, _pending.length));
}
