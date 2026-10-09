import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/saved_account.dart';
import '../providers/session_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/core/noo_avatar.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_text_field.dart';
import '../widgets/settings/settings_dialogs.dart';
import '../widgets/shell/shell_common.dart';
import 'login_webview_view.dart';

class LoginView extends StatefulWidget {
  /// True when this is pushed from Settings ("Add account") on top of an
  /// already-logged-in session, rather than shown as the app's root screen
  /// with no account yet. Adds a top bar/back affordance and auto-pops once
  /// the new account becomes active.
  final bool isAddingAccount;

  const LoginView({super.key, this.isAddingAccount = false});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _urlController = TextEditingController();
  String? _originalActiveAccountId;
  String? _localError;
  bool _popped = false;
  bool _webViewPushed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAddingAccount) {
      _originalActiveAccountId = context
          .read<SessionController>()
          .activeAccountId;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(
        () => _localError = 'Please enter your Nextcloud server address',
      );
      return;
    }
    setState(() => _localError = null);
    FocusScope.of(context).unfocus();
    context.read<SessionController>().startLoginFlow(
      url,
      addAccount: widget.isAddingAccount,
    );
  }

  /// Resumes a saved account with one tap (see [SessionController.switchAccount]).
  /// That can fail silently from the account's own perspective - most often
  /// a stored app password that no longer works (revoked server-side, or
  /// left over from before a since-fixed bug that deleted it too eagerly on
  /// a plain network hiccup) - so this surfaces that as a SnackBar with a
  /// silently failing every time - a delete button on the row itself (see
  /// [_SavedAccountRow]) is the way out.
  Future<void> _continueAsAccount(SavedAccount account) async {
    final session = context.read<SessionController>();
    final success = await session.switchAccount(account.id);
    if (success || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("Couldn't sign in as ${account.label}"),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Mirrors Settings' own account removal - same confirm/remove gate, just
  /// reached from the login screen instead of the saved-accounts list.
  Future<void> _confirmRemoveAccount(SavedAccount account) async {
    await confirmRemoveAccount(
      context,
      context.read<SessionController>(),
      accountId: account.id,
      username: account.username,
      host: serverHost(account.serverUrl),
      isActive: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final session = context.watch<SessionController>();

    final isAwaitingBrowser =
        session.loginFlowStatus == LoginFlowStatus.awaitingBrowser;
    final isInitiating = session.loginFlowStatus == LoginFlowStatus.initiating;

    // A new/refreshed account has just become active - pop back to
    // Settings rather than leaving this form sitting on top of it.
    if (widget.isAddingAccount &&
        !_popped &&
        session.loginFlowStatus == LoginFlowStatus.idle &&
        session.activeAccountId != _originalActiveAccountId) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    // Every login (first account or an additional one) shows its login
    // page in LoginWebViewView, a real screen this app owns - see
    // SessionController.startLoginFlow's doc comment for why. Push it the
    // moment there's a URL to show; _webViewPushed resets once that route
    // pops (cancelled or done) so a retry after cancelling pushes it again.
    if (!_webViewPushed &&
        isAwaitingBrowser &&
        session.pendingLoginUrl != null) {
      _webViewPushed = true;
      final url = session.pendingLoginUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // A plain MaterialPageRoute's animated slide/fade transition can
        // leave this screen fully black after popping back off of it - a
        // known Android WebView-as-PlatformView compositing issue with the
        // Impeller renderer (the platform view's surface isn't always torn
        // down in sync with an animated route transition). An instant,
        // non-animated route sidesteps it entirely; the close (X) button
        // already reads like a immediate action, not something that needs
        // a slide, so no UX is lost.
        await Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => LoginWebViewView(url: url),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        _webViewPushed = false;
      });
    }

    final errorMessage =
        _localError ??
        (session.loginFlowStatus == LoginFlowStatus.error
            ? session.errorMessage
            : null);

    final body = Scaffold(
      backgroundColor: colors.bg,
      appBar: widget.isAddingAccount
          ? NooTopBar(
              style: NooLayout.navStyle(context),
              title: 'Add account',
              leading: const NooTopBarBack(),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A logout keeps the account saved rather than
                  // deleting it, specifically so it can be resumed
                  // from here with one tap - no need to repeat
                  // Login Flow v2.
                  if (!widget.isAddingAccount &&
                      session.accounts.isNotEmpty) ...[
                    _SavedAccountsSection(
                      accounts: session.accounts,
                      onSelect: (account) => _continueAsAccount(account),
                      onRemove: (account) => _confirmRemoveAccount(account),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(child: Divider(color: colors.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: NooText.meta.copyWith(color: colors.fg3),
                          ),
                        ),
                        Expanded(child: Divider(color: colors.line)),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                  _ServerForm(
                    urlController: _urlController,
                    isLoading:
                        isInitiating || session.isLoading || isAwaitingBrowser,
                    errorMessage: errorMessage,
                    onContinue: _handleContinue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.isAddingAccount) return body;

    // Backing out mid-flow (system back/swipe-back, not just the explicit
    // Cancel button in LoginWebViewView) should cancel the pending login
    // flow rather than leaving its poll timer running after this screen is
    // gone - this view could never be popped before "add account" existed,
    // so that case wasn't reachable until now.
    return PopScope(
      canPop: session.loginFlowStatus != LoginFlowStatus.awaitingBrowser,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) session.cancelLoginFlow();
      },
      child: body,
    );
  }
}

class _ServerForm extends StatelessWidget {
  final TextEditingController urlController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onContinue;

  const _ServerForm({
    required this.urlController,
    required this.isLoading,
    required this.errorMessage,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          // Same monochrome-tinted treatment as the splash/lock screens
          // (see main.dart's _SplashView) - the asset is a plain white
          // silhouette on transparent, meant to be recolored rather than
          // shown as-is. Used everywhere the app shows its own icon
          // in-app, rather than the full-color launcher icon.
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(colors.fg1, BlendMode.srcIn),
            child: Image.asset(
              'assets/icon/app_icon_monochrome.png',
              width: 80,
              height: 80,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Noo',
          textAlign: TextAlign.center,
          style: NooText.largeTitle.copyWith(color: colors.fg1),
        ),
        const SizedBox(height: 6),
        Text(
          'Connect to your self-hosted server',
          textAlign: TextAlign.center,
          style: NooText.body.copyWith(color: colors.fg3),
        ),
        const SizedBox(height: 36),
        if (errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.dangerSoft,
              borderRadius: BorderRadius.circular(NooRadii.input),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleAlert, color: colors.danger, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: NooText.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        NooTextField(
          controller: urlController,
          placeholder: 'cloud.example.com',
          leadingIcon: LucideIcons.server,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => onContinue(),
        ),
        const SizedBox(height: 28),
        NooButton(
          variant: NooButtonVariant.primary,
          size: NooButtonSize.cta,
          fullWidth: true,
          disabled: isLoading,
          onTap: onContinue,
          child: Text(isLoading ? 'Connecting…' : 'Continue'),
        ),
        const SizedBox(height: 24),
        Text(
          "You'll finish signing in on the page that opens. This app never sees your password.",
          textAlign: TextAlign.center,
          style: NooText.meta.copyWith(color: colors.fg3, fontSize: 11),
        ),
      ],
    );
  }
}

/// Saved accounts a logout left recoverable - tapping one resumes it via
/// [SessionController.switchAccount] instead of repeating Login Flow v2.
class _SavedAccountsSection extends StatelessWidget {
  final List<SavedAccount> accounts;
  final ValueChanged<SavedAccount> onSelect;
  final ValueChanged<SavedAccount> onRemove;

  const _SavedAccountsSection({
    required this.accounts,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Continue as',
            style: NooText.label.copyWith(color: colors.fg2),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(NooRadii.card),
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.line),
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 1),
                  _SavedAccountRow(
                    account: accounts[i],
                    onTap: () => onSelect(accounts[i]),
                    onRemove: () => onRemove(accounts[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedAccountRow extends StatelessWidget {
  final SavedAccount account;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SavedAccountRow({
    required this.account,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NooSpace.md,
            vertical: 10,
          ),
          child: Row(
            spacing: 12,
            children: [
              NooAvatar(initials: accountInitial(account.label), size: 36),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      account.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.bodyL.copyWith(
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: colors.fg1,
                      ),
                    ),
                    Text(
                      serverHost(account.serverUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.meta.copyWith(color: colors.fg3),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.x, size: 16, color: colors.fg2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
