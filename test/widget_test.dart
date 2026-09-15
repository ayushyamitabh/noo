import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nextcloud_client/main.dart';
import 'package:nextcloud_client/providers/server_provider.dart';

void main() {
  test('ServerProvider initializes unauthenticated', () {
    final provider = ServerProvider();
    expect(provider.isLoggedIn, false);
    expect(provider.items.isEmpty, true);
  });

  testWidgets('App renders LoginView when not logged in', (WidgetTester tester) async {
    final provider = ServerProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const NextcloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nextcloud Client'), findsOneWidget);
    expect(find.text('Server Address'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password or App Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });
}
