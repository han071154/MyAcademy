import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'classes_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'student_courses_page.dart';

/// Khung chính sau đăng nhập: thanh điều hướng dưới với 3 mục Trang chủ / Lớp học / Hồ sơ,
/// nội dung từng mục đổi theo vai trò đăng nhập.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const _titles = ['Trang chủ', 'Lớp học', 'Hồ sơ'];

  Widget _homeTab() {
    if (Api.i.role == 'ADMIN') return const DashboardPage();
    return _SimpleHome(
      note: Api.i.role == 'TEACHER'
          ? 'Xem các lớp bạn đang phụ trách ở tab "Lớp học" bên dưới.'
          : 'Xem khóa học đang mở và đăng ký ở tab "Lớp học" bên dưới.',
    );
  }

  Widget _classesTab() {
    switch (Api.i.role) {
      case 'ADMIN':
        return const ClassesPage();
      case 'TEACHER':
        return const ClassesPage(mine: true);
      default:
        return const StudentCoursesPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_homeTab(), _classesTab(), const ProfilePage()];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab])),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
          NavigationDestination(
              icon: Icon(Icons.class_outlined), selectedIcon: Icon(Icons.class_), label: 'Lớp học'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Hồ sơ'),
        ],
      ),
    );
  }
}

/// Trang chủ đơn giản cho giáo viên/học viên: lời chào + gợi ý thao tác tiếp theo.
class _SimpleHome extends StatelessWidget {
  final String note;
  const _SimpleHome({required this.note});

  @override
  Widget build(BuildContext context) {
    final u = Api.i.user ?? {};
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Chào buổi sáng' : (h < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(children: [
          InitialAvatar(u['full_name'], radius: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              Text('${u['full_name'] ?? ''}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 24),
        SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const IconBox(Icons.info_outline, AppColors.primary),
            const SizedBox(width: 14),
            Expanded(child: Text(note, style: const TextStyle(color: AppColors.muted, height: 1.4))),
          ]),
        ),
      ],
    );
  }
}
