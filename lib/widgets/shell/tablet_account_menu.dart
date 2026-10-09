import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../../views/login_view.dart';
import '../noo/core/noo_avatar.dart';
import '../noo/core/noo_button.dart';
import 'shell_common.dart';

class TabletAccountMenu extends StatefulWidget {
  final bool framed;
  final VoidCallback? onManage;
  const TabletAccountMenu({super.key, this.framed = true, this.onManage});

  @override
  State<TabletAccountMenu> createState() => _TabletAccountMenuState();
}

class _TabletAccountMenuState extends State<TabletAccountMenu> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final colors = context.nooColors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 340);
    Widget accountRow(
      String name, {
      bool current = false,
      VoidCallback? onTap,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NooRadii.input),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            NooAvatar(
              initials: accountInitial(name),
              current: current,
              size: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.body.copyWith(fontSize: 14, color: colors.fg1),
              ),
            ),
            if (current)
              AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: duration,
                curve: Curves.easeInOutCubicEmphasized,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: colors.accentText,
                ),
              ),
          ],
        ),
      ),
    );
    return Material(
      color: widget.framed ? colors.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NooRadii.card),
        side: widget.framed ? BorderSide(color: colors.line) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          accountRow(
            session.displayName,
            current: true,
            onTap: () => setState(() => expanded = !expanded),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeInOutCubicEmphasized,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final account in session.accounts)
                        if (account.id != session.activeAccountId)
                          accountRow(
                            account.label,
                            onTap: () async {
                              await session.switchAccount(account.id);
                              if (mounted) setState(() => expanded = false);
                            },
                          ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          spacing: 6,
                          children: [
                            NooButton(
                              size: NooButtonSize.compact,
                              fullWidth: true,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const LoginView(isAddingAccount: true),
                                ),
                              ),
                              child: const Text('Add Account'),
                            ),
                            NooButton(
                              size: NooButtonSize.compact,
                              fullWidth: true,
                              variant: NooButtonVariant.secondary,
                              onTap:
                                  widget.onManage ??
                                  () => openSettings(context),
                              child: const Text('Manage Accounts'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
