import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import 'connection_check.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(authSessionProvider.notifier)
          .login(
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
          );
    } catch (e) {
      setState(
        () => _error = e is ApiException
            ? e.message
            : 'Sign-in failed on this phone (${e.runtimeType}). Please try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.backOffice(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Brandmark(),
                    const SizedBox(height: 40),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: AppColors.cream),
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Phone number is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            style: const TextStyle(color: AppColors.cream),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.creamDark,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Password is required'
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFE07A64)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.charcoal,
                                      ),
                                    )
                                  : const Text('Sign in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: AppColors.charcoal,
                              builder: (_) => const _ConnectionCheckSheet(),
                            ),
                            child: const Text(
                              'Trouble signing in? Check this phone',
                            ),
                          ),
                        ],
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

class _Brandmark extends StatelessWidget {
  const _Brandmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          child: const Icon(
            Icons.restaurant_menu,
            color: AppColors.gold,
            size: 38,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'CSC',
          style: TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'CREAM',
          style: TextStyle(
            color: AppColors.cream,
            fontWeight: FontWeight.w700,
            fontSize: 32,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'we serve beyond your desire',
          style: TextStyle(
            color: AppColors.creamDark,
            fontStyle: FontStyle.italic,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// Runs [runConnectionChecks] and shows each result, so a photo of this sheet
/// says what is wrong with one phone's sign-in.
class _ConnectionCheckSheet extends StatefulWidget {
  const _ConnectionCheckSheet();

  @override
  State<_ConnectionCheckSheet> createState() => _ConnectionCheckSheetState();
}

class _ConnectionCheckSheetState extends State<_ConnectionCheckSheet> {
  late Future<List<CheckResult>> _future = runConnectionChecks();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check this phone',
              style: TextStyle(
                color: AppColors.cream,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Take a photo of this screen and send it to Thirdsan.',
              style: TextStyle(
                color: AppColors.creamDark.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<CheckResult>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final results = snapshot.data ?? const [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              r.ok ? Icons.check_circle : Icons.error,
                              color: r.ok
                                  ? const Color(0xFF8FC9A4)
                                  : const Color(0xFFE07A64),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.label,
                                    style: const TextStyle(
                                      color: AppColors.cream,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    r.detail,
                                    style: TextStyle(
                                      color: AppColors.creamDark.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Server: ${AppConfig.apiBaseUrl}',
                      style: TextStyle(
                        color: AppColors.creamDark.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _future = runConnectionChecks()),
                      child: const Text('Check again'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
