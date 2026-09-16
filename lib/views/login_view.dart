import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';

class LoginView extends StatefulWidget {
  /// True when this is pushed from Settings ("Add account") on top of an
  /// already-logged-in session, rather than shown as the app's root screen
  /// with no account yet. Adds an AppBar/back affordance and auto-pops once
  /// the new account becomes active.
  final bool isAddingAccount;

  const LoginView({super.key, this.isAddingAccount = false});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  String? _originalActiveAccountId;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAddingAccount) {
      _originalActiveAccountId = context.read<ServerProvider>().activeAccountId;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    context.read<ServerProvider>().startLoginFlow(
      _urlController.text.trim(),
      addAccount: widget.isAddingAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    final isAwaitingBrowser =
        provider.loginFlowStatus == LoginFlowStatus.awaitingBrowser;
    final isInitiating = provider.loginFlowStatus == LoginFlowStatus.initiating;

    // A new/refreshed account has just become active - pop back to
    // Settings rather than leaving this form sitting on top of it.
    if (widget.isAddingAccount &&
        !_popped &&
        provider.loginFlowStatus == LoginFlowStatus.idle &&
        provider.activeAccountId != _originalActiveAccountId) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    final body = Scaffold(
      appBar: widget.isAddingAccount
          ? AppBar(title: const Text('Add Account'))
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: isAwaitingBrowser
                  ? _WaitingForBrowser(
                      onCancel: () => provider.cancelLoginFlow(),
                      onReopenBrowser: provider.reopenLoginBrowser,
                    )
                  : _ServerForm(
                      formKey: _formKey,
                      urlController: _urlController,
                      isLoading: isInitiating || provider.isLoading,
                      errorMessage:
                          provider.loginFlowStatus == LoginFlowStatus.error
                          ? provider.errorMessage
                          : null,
                      onContinue: _handleContinue,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
            ),
          ),
        ),
      ),
    );

    if (!widget.isAddingAccount) return body;

    // Backing out mid-flow (system back/swipe-back, not just the explicit
    // Cancel button in _WaitingForBrowser) should cancel the pending login
    // flow rather than leaving its poll timer running after this screen is
    // gone - this view could never be popped before "add account" existed,
    // so that case wasn't reachable until now.
    return PopScope(
      canPop: provider.loginFlowStatus != LoginFlowStatus.awaitingBrowser,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) provider.cancelLoginFlow();
      },
      child: body,
    );
  }
}

class _ServerForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController urlController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onContinue;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ServerForm({
    required this.formKey,
    required this.urlController,
    required this.isLoading,
    required this.errorMessage,
    required this.onContinue,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 80,
                height: 80,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Noo',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Connect to your self-hosted server',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 36),
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          TextFormField(
            controller: urlController,
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
            decoration: InputDecoration(
              labelText: 'Server Address',
              hintText: 'cloud.example.com',
              prefixIcon: const Icon(Icons.dns_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your Nextcloud server address';
              }
              return null;
            },
            onFieldSubmitted: (_) => onContinue(),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: isLoading ? null : onContinue,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "You'll finish signing in through your browser. This app never sees your password.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingForBrowser extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onReopenBrowser;

  const _WaitingForBrowser({
    required this.onCancel,
    required this.onReopenBrowser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: colorScheme.primary),
        const SizedBox(height: 28),
        Text(
          'Waiting for you to sign in',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Complete the login in the browser window that just opened, then come back here.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: onReopenBrowser,
          icon: const Icon(Icons.open_in_browser_rounded),
          label: const Text('Reopen browser'),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
