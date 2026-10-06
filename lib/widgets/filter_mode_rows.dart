import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/files_controller.dart';
import '../theme/design_tokens.dart';
import 'noo/core/noo_segmented_control.dart';

/// "Hidden files" row of the Files/Photos filter sheets: hide them (the
/// default), show only them, or show them alongside everything else. Same
/// icon-always/label-when-selected pill as the type filter above it in
/// both sheets.
class HiddenFilesFilterRow extends StatelessWidget {
  final HiddenFilesFilter value;
  final ValueChanged<HiddenFilesFilter> onChanged;

  const HiddenFilesFilterRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FilterModeRow<HiddenFilesFilter>(
      icon: LucideIcons.eye,
      title: 'Hidden files',
      value: value,
      onChanged: onChanged,
      options: const [
        NooSegmentOption(
          value: HiddenFilesFilter.hide,
          icon: LucideIcons.eyeOff,
          label: 'Hide',
        ),
        NooSegmentOption(
          value: HiddenFilesFilter.only,
          icon: LucideIcons.eye,
          label: 'Only hidden',
        ),
        NooSegmentOption(
          value: HiddenFilesFilter.include,
          icon: LucideIcons.layers,
          label: 'All + hidden',
        ),
      ],
    );
  }
}

/// "External storage" row of the Files/Photos filter sheets: cloud only
/// (the default), only external storage, or both. Files shows the external
/// items in a collapsible section for [StorageScope.all].
class StorageScopeRow extends StatelessWidget {
  final StorageScope value;
  final ValueChanged<StorageScope> onChanged;

  const StorageScopeRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FilterModeRow<StorageScope>(
      icon: LucideIcons.hardDrive,
      title: 'External storage',
      value: value,
      onChanged: onChanged,
      options: const [
        NooSegmentOption(
          value: StorageScope.cloud,
          icon: LucideIcons.cloud,
          label: 'Cloud only',
        ),
        NooSegmentOption(
          value: StorageScope.external,
          icon: LucideIcons.hardDrive,
          label: 'Only external',
        ),
        NooSegmentOption(
          value: StorageScope.all,
          icon: LucideIcons.layers,
          label: 'All + external',
        ),
      ],
    );
  }
}

class _FilterModeRow<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T value;
  final ValueChanged<T> onChanged;
  final List<NooSegmentOption<T>> options;

  const _FilterModeRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colors.fg2),
            const SizedBox(width: 10),
            Text(title, style: NooText.bodyL.copyWith(color: colors.fg1)),
          ],
        ),
        const SizedBox(height: 10),
        NooSegmentedControl<T>(
          fill: true,
          onSurface: true,
          labelOnlySelected: true,
          value: value,
          onChanged: onChanged,
          options: options,
        ),
      ],
    );
  }
}
