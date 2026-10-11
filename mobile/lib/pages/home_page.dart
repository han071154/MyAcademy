import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'classes_page.dart';
import 'courses_page.dart';
import 'dashboard_page.dart';
import 'payments_page.dart';
import 'users_page.dart';

class _Dest {
  final String title;
  final IconData icon;
  final Widget Function() page;
  _Dest(this.title, this.icon, this.page);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _i = 0;
  late final List<_Dest> _dests = _build();

  static const _roleLabel = {'ADMIN': 'Quản trị', 'TEACHER': 'Giáo viên', 'STUDENT': 'Học viên'};

  List<_Dest> _build() {
    switch (Api.i.role) {
      case 'ADMIN':
        return [
          _Dest('Tổng quan', Icons.dashboard, () => const DashboardPage()),
          _Dest('Học viên', Icons.school, () => const UsersPage(role: 'STUDENT')),
          _Dest('Giáo viên', Icons.person, () => const UsersPage(role: 'TEACHER')),
          _Dest('Khóa học', Icons.menu_book, () => const CoursesPage()),
          _Dest('Lớp học', Icons.class_, () => const ClassesPage()),
          _Dest('Học phí', Icons.payments, () => const PaymentsPage()),
        ];
      case 'TEACHER':
        return [_Dest('Lớp tôi dạy', Icons.class_, () => const ClassesPage(mine: true))];
      default:
        return [_Dest('Lịch học của tôi', Icons.calendar_month, () => const ClassesPage(mine: true))];
    }
  }

  Future<void> _changePassword() async {
    Navigator.pop(context); // đóng drawer
    final v = await showForm(context, 'Đổi mật khẩu', const [
      Field('old_password', 'Mật khẩu hiện tại', type: FieldType.password, required: true),
      Field('new_password', 'Mật khẩu mới (≥ 6 ký tự)', type: FieldType.password, required: true),
    ]);
    if (v == null || !mounted) return;
    if (await guard(context, () => Api.i.post('/auth/change-password', v)) && mounted) {
      toast(context, 'Đã đổi mật khẩu');
    }
  }

  Widget _navTile(IconData icon, String title,
          {bool selected = false, Color? color, required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          selected: selected,
          selectedTileColor: tint(AppColors.primary),
          selectedColor: AppColors.primary,
          iconColor: color ?? AppColors.muted,
          textColor: color ?? AppColors.ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(icon),
          title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = Api.i.user ?? {};
    final d = _dests[_i];
    return Scaffold(
      appBar: AppBar(title: Text(d.title)),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: Column(children: [
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 24, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Text(initial(u['full_name']),
                    style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 14),
              Text('${u['full_name'] ?? ''}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${u['email'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(20)),
                child: Text(_roleLabel[Api.i.role] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (var i = 0; i < _dests.length; i++)
                _navTile(_dests[i].icon, _dests[i].title, selected: i == _i, onTap: () {
                  setState(() => _i = i);
                  Navigator.pop(context);
                }),
            ]),
          ),
          const Divider(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                _navTile(Icons.key_outlined, 'Đổi mật khẩu', onTap: _changePassword),
                _navTile(Icons.logout, 'Đăng xuất', color: AppColors.danger, onTap: () => Api.i.logout()),
              ]),
            ),
          ),
        ]),
      ),
      body: KeyedSubtree(key: ValueKey(_i), child: d.page()),
    );
  }
}
