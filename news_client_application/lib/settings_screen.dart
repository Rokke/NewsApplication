import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:news_client_application/providers/config_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final txtSecret = TextEditingController();
  final txtSocketInternal = TextEditingController();
  final txtSocketExternal = TextEditingController();

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
    config.updateSettings(socketSecret: txtSecret.text, socketServerInternal: txtSocketInternal.text, socketServerExternal: txtSocketExternal.text);
    Navigator.of(context).pop();
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
            ElevatedButton(onPressed: () => _save(config), child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
