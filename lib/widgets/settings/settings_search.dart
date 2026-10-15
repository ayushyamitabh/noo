import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../noo/lists/noo_settings_row.dart';

/// One searchable Settings option: what the user sees ([label]) and which
/// category screen it lives on. [keywords] are extra words that should find
/// it (synonyms, option names). [target] is the exact text of the row to
/// scroll to once the category opens: null means the [label] itself is that
/// text, and an empty string means there's no single row (a short section
/// that just opens at the top).
class SettingsSearchEntry {
  final String label;
  final String category;
  final String keywords;
  final String? target;

  /// Absent from the tablet/desktop layout (the option only exists on phones)
  /// or from iOS - kept out of the results there instead of leading nowhere.
  final bool phoneOnly;
  final bool hiddenOnIos;

  const SettingsSearchEntry(
    this.label,
    this.category, {
    this.keywords = '',
    this.target,
    this.phoneOnly = false,
    this.hiddenOnIos = false,
  });

  String? get scrollTarget =>
      target == null ? label : (target!.isEmpty ? null : target);
}

/// The Settings options, by category (titles match `AccountView`'s). Kept in
/// step with `lib/widgets/settings/*` by `settings_search_test.dart`, which
/// builds each section and checks every [SettingsSearchEntry.target] is on
/// screen.
const settingsSearchIndex = <SettingsSearchEntry>[
  SettingsSearchEntry(
    'Add account',
    'Accounts',
    keywords: 'sign in log in login server nextcloud another',
  ),
  SettingsSearchEntry(
    'Saved accounts',
    'Accounts',
    keywords: 'manage switch remove sign out log out delete',
    target: 'Add account',
  ),
  SettingsSearchEntry(
    'App lock',
    'Security',
    keywords: 'pin passcode biometric fingerprint face id unlock protect',
  ),
  SettingsSearchEntry(
    'Lock account switching',
    'Security',
    keywords: 'pin passcode biometric unlock accounts protect',
  ),
  SettingsSearchEntry(
    'Lock hidden files',
    'Security',
    keywords: 'pin passcode biometric unlock dotfiles protect',
  ),
  SettingsSearchEntry(
    'Sync everything',
    'File sync',
    keywords: 'offline mirror whole account folders download',
  ),
  SettingsSearchEntry(
    'View offline files',
    'File sync',
    keywords: 'offline synced folders downloaded',
  ),
  SettingsSearchEntry(
    'Background sync notifications',
    'File sync',
    keywords: 'notify alerts updates conflicts',
  ),
  SettingsSearchEntry(
    'Sync on cellular',
    'File sync',
    keywords: 'mobile data wifi wi-fi metered',
  ),
  SettingsSearchEntry(
    'Sync now',
    'File sync',
    keywords: 'refresh update synchronize',
  ),
  SettingsSearchEntry(
    'Cache policy',
    'Files cache',
    keywords:
        'never cache refresh periodically manually interval minutes '
        'folder listings fresh',
  ),
  SettingsSearchEntry(
    'Theme',
    'Appearance',
    keywords: 'dark mode light mode system night',
  ),
  SettingsSearchEntry(
    'Bottom bar',
    'Appearance',
    keywords: 'attached floating navigation style',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Frosted glass',
    'Appearance',
    keywords: 'blur translucent transparent bottom bar menus viewer',
  ),
  SettingsSearchEntry(
    'Frost strength',
    'Appearance',
    keywords: 'frosted glass blur opacity transparency',
    phoneOnly: true,
    target: 'Frosted glass',
  ),
  SettingsSearchEntry(
    'Navigation menu',
    'Appearance',
    keywords: 'hamburger drawer avatar menu',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Avatar position',
    'Appearance',
    keywords: 'top bottom profile menu',
    phoneOnly: true,
    target: 'Navigation menu',
  ),
  SettingsSearchEntry(
    'Search in bottom bar',
    'Appearance',
    keywords: 'navigation tab satellite',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Upload button size',
    'Appearance',
    keywords: 'fab mini expanded auto plus add floating',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Accent color',
    'Appearance',
    keywords: 'colour theme color material you dynamic wallpaper noo blue',
  ),
  SettingsSearchEntry(
    'AMOLED black',
    'Appearance',
    keywords: 'pure black dark oled battery',
  ),
  SettingsSearchEntry(
    'Seek bar style',
    'Appearance',
    keywords: 'video progress bar player scrubber',
    hiddenOnIos: true,
  ),
  SettingsSearchEntry(
    'Default tab',
    'Tabs',
    keywords: 'start open home first screen launch',
  ),
  SettingsSearchEntry(
    'Tap tab to scroll to top',
    'Tabs',
    keywords: 'navigation bottom bar list scroll',
  ),
  SettingsSearchEntry(
    'Tab order',
    'Tabs',
    keywords: 'reorder pin bottom bar hide show navigation',
    target: '',
  ),
  SettingsSearchEntry(
    'Action bar position',
    'Action bar',
    keywords: 'selection top bottom multi-select bulk',
    target: 'Position',
  ),
  SettingsSearchEntry(
    'Keep filters visible',
    'Action bar',
    keywords: 'selection filter bar breadcrumbs hide show multi-select',
  ),
  SettingsSearchEntry(
    'Action bar actions',
    'Action bar',
    keywords: 'reorder more selection share delete move copy favorite',
    target: '',
  ),
  SettingsSearchEntry(
    'Swipe right',
    'Swipe on a file',
    keywords: 'gesture list favorite share delete action',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Swipe left',
    'Swipe on a file',
    keywords: 'gesture list favorite share delete action',
    phoneOnly: true,
  ),
  SettingsSearchEntry(
    'Version',
    'About',
    keywords: 'build number app identifier release',
  ),
  SettingsSearchEntry(
    'Privacy policy',
    'About',
    keywords: 'website github source licence license links',
  ),
];

/// The entries matching [query], best first: every whitespace-separated word
/// of the query must appear (case-insensitively) in an entry's label,
/// category or keywords; label matches rank above keyword-only matches.
/// [phone] / [ios] drop entries that don't exist in the current layout.
List<SettingsSearchEntry> searchSettings(
  String query, {
  required bool phone,
  required bool ios,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final scored = <(int, SettingsSearchEntry)>[];
  for (final entry in settingsSearchIndex) {
    if ((entry.phoneOnly && !phone) || (entry.hiddenOnIos && ios)) continue;
    final label = entry.label.toLowerCase();
    final category = entry.category.toLowerCase();
    final rest = '$category ${entry.keywords}'.toLowerCase();
    var score = 0;
    var matches = true;
    for (final word in words) {
      if (label.startsWith(word) || label.contains(' $word')) {
        score += 3;
      } else if (label.contains(word)) {
        score += 2;
      } else if (rest.contains(word)) {
        score += 1;
      } else {
        matches = false;
        break;
      }
    }
    if (matches) scored.add((score, entry));
  }
  // Stable: equal scores keep the index (screen) order.
  final ranked = [
    for (var i = 0; i < scored.length; i++) (i, scored[i].$1, scored[i].$2),
  ]..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return [for (final r in ranked) r.$3];
}

/// The result list shown in place of the category list while searching.
class SettingsSearchResults extends StatelessWidget {
  final List<SettingsSearchEntry> results;
  final IconData Function(String category) iconFor;
  final ValueChanged<SettingsSearchEntry> onOpen;

  const SettingsSearchResults({
    super.key,
    required this.results,
    required this.iconFor,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NooSpace.xxl),
        child: Column(
          children: [
            Icon(LucideIcons.searchX, size: 40, color: colors.fg3),
            const SizedBox(height: NooSpace.sm),
            Text(
              'No matching settings',
              style: NooText.bodyL.copyWith(color: colors.fg2),
            ),
          ],
        ),
      );
    }
    return NooGroupedList(
      children: [
        for (final entry in results)
          NooSettingsRow(
            icon: iconFor(entry.category),
            label: Text(entry.label),
            subtitle: Text(entry.category),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: colors.fg3,
            ),
            onTap: () => onOpen(entry),
          ),
      ],
    );
  }
}

/// Scrolls to and briefly highlights the row whose text is [label] inside
/// [child] once it's laid out - how a search result lands on its option.
/// Settings rows are plain [Text] labels, so this finds the first one with
/// that exact text instead of every row needing a key.
class SettingsReveal extends StatefulWidget {
  final String? label;
  final Widget child;

  const SettingsReveal({super.key, required this.label, required this.child});

  @override
  State<SettingsReveal> createState() => _SettingsRevealState();
}

class _SettingsRevealState extends State<SettingsReveal> {
  @override
  void initState() {
    super.initState();
    if (widget.label != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  Element? _find(String label) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Text && widget.data == label) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  Future<void> _reveal() async {
    // Let a page transition / switcher settle so positions are final.
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    final element = _find(widget.label!);
    if (element == null) return;
    await Scrollable.ensureVisible(
      element,
      alignment: .3,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !element.mounted) return;
    final box = element.renderObject;
    final overlay = Overlay.maybeOf(context);
    if (box is! RenderBox || !box.attached || overlay == null) return;
    final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(8);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _Flash(rect: rect, onDone: entry.remove),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A rounded accent highlight that fades out - the "this is it" cue.
class _Flash extends StatefulWidget {
  final Rect rect;
  final VoidCallback onDone;
  const _Flash({required this.rect, required this.onDone});

  @override
  State<_Flash> createState() => _FlashState();
}

class _FlashState extends State<_Flash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Positioned.fromRect(
      rect: widget.rect,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: TweenSequence([
            TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
            TweenSequenceItem(tween: ConstantTween(1.0), weight: 3),
            TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 4),
          ]).animate(_controller),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accentSoft.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(NooRadii.input),
            ),
          ),
        ),
      ),
    );
  }
}
