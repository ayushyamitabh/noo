import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../noo/lists/noo_settings_row.dart';
import 'settings_section.dart';

class SettingsAboutSection extends StatefulWidget {
  const SettingsAboutSection({super.key});

  @override
  State<SettingsAboutSection> createState() => _SettingsAboutSectionState();
}

class _SettingsAboutSectionState extends State<SettingsAboutSection> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  Future<void> _openLink(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final pending = snapshot.hasError ? 'Unavailable' : 'Loading…';
      return SettingsSection(
        title: 'About',
        children: [
          const NooSettingsRow(
            label: Text('Noo'),
            subtitle: Text('An independent Nextcloud client'),
          ),
          NooSettingsRow(
            label: const Text('Version'),
            trailing: Text(info?.version ?? pending),
          ),
          NooSettingsRow(
            label: const Text('Build number'),
            trailing: Text(info?.buildNumber ?? pending),
          ),
          NooSettingsRow(
            label: const Text('App identifier'),
            subtitle: Text(info?.packageName ?? pending),
          ),
          for (final link in {
            'Website': 'https://noo.ayushya.dev',
            'GitHub': 'https://github.com/ayushyamitabh/noo',
            'Privacy policy': 'https://noo.ayushya.dev/privacy',
          }.entries)
            NooSettingsRow(
              label: Text(link.key),
              value: '',
              onTap: () => _openLink(link.value),
            ),
        ],
      );
    },
  );
}
