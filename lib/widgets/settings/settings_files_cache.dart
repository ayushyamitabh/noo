import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/files_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_settings_row.dart';
import 'settings_section.dart';

String _cachePolicyLabel(CachePolicy policy) {
  switch (policy) {
    case CachePolicy.never:
      return 'Never cache';
    case CachePolicy.interval:
      return 'Refresh periodically';
    case CachePolicy.manual:
      return 'Refresh manually only';
  }
}

String _cachePolicyDescription(CachePolicy policy) {
  switch (policy) {
    case CachePolicy.never:
      return 'Every visit to a folder fetches it fresh; synced files are '
          'checked each time you open the app';
    case CachePolicy.interval:
      return "Reuse a folder's listing until it's a few minutes old; synced "
          'files update in the background on the same schedule';
    case CachePolicy.manual:
      return "Reuse a folder's listing until you pull to refresh; synced "
          'files only update when you pull down or tap Sync now';
  }
}

/// Settings section 5: how often folder listings and synced files refresh
/// from the server.
class SettingsFilesCacheSection extends StatelessWidget {
  const SettingsFilesCacheSection({super.key});

  void _openPolicyPicker(BuildContext context, FilesController files) {
    showSettingsPicker(
      context,
      title: 'Cache policy',
      options: [
        for (final policy in CachePolicy.values)
          NooSettingsRow(
            label: Text(_cachePolicyLabel(policy)),
            subtitle: Text(_cachePolicyDescription(policy)),
            trailing: policy == files.cachePolicy
                ? Icon(LucideIcons.check, size: 18, color: context.nooColors.accentText)
                : null,
            onTap: () {
              files.setCachePolicy(policy);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<FilesController>();

    return SettingsSection(
      title: 'Files cache',
      subtitle: 'How often folder listings and synced files refresh from the server',
      children: [
        NooSettingsRow(
          icon: LucideIcons.database,
          label: const Text('Cache policy'),
          value: _cachePolicyLabel(files.cachePolicy),
          onTap: () => _openPolicyPicker(context, files),
        ),
        if (files.cachePolicy == CachePolicy.interval)
          _CacheIntervalRow(
            minutes: files.cacheIntervalMinutes,
            onChanged: files.setCacheIntervalMinutes,
          ),
      ],
    );
  }
}

/// The refresh-interval slider shown under "Cache policy" while
/// [CachePolicy.interval] is selected - not a plain [NooSettingsRow] since
/// it needs a full-width [Slider], but paints its own `surface` background
/// the same way so it sits correctly inside the group's line dividers (see
/// `NooGroupedList`'s doc comment).
class _CacheIntervalRow extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  const _CacheIntervalRow({required this.minutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NooSpace.md, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Refresh interval', style: NooText.bodyL.copyWith(color: colors.fg1)),
                Text('$minutes min', style: NooText.meta.copyWith(color: colors.fg3)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accent,
                inactiveTrackColor: colors.surface3,
                thumbColor: colors.accent,
                overlayColor: colors.accent.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: minutes.toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                label: '$minutes min',
                onChanged: (value) => onChanged(value.round()),
              ),
            ),
            if (minutes < 15)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'While the app is closed, synced files refresh at most every '
                  '15 min (an Android limit).',
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
