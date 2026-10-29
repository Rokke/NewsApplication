import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_client_application/home.dart';
import 'package:news_client_application/providers/config_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

// No addresses and no secret: the SocketProvider is not valid, so it never tries to connect
ApplicationConfiguration _emptyConfig() =>
    ApplicationConfiguration()
      ..socketServerInternal = ''
      ..socketServerExternal = ''
      ..socketSecret = ''
      ..logFilepath = '';

void main() {
  testWidgets('HomePage without a configured server asks for configuration', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providerConfig.overrideWith((ref) => _emptyConfig()),
          appVersionProvider.overrideWith((ref) => PackageInfo(appName: 'news', packageName: 'news', version: '9.9.9', buildNumber: '1')),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    expect(find.text('Konfigurer leser'), findsOneWidget);
    expect(find.text('RSS news'), findsOneWidget);
    expect(find.text('9.9.9'), findsOneWidget);
    expect(find.byIcon(Icons.no_cell), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
