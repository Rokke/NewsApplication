import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_feed_reader/providers/config_provider.dart';

class SettingsScreen extends ConsumerWidget {
  SettingsScreen({Key? key}) : super(key: key);
  final txtSecret = TextEditingController();
  final txtLogpath = TextEditingController();
  void _save(BuildContext context, ApplicationConfiguration config, String secret, String logpath) {
    config.updateSettings(socketSecret: secret, logFilepath: logpath);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.read(providerConfig.notifier);
    txtSecret.text = config.socketSecret;
    txtLogpath.text = config.logFilepath;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(controller: txtSecret, decoration: const InputDecoration(labelText: 'Server secret')),
            const SizedBox(height: 20),
            TextField(controller: txtLogpath, decoration: const InputDecoration(labelText: 'Logpath')),
            const Expanded(child: SizedBox()),
            ElevatedButton(onPressed: () => _save(context, config, txtSecret.text, txtLogpath.text), child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
