import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/main.dart';
import 'package:noo/providers/server_provider.dart';

void main() {
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'readAll') return <String, String>{};
          return null;
        });
  });

  test('ServerProvider initializes unauthenticated', () {
    final provider = ServerProvider();
    expect(provider.isLoggedIn, false);
    expect(provider.items.isEmpty, true);
  });

  testWidgets('App renders LoginView when not logged in', (
    WidgetTester tester,
  ) async {
    final provider = ServerProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const NextcloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Noo'), findsOneWidget);
    expect(find.text('Server Address'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
