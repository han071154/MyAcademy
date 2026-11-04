import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Hồ sơ cá nhân: thông tin tài khoản + đổi mật khẩu + đăng xuất. Dùng chung cho mọi vai trò.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<dynamic> _f = Api.i.get('/auth/me');
  void _reload() => setState(() { _f = Api.i.get('/auth/me'); });

  static const _roleLabel = {'ADMIN': 'Quản trị viên', 'TEACHER': 'Giảng viên', 'STUDENT': 'Học viên'};

  Future<void> _changePassword() async {
    final v = await showForm(context, 'Đổi mật khẩu', [
      const Field('old_password', 'Mật khẩu hiện tại', type: FieldType.password, required: true),
      Field('new_password', 'Mật khẩu mới (≥ ${Api.minPasswordLength} ký tự)', type: FieldType.password, required: true),
    ]);
    if (v == null || !mounted) return;
    if (await guard(context, () => Api.i.post('/auth/change-password', v)) && mounted) {
      toast(context, 'Đã đổi mật khẩu');
    }
  }

  Future<void> _logout() async {
    if (await confirm(context, 'Đăng xuất khỏi ứng dụng?')) await Api.i.logout();
  }

  @override
  Widget build(BuildContext context) => Loader(
        future: _f,
        onRetry: _reload,
        builder: (data) {
          final u = data as Map;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _f;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                Column(children: [
                  InitialAvatar(u['full_name'], radius: 42),
                  const SizedBox(height: 14),
                  Text('${u['full_name'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${u['email'] ?? ''}', style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  Pill(_roleLabel[Api.i.role] ?? Api.i.role, AppColors.primary),
                ]),
                const SizedBox(height: 28),
                if (u['phone'] != null)
                  SoftCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const IconBox(Icons.call_outlined, AppColors.primary),
                      title: const Text('Số điện thoại'),
                      subtitle: Text('${u['phone']}'),
                    ),
                  ),
                SoftCard(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ListTile(
                      leading: const IconBox(Icons.key_outlined, AppColors.amber),
                      title: const Text('Đổi mật khẩu'),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                      onTap: _changePassword,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const IconBox(Icons.logout, AppColors.danger),
                      title: const Text('Đăng xuất', style: TextStyle(color: AppColors.danger)),
                      onTap: _logout,
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      );
}
