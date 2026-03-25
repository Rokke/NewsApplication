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
  final List<IPBlockEntry> blockedPrefixes;
  final String _filename;

  IPChecks._(this._filename, {required this.blockedPrefixes});

  factory IPChecks.load(String path) {
    final filename = '$path/rss_ipblocklist.json';
    final file = File(filename);
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync());
      return IPChecks._(
        filename,
        blockedPrefixes: (json['blocked'] as List<dynamic>).map((e) => IPBlockEntry.fromJson(e as Map<String, dynamic>)).toList(),
      );
    }
    // Also try loading legacy file format
    final legacyFile = File('$path/rss_ipconnections.json');
    if (legacyFile.existsSync()) {
      final json = jsonDecode(legacyFile.readAsStringSync());
      final entries = (json['ips'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .where((e) => e['block'] == true)
          .map((e) => IPBlockEntry(prefix: e['ip'] as String, reason: 'migrated from legacy'))
          .toList();
      final checks = IPChecks._(filename, blockedPrefixes: entries);
      checks.save();
      return checks;
    }
    // Default blocked prefixes
    return IPChecks._(filename, blockedPrefixes: [
      IPBlockEntry(prefix: '45.', reason: 'known scanner range'),
      IPBlockEntry(prefix: '89.', reason: 'known scanner range'),
    ])
      ..save();
  }

  void save() {
    File(_filename).writeAsStringSync(jsonEncode({
      'version': '2.0',
      'blocked': blockedPrefixes.map((e) => e.toMap).toList(),
    }));
  }

  /// Returns true if the socket's IP matches a blocked prefix
  bool isBlocked(Socket socket) {
    final addr = socket.remoteAddress.address;
    for (final entry in blockedPrefixes) {
      if (addr.startsWith(entry.prefix)) {
        _log.warning('Connection from $addr blocked (matches prefix: ${entry.prefix}, reason: ${entry.reason})');
        return true;
      }
    }
    return false;
  }

  IPBlockEntry? checkConnectionBlocked(Socket socket) {
    final addr = socket.remoteAddress.address;
    for (final entry in blockedPrefixes) {
      if (addr.startsWith(entry.prefix)) {
        _log.warning('Connection from $addr blocked (prefix: ${entry.prefix})');
        return entry;
      }
    }
    return null;
  }
}

class IPBlockEntry {
  final String prefix;
  final String reason;
  bool block;

  IPBlockEntry({required this.prefix, this.reason = '', this.block = true});

  factory IPBlockEntry.fromJson(Map<String, dynamic> json) => IPBlockEntry(
        prefix: json['prefix'] as String,
        reason: json['reason'] as String? ?? '',
      );

  Map<String, dynamic> get toMap => {
        'prefix': prefix,
        'reason': reason,
      };

  @override
  String toString() => 'IPBlock($prefix, $reason)';
}
