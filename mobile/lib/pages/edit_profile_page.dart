import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../validators.dart';
import '../widgets.dart';

/// Tự sửa hồ sơ cá nhân: họ tên, số điện thoại, ngày sinh, địa chỉ.
/// Email là tên đăng nhập nên không sửa ở đây (nhờ admin nếu cần đổi).
class EditProfilePage extends StatefulWidget {
  final Map profile;
  const EditProfilePage({super.key, required this.profile});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${widget.profile['full_name'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.profile['phone'] ?? ''}');
  late final _address = TextEditingController(text: '${widget.profile['address'] ?? ''}');
  final _dobKey = GlobalKey<FormFieldState<String>>();
  late DateTime? _dob = DateTime.tryParse('${widget.profile['dob'] ?? ''}');
  late final _dobText = TextEditingController(text: _dob == null ? '' : fmtDate(_dob!.toIso8601String()));
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _dobText]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    var init = _dob ?? DateTime(now.year - 18, now.month, now.day);
    if (init.isAfter(V.latestDob)) init = V.latestDob;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
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

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Api.i.updateMyProfile(
        fullName: _name.text,
        phone: V.cleanPhone(_phone.text),
        dob: _dob!,
        address: _address.text,
      );
      if (mounted) {
        toast(context, 'Đã cập nhật hồ sơ');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          TextFormField(
            initialValue: '${widget.profile['email'] ?? ''}',
            enabled: false,
            decoration: deco(labelText: 'Email (tên đăng nhập)', prefixIcon: const Icon(Icons.mail_outline))
                .copyWith(helperText: 'Muốn đổi email, vui lòng liên hệ quản trị viên'),
          ),
          gap,
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
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: V.address,
            maxLines: 2,
            minLines: 1,
            decoration: deco(labelText: 'Địa chỉ *', prefixIcon: const Icon(Icons.home_outlined)),
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: tint(AppColors.danger), borderRadius: BorderRadius.circular(12)),
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
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Lưu thay đổi'),
            ),
          ),
        ]),
      ),
    );
  }
}
