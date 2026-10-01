import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/session_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/core/noo_button.dart';

/// Shown in place of the main shell whenever [SessionController.needsUnlock] is
/// true - a fresh app launch with login lock configured, or returning to the
/// foreground after being backgrounded. Prompts automatically on first show
/// and again whenever the app resumes while still locked (e.g. the user
/// switched away to enter their device PIN in the system UI and came back).
class LockScreenView extends StatefulWidget {
  const LockScreenView({super.key});

  @override
  State<LockScreenView> createState() => _LockScreenViewState();
}

class _LockScreenViewState extends State<LockScreenView>
    with WidgetsBindingObserver {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted || _authenticating) {
      return;
    }
    if (context.read<SessionController>().needsUnlock) _attemptUnlock();
  }

  Future<void> _attemptUnlock() async {
    if (_authenticating || !mounted) return;
    setState(() => _authenticating = true);
    await context.read<SessionController>().attemptUnlock();
    if (mounted) setState(() => _authenticating = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Same monochrome-tinted treatment as the splash screen (see
              // main.dart's _SplashView) - the asset is a plain white
              // silhouette on transparent, meant to be recolored rather
              // than shown as-is.
              ColorFiltered(
                colorFilter: ColorFilter.mode(colors.fg1, BlendMode.srcIn),
                child: Image.asset(
                  'assets/icon/app_icon_monochrome.png',
                  width: 80,
                  height: 80,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Noo is locked',
                textAlign: TextAlign.center,
                style: NooText.title.copyWith(color: colors.fg1),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock with your PIN or biometrics to continue',
                textAlign: TextAlign.center,
                style: NooText.body.copyWith(color: colors.fg3),
              ),
              const SizedBox(height: 32),
              NooButton(
                variant: NooButtonVariant.primary,
                size: NooButtonSize.cta,
                icon: LucideIcons.lockOpen,
                disabled: _authenticating,
                onTap: _attemptUnlock,
                child: Text(_authenticating ? 'Unlocking…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
