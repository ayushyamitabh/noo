import 'package:flutter/material.dart';

/// One bulk action available for the current multi-selection (e.g. favorite,
/// download, delete), shown as an icon button in the sticky selection
/// toolbar each tab (Files, Photos, ...) renders inline in its own content.
class SelectionAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
