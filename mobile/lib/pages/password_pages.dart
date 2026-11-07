import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../validators.dart';
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
  Widget build(BuildContext context) {
    final len = widget.controller.text.length;
    final ok = len >= Api.minPasswordLength;
    return TextField(
      controller: widget.controller,
      obscureText: _hide,
      onChanged: (_) => setState(() {}),
      decoration: deco(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ).copyWith(
        helperText: len == 0
            ? null
            : ok
                ? 'Độ dài hợp lệ ✓'
                : 'Tối thiểu ${Api.minPasswordLength} ký tự ($len/${Api.minPasswordLength})',
        helperStyle: TextStyle(color: ok ? AppColors.ok : AppColors.danger),
      ),
    );
  }
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

/// Học viên tự đăng ký tài khoản (chỉ tạo được vai trò Học viên).
/// Mỗi ô báo lỗi ngay khi người dùng nhập sai, không cần bấm Đăng ký mới biết.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _pass2Key = GlobalKey<FormFieldState<String>>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _dobText = TextEditingController();
  final _address = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  DateTime? _dob;
  final _dobKey = GlobalKey<FormFieldState<String>>();
  bool _hide = true;
  bool _hide2 = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _dobText, _address, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validatePass2(String? v) => V.confirm(() => _pass.text)(v);

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: V.latestDob,
      helpText: 'Chọn ngày sinh',
    );
    if (d != null) {
      setState(() {
        _dob = d;
        _dobText.text = fmtDate(d.toIso8601String());
      });
      _dobKey.currentState?.validate(); // xóa báo lỗi "chưa chọn ngày sinh" nếu có
    }
  }

  Future<void> _register() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Api.i.registerStudent(
        fullName: _name.text,
        email: _email.text,
        password: _pass.text,
        phone: V.cleanPhone(_phone.text),
        dob: _dob!,
        address: _address.text,
      );
      // Đã đăng nhập: đóng trang để màn hình chính hiện ra.
      if (mounted) {
        toast(context, 'Đăng ký thành công, chào mừng bạn!');
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _eye(bool hide, VoidCallback onTap) => IconButton(
        icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    final passLen = _pass.text.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký học viên')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
            'Tạo tài khoản học viên để đăng ký lớp, xem lịch học, nộp bài và theo dõi học phí. '
            'Vui lòng điền đầy đủ tất cả thông tin.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: V.name,
            decoration: deco(labelText: 'Họ và tên *', prefixIcon: const Icon(Icons.badge_outlined)),
          ),
          gap,
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: V.email,
            decoration: deco(labelText: 'Email *', prefixIcon: const Icon(Icons.mail_outline)),
          ),
          gap,
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: V.phone,
            decoration: deco(labelText: 'Số điện thoại *', prefixIcon: const Icon(Icons.phone_outlined)),
          ),
          gap,
          TextFormField(
            key: _dobKey,
            controller: _dobText,
            readOnly: true,
            onTap: _pickDob,
            validator: (_) => _dob == null ? 'Vui lòng chọn ngày sinh' : null,
            decoration: deco(
              labelText: 'Ngày sinh *',
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
          ),
          gap,
          TextFormField(
            controller: _address,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: V.address,
            decoration: deco(labelText: 'Địa chỉ *', prefixIcon: const Icon(Icons.home_outlined)),
          ),
          gap,
          TextFormField(
            controller: _pass,
            obscureText: _hide,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: V.password,
            onChanged: (_) {
              setState(() {}); // cập nhật bộ đếm ký tự
              if (_pass2.text.isNotEmpty) _pass2Key.currentState?.validate();
            },
            decoration: deco(
              labelText: 'Mật khẩu *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: _eye(_hide, () => setState(() => _hide = !_hide)),
            ).copyWith(
              helperText: passLen >= Api.minPasswordLength
                  ? 'Độ dài hợp lệ ✓'
                  : 'Tối thiểu ${Api.minPasswordLength} ký tự ($passLen/${Api.minPasswordLength})',
              helperStyle: TextStyle(color: passLen >= Api.minPasswordLength ? AppColors.ok : AppColors.muted),
            ),
          ),
          gap,
          TextFormField(
            key: _pass2Key,
            controller: _pass2,
            obscureText: _hide2,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _validatePass2,
            onFieldSubmitted: (_) => _register(),
            decoration: deco(
              labelText: 'Nhập lại mật khẩu *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: _eye(_hide2, () => setState(() => _hide2 = !_hide2)),
            ),
          ),
          if (_error != null) _errorBox(_error!),
          const SizedBox(height: 20),
          _submitButton('Đăng ký', _loading, _register),
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Đã có tài khoản? Đăng nhập'),
          ),
        ]),
      ),
    );
  }
}

/// Đổi mật khẩu từ trang Hồ sơ: nhập mật khẩu hiện tại + mật khẩu mới, báo lỗi ngay khi gõ.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _pass2Key = GlobalKey<FormFieldState<String>>();
  final _old = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _hide = [true, true, true];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_old, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Api.i.changePassword(_old.text, _pass.text);
      if (mounted) {
        toast(context, 'Đã đổi mật khẩu');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  InputDecoration _deco(String label, int i) => deco(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_hide[i] ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hide[i] = !_hide[i]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final len = _pass.text.length;
    final ok = len >= Api.minPasswordLength;
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi mật khẩu')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          TextFormField(
            controller: _old,
            obscureText: _hide[0],
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập mật khẩu hiện tại' : null,
            decoration: _deco('Mật khẩu hiện tại *', 0),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _pass,
            obscureText: _hide[1],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) {
              final e = V.password(v, empty: 'Vui lòng nhập mật khẩu mới');
              if (e != null) return e;
              if (v == _old.text) return 'Mật khẩu mới phải khác mật khẩu hiện tại';
              return null;
            },
            onChanged: (_) {
              setState(() {});
              if (_pass2.text.isNotEmpty) _pass2Key.currentState?.validate();
            },
            decoration: _deco('Mật khẩu mới *', 1).copyWith(
              helperText: ok ? 'Độ dài hợp lệ ✓' : 'Tối thiểu ${Api.minPasswordLength} ký tự ($len/${Api.minPasswordLength})',
              helperStyle: TextStyle(color: ok ? AppColors.ok : AppColors.muted),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: _pass2Key,
            controller: _pass2,
            obscureText: _hide[2],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: V.confirm(() => _pass.text),
            onFieldSubmitted: (_) => _save(),
            decoration: _deco('Nhập lại mật khẩu mới *', 2),
          ),
          if (_error != null) _errorBox(_error!),
          const SizedBox(height: 20),
          _submitButton('Lưu mật khẩu', _loading, _save),
        ]),
      ),
    );
  }
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
