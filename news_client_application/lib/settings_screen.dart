import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_client_application/providers/config_provider.dart';

class SettingsScreen extends ConsumerWidget {
  SettingsScreen({Key? key}) : super(key: key);
  final txtSecret = TextEditingController();
  final txtSocketInternal = TextEditingController();
  final txtSocketExternal = TextEditingController();
  void _save(BuildContext context, ApplicationConfiguration config, String secret, String socketInternal, String socketExternal) {
    config.updateSettings(socketSecret: secret, socketServerInternal: socketInternal, socketServerExternal: socketExternal);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.read(providerConfig.notifier);
    txtSecret.text = config.socketSecret;
    txtSocketInternal.text = config.socketServerInternal;
    txtSocketExternal.text = config.socketServerExternal;
    // txtLogpath.text = config.logFilepath;
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
            // TextField(controller: txtLogpath, decoration: const InputDecoration(labelText: 'Logpath')),
            const Expanded(child: SizedBox()),
            ElevatedButton(onPressed: () => _save(context, config, txtSecret.text, txtSocketInternal.text, txtSocketExternal.text), child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
