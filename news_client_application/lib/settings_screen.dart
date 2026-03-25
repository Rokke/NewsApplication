import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:news_client_application/providers/config_provider.dart';
import 'package:news_client_application/providers/log_provider.dart';
import 'package:statssender/statssender.dart';

final _log = Logger('SettingsScreen');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final txtSecret = TextEditingController();
  final txtSocketInternal = TextEditingController();
  final txtSocketExternal = TextEditingController();
  bool _isSendingLog = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(providerConfig);
    txtSecret.text = config.socketSecret;
    txtSocketInternal.text = config.socketServerInternal;
    txtSocketExternal.text = config.socketServerExternal;
  }

  @override
  void dispose() {
    txtSecret.dispose();
    txtSocketInternal.dispose();
    txtSocketExternal.dispose();
    super.dispose();
  }

  void _save(ApplicationConfiguration config) {
    _log.info('Settings saved');
    config.updateSettings(socketSecret: txtSecret.text, socketServerInternal: txtSocketInternal.text, socketServerExternal: txtSocketExternal.text);
    Navigator.of(context).pop();
  }

  Future<void> _sendLog() async {
    final logService = ref.read(logServiceProvider);
    final logPath = logService.logFilePath;
    if (logPath == null) {
      _log.warning('No log file available to send');
      return;
    }

    setState(() => _isSendingLog = true);
    _log.info('Sending log file: $logPath');

    try {
      await logService.flush();
      await StatsService.zipAndSendFile(
        applicationName: 'NewsClient',
        filenames: [logPath],
        isDevelopment: kDebugMode,
      );
      _log.info('Log file sent successfully');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log sent')));
      }
    } catch (e, stackTrace) {
      _log.severe('Failed to send log file', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send log: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSendingLog = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.read(providerConfig);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(controller: txtSecret, decoration: const InputDecoration(labelText: 'Server secret')),
            const SizedBox(height: 20),
            TextField(controller: txtSocketInternal, decoration: const InputDecoration(labelText: 'Server internal network')),
            const SizedBox(height: 20),
            TextField(controller: txtSocketExternal, decoration: const InputDecoration(labelText: 'Server external network')),
            const SizedBox(height: 20),
            const Expanded(child: SizedBox()),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _isSendingLog ? null : _sendLog,
                icon: _isSendingLog ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: const Text('Send Log'),
              ),
            ),
            ElevatedButton(onPressed: () => _save(config), child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
