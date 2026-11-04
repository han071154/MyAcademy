import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'password_pages.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _hide = true;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.i.login(_email.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.translate, size: 38, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Trung tâm ngoại ngữ',
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Lớp học, lịch học và học phí trong một ứng dụng',
                    textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Đăng nhập', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: deco(labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass,
                      obscureText: _hide,
                      onSubmitted: (_) => _login(),
                      decoration: deco(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tint(AppColors.danger),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
                        ]),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : const Text('Đăng nhập'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ForgotPasswordPage(initialEmail: _email.text.trim()))),
                      child: const Text('Quên mật khẩu?'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
