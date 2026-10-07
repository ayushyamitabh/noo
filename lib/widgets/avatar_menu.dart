import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/trash_controller.dart';
import '../theme/design_tokens.dart';
import '../views/login_view.dart';
import 'noo/core/noo_avatar.dart';
import 'noo/core/noo_badge.dart';
import 'noo/nav/noo_bottom_bar.dart';
import 'noo/noo_layout.dart';
import 'noo/lists/noo_settings_row.dart';
import 'shell/shell_common.dart';

/// The shell supplies the expanding-card presentation. Standalone top bars
/// retain a dialog fallback (for screens outside the shell).
Future<void> showAvatarMenu(BuildContext context) async {
  final scope = AvatarNavigationScope.maybeOf(context);
  if (scope != null) {
    scope._host.openFrom(context);
    return;
  }
  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    transitionDuration: NooMotion.base,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
          child: _StandaloneAvatarCard(),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: Tween(begin: .88, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class _StandaloneAvatarCard extends StatefulWidget {
  @override
  State<_StandaloneAvatarCard> createState() => _StandaloneAvatarCardState();
}

class _StandaloneAvatarCardState extends State<_StandaloneAvatarCard> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => AvatarMenuCard(
    expanded: expanded,
    onExpand: () => setState(() => expanded = !expanded),
    onClose: () => Navigator.pop(context),
  );
}

/// Account controls and hidden-tab navigation, shared by both card positions.
class AvatarMenuCard extends StatelessWidget {
  final bool bottom;
  final bool expanded;
  final bool movingAvatar;
  final bool showHeaderAvatar;
  final VoidCallback onExpand;
  final VoidCallback onClose;
  const AvatarMenuCard({
    super.key,
    this.bottom = false,
    this.movingAvatar = false,
    this.showHeaderAvatar = true,
    required this.expanded,
    required this.onExpand,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final trashCount = context.watch<TrashController>().items.length;
    void settingsTap() {
      onClose();
      openSettings(context);
    }

    final header = InkWell(
      onTap: onExpand,
      child: Padding(
        padding: const EdgeInsets.all(NooSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.bodyL.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.fg1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serverHost(session.serverUrl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.meta.copyWith(color: colors.fg3),
                  ),
                ],
              ),
            ),
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 20,
              color: colors.fg2,
            ),
            if (showHeaderAvatar) const SizedBox(width: 12),
            if (showHeaderAvatar)
              movingAvatar
                  ? const SizedBox.square(dimension: 32)
                  : NooAvatar(
                      initials: accountInitial(session.username),
                      current: true,
                      size: 32,
                    ),
          ],
        ),
      ),
    );
    final attached = bottom && !showHeaderAvatar;
    final accountSection = AnimatedSize(
      duration: NooMotion.base,
      curve: Curves.easeOutCubic,
      alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
      child: expanded
          ? Column(
              children: [
                for (final account in session.accounts)
                  if (account.id != session.activeAccountId)
                    _OtherAccountRow(
                      name: account.username,
                      host: serverHost(account.serverUrl),
                      onTap: () {
                        onClose();
                        session.switchAccount(account.id);
                      },
                    ),
                Padding(
                  padding: const EdgeInsets.all(NooSpace.md),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: _AccountButton(
                          icon: LucideIcons.userPlus,
                          label: 'Add Account',
                          onTap: () {
                            final nav = Navigator.of(context);
                            onClose();
                            nav.push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const LoginView(isAddingAccount: true),
                              ),
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: _AccountButton(
                          icon: LucideIcons.users,
                          label: 'Manage Accounts',
                          onTap: settingsTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const SizedBox(width: double.infinity),
    );
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!attached) accountSection,
        for (final tab in settings.tabOrder.where(settings.hiddenTabs.contains))
          NooSettingsRow(
            backgroundColor: Colors.transparent,
            icon: tab.icon,
            label: Text(tab.label),
            trailing: tab == AppTab.trash && trashCount > 0
                ? NooBadge(
                    tone: NooBadgeTone.accent,
                    child: Text('$trashCount'),
                  )
                : null,
            onTap: () {
              onClose();
              settings.requestTab(tab);
            },
          ),
        Divider(height: 1, color: colors.line),
        NooSettingsRow(
          backgroundColor: Colors.transparent,
          icon: LucideIcons.settings,
          label: const Text('Settings'),
          onTap: settingsTap,
        ),
        if (attached) ...[header, accountSection],
      ],
    );
    final content = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NooRadii.card - 1),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!bottom) header,
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(child: rows),
                ),
                if (bottom && !attached) header,
              ],
            ),
          ),
        ),
      ),
    );
    return movingAvatar
        ? content
        : _AvatarSurface(
            radius: BorderRadius.circular(NooRadii.card),
            child: content,
          );
  }
}

class _AvatarSurface extends StatelessWidget {
  final BorderRadius radius;
  final Widget child;
  final bool connected;
  const _AvatarSurface({
    required this.radius,
    required this.child,
    this.connected = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final colors = context.nooColors;
    final frosted = settings.bottomBarFrosted;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted
            ? colors.surface.withValues(alpha: settings.bottomBarFrostedOpacity)
            : colors.surface,
        border: connected
            ? null
            : Border.all(color: colors.line),
        borderRadius: radius,
      ),
      child: Padding(padding: const EdgeInsets.all(1), child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: frosted || connected ? null : const [nooDialogShadow],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: frosted
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: settings.bottomBarFrostedBlur,
                  sigmaY: settings.bottomBarFrostedBlur,
                ),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

class AvatarNavigationScope extends InheritedNotifier<AnimationController> {
  final _AvatarNavigationHostState _host;
  AvatarNavigationScope._({
    required _AvatarNavigationHostState host,
    required super.child,
  }) : _host = host,
       super(notifier: host.animation);
  static AvatarNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AvatarNavigationScope>();
  double get progress =>
      Curves.easeInOutCubicEmphasized.transform(_host.animation.value);
  bool get bottom => _host.bottom;
  void close() => _host.close();
  @override
  bool updateShouldNotify(AvatarNavigationScope oldWidget) => true;
}

/// Keeps the top avatar's layout slot while the single animated avatar moves
/// into the card. Its own context gives us the real screen-space origin.
class AvatarNavigationAnchor extends StatelessWidget {
  final Widget child;
  const AvatarNavigationAnchor({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final scope = AvatarNavigationScope.maybeOf(context);
    return IgnorePointer(
      ignoring: scope != null && scope.progress > 0,
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: 1 - (scope?.progress ?? 0),
          child: Opacity(
            opacity: scope != null && scope.progress > 0 ? 0 : 1,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Only the content pane moves; the bottom navigation stays anchored.
class AvatarNavigationBody extends StatelessWidget {
  final Widget child;
  const AvatarNavigationBody({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final scope = AvatarNavigationScope.maybeOf(context);
    return Padding(
      padding: EdgeInsets.only(
        top: scope == null || scope.bottom
            ? 0
            : (scope._host.cardHeight + 12) * scope.progress,
      ),
      child: child,
    );
  }
}

class AvatarNavigationSatellite extends StatelessWidget {
  final double size;
  const AvatarNavigationSatellite({super.key, required this.size});
  @override
  Widget build(BuildContext context) {
    final scope = AvatarNavigationScope.maybeOf(context);
    if (context.watch<SettingsController>().bottomBarStyle ==
        NooBottomBarStyle.attached) {
      return Builder(
        builder: (anchorContext) => ShellAvatarButton(
          hitBox: size,
          label: 'Menu',
          onTap: () => showAvatarMenu(anchorContext),
        ),
      );
    }
    return IgnorePointer(
      ignoring: scope != null && scope.progress > 0,
      child: Opacity(
        opacity: scope != null && scope.progress > 0 ? 0 : 1,
        child: SizedBox(
          width: size,
          height: size,
          child: _AvatarSurface(
            radius: BorderRadius.circular(size / 2),
            child: Builder(
              builder: (anchorContext) => ShellAvatarButton(
                hitBox: size,
                label: 'Menu',
                onTap: () => showAvatarMenu(anchorContext),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AvatarNavigationHost extends StatefulWidget {
  final Widget child;
  const AvatarNavigationHost({super.key, required this.child});
  @override
  State<AvatarNavigationHost> createState() => _AvatarNavigationHostState();
}

class _AvatarNavigationHostState extends State<AvatarNavigationHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 320),
  );
  final GlobalKey measureKey = GlobalKey();
  Rect? origin;
  bool bottom = false;
  bool expanded = false;
  double cardHeight = 150;
  bool measuring = false;
  void measure() {
    if (measuring) return;
    measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      measuring = false;
      if (!mounted) return;
      final box = measureKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && (box.size.height - cardHeight).abs() > .5) {
        setState(() => cardHeight = box.size.height);
      }
    });
  }

  void openFrom(BuildContext context) {
    if (animation.value > 0) {
      close();
      return;
    }
    final settings = context.read<SettingsController>();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final hostBox = this.context.findRenderObject() as RenderBox;
    final center = hostBox.globalToLocal(
      box.localToGlobal(box.size.center(Offset.zero)),
    );
    setState(() {
      bottom = settings.avatarPosition == AvatarPosition.bottom;
      final diameter = bottom
          ? NooBottomBar.rowHeight(
              NooLayout.navStyle(context),
              settings.bottomBarStyle,
            )
          : 32.0;
      origin = Rect.fromCenter(
        center: center,
        width: diameter,
        height: diameter,
      );
      expanded = false;
    });
    animation.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    animation.forward();
  }

  void close() {
    animation.reverseDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    animation.reverse();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final session = context.watch<SessionController>();
    final enabled = settings.navMenuStyle == NooNavMenuStyle.avatarMenu;
    return AvatarNavigationScope._(
      host: this,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = Curves.easeInOutCubicEmphasized.transform(
            animation.value,
          );
          return PopScope(
            canPop: animation.value == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final safeTop = MediaQuery.viewPaddingOf(context).top;
                final attached =
                    bottom &&
                    settings.bottomBarStyle == NooBottomBarStyle.attached;
                final bottomEdge = bottom && origin != null
                    ? origin!.center.dy -
                          NooBottomBar.rowHeight(
                                NooLayout.navStyle(context),
                                settings.bottomBarStyle,
                              ) /
                              2 -
                          (attached ? 0 : 12)
                    : height;
                final maxHeight = (bottomEdge - safeTop - 24).clamp(
                  72.0,
                  height * .8,
                );
                measure();
                Widget card() => ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: AvatarMenuCard(
                    bottom: bottom,
                    movingAvatar: true,
                    showHeaderAvatar: !attached,
                    expanded: expanded,
                    onExpand: () => setState(() => expanded = !expanded),
                    onClose: close,
                  ),
                );
                final target = Rect.fromLTWH(
                  attached ? 0 : 12,
                  bottom ? bottomEdge - cardHeight : safeTop + 8,
                  attached ? width : width - 24,
                  cardHeight,
                );
                final rect = Rect.lerp(
                  attached
                      ? Rect.fromLTWH(0, bottomEdge, width, 0)
                      : origin ?? target,
                  target,
                  progress,
                )!;
                final radius = attached
                    ? BorderRadius.vertical(
                        top: Radius.circular(NooRadii.card * progress),
                      )
                    : BorderRadius.circular(
                        lerpDouble(
                          (origin?.width ?? 32) / 2,
                          NooRadii.card,
                          progress,
                        )!,
                      );
                final avatarTarget = Rect.fromLTWH(
                  target.right - 49,
                  bottom ? target.bottom - 49 : target.top + 17,
                  32,
                  32,
                );
                final avatar = Rect.lerp(
                  origin == null
                      ? avatarTarget
                      : Rect.fromCenter(
                          center: origin!.center,
                          width: 32,
                          height: 32,
                        ),
                  avatarTarget,
                  progress,
                )!;
                return Stack(
                  children: [
                    widget.child,
                    if (enabled)
                      Positioned(
                        left: attached ? 0 : 12,
                        right: attached ? 0 : 12,
                        top: safeTop,
                        child: Offstage(
                          child:
                              NotificationListener<
                                SizeChangedLayoutNotification
                              >(
                                onNotification: (_) {
                                  measure();
                                  return false;
                                },
                                child: SizeChangedLayoutNotifier(
                                  child: KeyedSubtree(
                                    key: measureKey,
                                    child: card(),
                                  ),
                                ),
                              ),
                        ),
                      ),
                    if (enabled && progress > 0 && origin != null) ...[
                      Positioned.fill(
                        bottom: bottom ? height - bottomEdge : 0,
                        child: Semantics(
                          label: 'Close menu',
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: close,
                            child: const ColoredBox(color: Colors.transparent),
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: rect,
                        child: _AvatarSurface(
                          radius: radius,
                          connected: attached,
                          child: ClipRRect(
                            borderRadius: radius,
                            child: OverflowBox(
                              alignment: bottom
                                  ? Alignment.bottomRight
                                  : Alignment.topRight,
                              minWidth: target.width,
                              maxWidth: target.width,
                              minHeight: target.height,
                              maxHeight: target.height,
                              child: IgnorePointer(
                                ignoring: progress < .95,
                                child: Opacity(
                                  opacity: ((progress - .3) / .7).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: card(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!attached)
                        Positioned.fromRect(
                          rect: avatar,
                          child: Semantics(
                            label: 'Close menu',
                            button: true,
                            child: GestureDetector(
                              onTap: close,
                              child: NooAvatar(
                                initials: accountInitial(session.username),
                                current: true,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OtherAccountRow extends StatelessWidget {
  final String name;
  final String host;
  final VoidCallback onTap;

  const _OtherAccountRow({
    required this.name,
    required this.host,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(NooSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.bodyL.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.fg1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.meta.copyWith(color: colors.fg3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            NooAvatar(initials: accountInitial(name), current: false, size: 32),
          ],
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AccountButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(NooRadii.input);
    return Material(
      color: colors.bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Icon(icon, size: 18, color: colors.fg2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.body.copyWith(color: colors.fg1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
