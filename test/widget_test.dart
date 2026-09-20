import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/main.dart';
import 'package:noo/providers/favorites_controller.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/item_operations.dart';
import 'package:noo/providers/photos_controller.dart';
import 'package:noo/providers/pick_controller.dart';
import 'package:noo/providers/recent_controller.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/providers/shares_controller.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/providers/trash_controller.dart';

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

  test('SessionController initializes unauthenticated', () {
    final session = SessionController();
    expect(session.isLoggedIn, false);
  });

  testWidgets('App renders LoginView when not logged in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        // Mirrors main.dart's own provider order/wiring.
        providers: [
          ChangeNotifierProvider(create: (_) => SessionController()),
          ChangeNotifierProvider(create: (_) => SettingsController()),
          ChangeNotifierProvider(
            create: (context) => SyncStatusController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) => FilesController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) =>
                PhotosController(context.read(), context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) =>
                FavoritesController(context.read(), context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) => TrashController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) => SharesController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) => RecentController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) => PickController(context.read()),
          ),
          Provider(
            create: (context) => ItemOperations(
              session: context.read(),
              files: context.read(),
              photos: context.read(),
              favorites: context.read(),
            ),
          ),
        ],
        child: const NextcloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Noo'), findsOneWidget);
    expect(find.text('Server Address'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
