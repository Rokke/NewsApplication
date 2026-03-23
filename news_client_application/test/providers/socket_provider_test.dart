import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('socket provider ...', () async {
    final socket = await Socket.connect('localhost', 3344);
    socket.add(utf8.encode('data'));
    socket.close();
    // TODO: Implement test
  });
}
