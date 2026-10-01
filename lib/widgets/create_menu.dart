import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/files_controller.dart';
import '../services/share_intent_service.dart';
import '../views/share_upload_view.dart';
import 'noo/core/noo_button.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/overlays/noo_dialog.dart';
import 'noo/overlays/noo_sheet.dart';
import 'noo/overlays/noo_text_field.dart';

/// The Files tab's "+"/FAB action: upload a file or create a folder into
/// the current folder. Shared by `FilesView`'s own create button and
/// `MainShellView`'s FAB (the Noo Design System project's FAB component),
/// since both need to trigger the exact same flow.
void showCreateMenu(BuildContext context) {
  showNooSheet(
    context,
    children: [
      NooGroupedList(
        children: [
          NooSettingsRow(
            icon: LucideIcons.upload,
            label: const Text('Upload file'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadFile(context);
            },
          ),
          NooSettingsRow(
            icon: LucideIcons.folder,
            label: const Text('New folder'),
            onTap: () {
              Navigator.pop(context);
              _showCreateFolderDialog(context);
            },
          ),
        ],
      ),
    ],
  );
}

void _showCreateFolderDialog(BuildContext context) {
  final files = context.read<FilesController>();
  final controller = TextEditingController();

  Future<void> submit(BuildContext ctx) async {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(ctx);
    final success = await files.createFolder(name);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(success ? 'Created folder $name' : 'Failed to create folder'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  showNooDialog<void>(
    context,
    title: 'New folder',
    children: [
      NooTextField(
        controller: controller,
        placeholder: 'e.g. Finance',
        autofocus: true,
        onSurface: false,
        onSubmitted: (_) => submit(context),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 10,
        children: [
          NooButton(
            variant: NooButtonVariant.secondary,
            onTap: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          NooButton(
            variant: NooButtonVariant.primary,
            onTap: () => submit(context),
            child: const Text('Create'),
          ),
        ],
      ),
    ],
  );
}

// Mirrors `main.dart`'s `_handleSharedFiles` exactly, so picking a file via
// "+"/the FAB lands on the same destination-picker screen and background
// foreground-service upload as receiving one via Android's "Share to..."
// sheet does, rather than a separate in-app-only upload path.
Future<void> _pickAndUploadFile(BuildContext context) async {
  final picked = await FilePicker.pickFiles();
  if (picked.isEmpty) return;
  final files = picked
      .where((f) => f.path != null)
      .map(
        (f) => SharedFileRef(
          uri: Uri.file(f.path!).toString(),
          name: f.name,
          size: f.lengthSync(),
        ),
      )
      .toList();
  if (files.isEmpty || !context.mounted) return;

  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ShareUploadView(files: files)));
}
