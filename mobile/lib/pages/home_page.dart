import 'package:flutter/material.dart';

import '../api.dart';
import 'classes_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'schedule_page.dart';
import 'student_classes_page.dart';
import 'student_dashboard_page.dart';
import 'teacher_dashboard_page.dart';

/// Khung chính sau đăng nhập: thanh điều hướng dưới với 3 mục Trang chủ / Lớp học / Hồ sơ,
/// nội dung từng mục đổi theo vai trò đăng nhập.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// Màn hình con (vd: sau khi đăng ký + đóng tiền) yêu cầu chuyển sang tab khác.
  static final tabRequest = ValueNotifier<int?>(null);

  /// Đóng hết các màn hình đang mở và về tab [index] (0 Trang chủ, 1 Lớp học, 2 Hồ sơ).
  static void goToTab(BuildContext context, int index) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tabRequest.value = index;
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  String get _classesLabel {
    if (Api.i.role == 'TEACHER') return 'Lớp dạy';
    if (Api.i.role == 'ADMIN') return 'Quản lý lớp';
    return 'Lớp học';
  }

  List<String> get _titles => ['Trang chủ', _classesLabel, 'Hồ sơ'];

  void _selectTab(int index) {
    if (mounted) setState(() => _tab = index);
  }

  void _onTabRequest() {
    final t = HomePage.tabRequest.value;
    if (t == null) return;
    HomePage.tabRequest.value = null;
    _selectTab(t);
  }

  @override
  void initState() {
    super.initState();
    HomePage.tabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    HomePage.tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  Widget _homeTab() {
    switch (Api.i.role) {
      case 'ADMIN':
        return const DashboardPage();
      case 'TEACHER':
        return TeacherDashboardPage(onSelectTab: _selectTab);
      default:
        return StudentDashboardPage(onSelectTab: _selectTab);
    }
  }

  Widget _classesTab() {
    switch (Api.i.role) {
      case 'ADMIN':
        return const ClassesPage();
      case 'TEACHER':
        return const ClassesPage(mine: true);
      default:
        return const StudentClassesPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_homeTab(), _classesTab(), const ProfilePage()];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          if (_tab == 0 && Api.i.role == 'ADMIN')
            IconButton(
              tooltip: 'Lịch toàn trung tâm',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulePage())),
            ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
          NavigationDestination(
              icon: const Icon(Icons.class_outlined),
              selectedIcon: const Icon(Icons.class_),
              label: _classesLabel),
          const NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Hồ sơ'),
        ],
      ),
    );
  }
}
