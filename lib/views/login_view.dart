import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(text: 'https://');
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final provider = context.read<ServerProvider>();
    final success = await provider.login(
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
    );

    if (!success && mounted) {
      final error = provider.errorMessage ?? 'Failed to connect to Nextcloud server.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Logo & Branding
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cloud_outlined,
                          size: 44,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Nextcloud Client',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Log in to your selfhosted Nextcloud server',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Error Box if any
                    if (provider.errorMessage != null)
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
                                provider.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Server URL Input
                    TextFormField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Server Address',
                        hintText: 'https://cloud.example.com',
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty || val == 'https://') {
                          return 'Please enter your Nextcloud server URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Username Input
                    TextFormField(
                      controller: _userController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password / App Password Input
                    TextFormField(
                      controller: _passController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password or App Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please enter your password or app password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Login Button
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: provider.isLoading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        child: provider.isLoading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Text(
                                'Log In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Supports standard WebDAV and OCS APIs for all self-hosted Nextcloud Hub installations.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
