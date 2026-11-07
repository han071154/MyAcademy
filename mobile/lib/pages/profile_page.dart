import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_profile_page.dart';
import 'password_pages.dart';

/// Hồ sơ cá nhân: thông tin tài khoản + sửa hồ sơ + đổi mật khẩu + đăng xuất. Dùng chung cho mọi vai trò.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<dynamic> _f = Api.i.get('/auth/me');
  void _reload() => setState(() { _f = Api.i.get('/auth/me'); });

  static const _roleLabel = {'ADMIN': 'Quản trị viên', 'TEACHER': 'Giảng viên', 'STUDENT': 'Học viên'};

  Future<void> _changePassword() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordPage()));

  Future<void> _edit(Map u) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => EditProfilePage(profile: u)));
    if (saved == true && mounted) _reload();
  }

  Widget _info(IconData icon, String label, dynamic value) {
    final empty = value == null || '$value'.trim().isEmpty;
    return ListTile(
      leading: IconBox(icon, AppColors.primary),
      title: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      subtitle: Text(
        empty ? 'Chưa cập nhật' : '$value',
        style: TextStyle(
          color: empty ? AppColors.danger : null,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontStyle: empty ? FontStyle.italic : null,
        ),
      ),
    );
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
                if (u['phone'] == null || u['dob'] == null || u['address'] == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: tint(AppColors.amber), borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.info_outline, size: 18, color: AppColors.amber),
                      SizedBox(width: 8),
                      Expanded(child: Text('Hồ sơ của bạn còn thiếu thông tin, hãy bấm "Chỉnh sửa hồ sơ" để bổ sung.')),
                    ]),
                  ),
                SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _info(Icons.call_outlined, 'Số điện thoại', u['phone']),
                    const Divider(height: 1),
                    _info(Icons.cake_outlined, 'Ngày sinh', u['dob'] == null ? null : fmtDate(u['dob'])),
                    const Divider(height: 1),
                    _info(Icons.home_outlined, 'Địa chỉ', u['address']),
                  ]),
                ),
                SoftCard(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ListTile(
                      leading: const IconBox(Icons.edit_outlined, AppColors.primary),
                      title: const Text('Chỉnh sửa hồ sơ'),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                      onTap: () => _edit(u),
                    ),
                    const Divider(height: 1),
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
