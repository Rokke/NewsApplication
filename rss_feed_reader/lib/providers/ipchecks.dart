import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';

final providerIPChecks = Provider<IPChecks?>((ref) {
  final appConfig = ref.watch(providerConfig);
  if (appConfig.logFilepath.isNotEmpty) return IPChecks.load(appConfig.logFilepath);
  return null;
});

class IPChecks {
  final _log = Logger('IPChecks');
  final List<IPCheckAddress> ips;
  final String _filename;
  final DateTime? lastUpdate;

  IPChecks._(this._filename, {required this.ips, required this.lastUpdate});
  factory IPChecks.load(String path) {
    final filename = '$path/rss_ipconnections.json';
    final file = File(filename);
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync());
      return IPChecks._(
        filename,
        ips: (json['ips'] as List<dynamic>).map((entry) => IPCheckAddress.fromJson(entry as Map<String, dynamic>)).toList(),
        lastUpdate: DateTime.fromMillisecondsSinceEpoch(json['lastUpdate'] ?? '0'),
      );
    }
    return IPChecks._(filename, ips: ['45.', '89'].map((e) => IPCheckAddress.fromJson({'ip': e, 'ok': false, 'block': true})).toList(), lastUpdate: DateTime.now());
  }
  void save() {
    File(_filename).writeAsStringSync(jsonEncode(toMap));
  }

  Map<String, dynamic> get toMap => {'version': '1.0', 'ips': ips.map((e) => e.toMap).toList(), 'lastUpdate': lastUpdate?.millisecondsSinceEpoch};
  IPCheckAddress? checkConnectionBlocked(Socket socket) {
    final found = _findCheck(socket);
    if (found != null) {
      found.increaseCount();
      save();
    }
    return found;
  }

  IPCheckAddress? _findCheck(Socket socket) {
    for (var element in ips) {
      if (element.isCorrectIP(socket)) return element;
    }
    return null;
  }

  void ipConnectedOK(IPCheckAddress ipCheck) {
    if (ipCheck.connectedOK()) {
      _log.info('ipConnectedOK($ipCheck)-first time');
      save();
    }
  }

  void blockIP(IPCheckAddress ipCheck) {
    _log.warning('blockIP($ipCheck)');
    ipCheck.blockAddress();
    save();
  }

  bool addNewConnection(Socket socket) {
    _log.info('addNewConnection(${socket.remoteAddress}:${socket.remotePort})');
    final newIPCheck = IPCheckAddress.fromSocket(socket);
    final found = ips.firstWhere((element) => element == newIPCheck, orElse: IPCheckAddress.empty);
    if (found.ip.isEmpty) {
      ips.add(newIPCheck);
      save();
      return true;
    }
    return false;
  }
}

class IPCheckAddress {
  final String ip;
  bool ok;
  bool block;
  int count = 0;
  DateTime? lastConnected;

  IPCheckAddress._({required this.ip, required this.ok, required this.block, required this.lastConnected});
  void increaseCount() {
    lastConnected = DateTime.now();
    count++;
  }

  Map<String, dynamic> get toMap => {
        'ip': ip,
        'ok': ok,
        'block': block,
        'lastConnected': lastConnected?.millisecondsSinceEpoch,
      };
  void blockAddress() {
    ok = false;
    block = true;
  }

  bool connectedOK() {
    if (!ok) {
      ok = true;
      return true;
    }
    return false;
  }

  factory IPCheckAddress.empty() => IPCheckAddress._(ip: '', ok: false, block: false, lastConnected: DateTime.fromMillisecondsSinceEpoch(0));
  factory IPCheckAddress.fromSocket(Socket socket, {bool ok = false, bool block = false}) => IPCheckAddress._(ip: _fetchAddress(socket), ok: ok, block: block, lastConnected: DateTime.now());
  factory IPCheckAddress.fromJson(Map<String, dynamic> json) => IPCheckAddress._(
        ip: json['ip'],
        ok: json['ok'] ?? false,
        block: json['block'] ?? false,
        lastConnected: DateTime.fromMillisecondsSinceEpoch(json['lastConnected'] ?? 0),
      );
  static String _fetchAddress(Socket socket) => socket.remoteAddress.address;
  bool isCorrectIP(Socket socket) => _fetchAddress(socket).startsWith(ip);
  @override
  bool operator ==(Object other) => identical(this, other) || (other is IPCheckAddress && runtimeType == other.runtimeType && (ip.startsWith(other.ip) || other.ip.startsWith(ip)));

  @override
  int get hashCode => ip.hashCode;
  @override
  String toString() => 'IPCheck($ip,$ok,$block,$lastConnected)';
}
