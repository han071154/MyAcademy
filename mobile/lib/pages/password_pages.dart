import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ô nhập mật khẩu có nút ẩn/hiện.
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  const _PasswordField(this.controller, this.label);
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hide = true;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hide,
        decoration: deco(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
      );
}

Widget _errorBox(String msg) => Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tint(AppColors.danger), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: AppColors.danger))),
      ]),
    );

Widget _submitButton(String label, bool loading, VoidCallback onPressed) => SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Text(label),
      ),
    );

/// Quên mật khẩu: nhập email → nhận mã trong email → nhập mã + mật khẩu mới.
class ForgotPasswordPage extends StatefulWidget {
  final String? initialEmail;
  const ForgotPasswordPage({super.key, this.initialEmail});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _sent = false;
  bool _loading = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendCode() => _run(() async {
        if (!_email.text.contains('@')) throw ApiException('Vui lòng nhập email hợp lệ');
        await Api.i.sendResetCode(_email.text);
        if (mounted) {
          setState(() => _sent = true);
          toast(context, 'Đã gửi mã xác nhận, vui lòng kiểm tra email');
        }
      });

  Future<void> _reset() => _run(() async {
        if (_code.text.trim().isEmpty) throw ApiException('Vui lòng nhập mã xác nhận');
        if (_pass.text != _pass2.text) throw ApiException('Mật khẩu nhập lại không khớp');
        await Api.i.resetPasswordWithCode(_email.text, _code.text, _pass.text);
        // Đã đăng nhập: đóng trang để màn hình chính hiện ra.
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quên mật khẩu')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(
            _sent
                ? 'Nhập mã xác nhận đã gửi tới ${_email.text.trim()} và đặt mật khẩu mới.'
                : 'Nhập email tài khoản, chúng tôi sẽ gửi mã xác nhận để đặt lại mật khẩu.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            enabled: !_sent,
            keyboardType: TextInputType.emailAddress,
            decoration: deco(labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline)),
          ),
          if (_sent) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: deco(labelText: 'Mã xác nhận', prefixIcon: const Icon(Icons.pin_outlined)),
            ),
            const SizedBox(height: 14),
            _PasswordField(_pass, 'Mật khẩu mới (≥ ${Api.minPasswordLength} ký tự)'),
            const SizedBox(height: 14),
            _PasswordField(_pass2, 'Nhập lại mật khẩu mới'),
          ],
          if (_error != null) _errorBox(_error!),
          const SizedBox(height: 20),
          _sent
              ? _submitButton('Đặt lại mật khẩu', _loading, _reset)
              : _submitButton('Gửi mã xác nhận', _loading, _sendCode),
          if (_sent)
            TextButton(onPressed: _loading ? null : _sendCode, child: const Text('Gửi lại mã')),
        ]),
      );
}

/// Bắt buộc đổi mật khẩu khi đăng nhập bằng mật khẩu do admin cấp / mật khẩu mặc định.
class ForceChangePasswordPage extends StatefulWidget {
  const ForceChangePasswordPage({super.key});
  @override
  State<ForceChangePasswordPage> createState() => _ForceChangePasswordPageState();
}

class _ForceChangePasswordPageState extends State<ForceChangePasswordPage> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_pass.text != _pass2.text) throw ApiException('Mật khẩu nhập lại không khớp');
      await Api.i.changePassword(null, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Đặt mật khẩu mới'),
          automaticallyImplyLeading: false,
          actions: [TextButton(onPressed: Api.i.logout, child: const Text('Đăng xuất'))],
        ),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(
            'Xin chào ${Api.i.user?['full_name'] ?? ''}. Tài khoản của bạn đang dùng mật khẩu được cấp sẵn, '
            'vui lòng đặt mật khẩu mới để tiếp tục.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          _PasswordField(_pass, 'Mật khẩu mới (≥ ${Api.minPasswordLength} ký tự)'),
          const SizedBox(height: 14),
          _PasswordField(_pass2, 'Nhập lại mật khẩu mới'),
          if (_error != null) _errorBox(_error!),
          const SizedBox(height: 20),
          _submitButton('Lưu mật khẩu', _loading, _save),
        ]),
      );
}
