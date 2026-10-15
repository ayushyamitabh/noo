import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/services/sync_service.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/widgets/manage_synced_folders_sheet.dart';

import 'files_test_harness.dart';

class _Sync extends SyncStatusController {
  _Sync(
    super.session,
    super.files,
    this._paths, {
    this.everything = false,
    this.deviceOnly = const [],
  });
  final List<String> _paths;
  final bool everything;
  final List<DeviceOnlyItem> deviceOnly;
  @override
  List<String> get syncedPaths => _paths;
  @override
  bool get syncEverything => everything;
  @override
  Future<List<DeviceOnlyItem>> deviceOnlyItems() async => deviceOnly;
}

void main() {
  setUpFilesHarness();

  Future<void> pumpSheet(WidgetTester tester, SyncStatusController sync) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManageSyncedFoldersSheet(sync: sync),
            ),
          ),
        ),
      );

  testWidgets('lists the synced paths', (tester) async {
    final connectivity = HarnessConnectivity();
    final session = HarnessSession(connectivity);
    final files = HarnessFiles(session, []);
    final sync = _Sync(session, files, ['/Docs', '/Photos/2024']);
    await pumpSheet(tester, sync);
    await tester.pump();
    expect(find.text('/Docs'), findsOneWidget);
    expect(find.text('/Photos/2024'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    files.dispose();
    session.dispose();
    connectivity.dispose();
  });

  testWidgets('"Sync everything" lists what is on the device', (tester) async {
    final connectivity = HarnessConnectivity();
    final session = HarnessSession(connectivity);
    final files = HarnessFiles(session, []);
    final sync = _Sync(
      session,
      files,
      const [],
      everything: true,
      deviceOnly: const [
        DeviceOnlyItem('/Docs', isFolder: true),
        DeviceOnlyItem('/notes.txt', isFolder: false),
      ],
    );
    await pumpSheet(tester, sync);
    await tester.pump();
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('/Docs'), findsOneWidget);
    expect(find.text('/notes.txt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    files.dispose();
    session.dispose();
    connectivity.dispose();
  });

  testWidgets('left-over files are listed with a remove action', (
    tester,
  ) async {
    final connectivity = HarnessConnectivity();
    final session = HarnessSession(connectivity);
    final files = HarnessFiles(session, []);
    final sync = _Sync(
      session,
      files,
      const ['/Keep'],
      deviceOnly: const [DeviceOnlyItem('/Old', isFolder: true)],
    );
    await pumpSheet(tester, sync);
    await tester.pump();
    expect(find.text('/Keep'), findsOneWidget);
    expect(find.text('On this device, not syncing'), findsOneWidget);
    expect(find.text('/Old'), findsOneWidget);
    expect(find.byTooltip('Remove from device'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    files.dispose();
    session.dispose();
    connectivity.dispose();
  });
}
