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
          ? 'Bạn chưa được phân công lớp nào.'
          : 'Bạn chưa đăng ký lớp nào. Xem khóa học đang mở và đăng ký ở tab "Lớp học" bên dưới.',
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

/// Trang chủ giáo viên/học viên: lời chào + danh sách "Lớp của tôi" (lịch học, phòng, học phí còn nợ).
class _SimpleHome extends StatefulWidget {
  final String note;
  const _SimpleHome({required this.note});
  @override
  State<_SimpleHome> createState() => _SimpleHomeState();
}

class _SimpleHomeState extends State<_SimpleHome> {
  late Future<dynamic> _f = Api.i.get('/my/classes');
  bool get _student => Api.i.role == 'STUDENT';

  void _reload() => setState(() { _f = Api.i.get('/my/classes'); });

  // Đăng ký / hủy lớp ở tab "Lớp học" → danh sách ở đây tự cập nhật
  void _onChanged() {
    if (mounted) _reload();
  }

  @override
  void initState() {
    super.initState();
    Api.i.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    Api.i.changes.removeListener(_onChanged);
    super.dispose();
  }

  Widget _classCard(Map c) {
    final fee = num.tryParse('${c['fee']}') ?? 0;
    final debt = fee - (num.tryParse('${c['paid']}') ?? 0);
    final dates = c['start_date'] == null ? null : '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}';
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(width: 8),
          Pill(classStatus[c['status']] ?? '${c['status']}', statusColor(c['status'])),
        ]),
        const SizedBox(height: 6),
        if (_student) MetaRow(Icons.person_outline, 'GV: ${c['teacher_name'] ?? 'chưa phân công'}'),
        MetaRow(Icons.schedule, '${c['schedule'] ?? 'Chưa có lịch'}'),
        if (c['room'] != null) MetaRow(Icons.meeting_room_outlined, 'Phòng ${c['room']}'),
        if (dates != null) MetaRow(Icons.event_outlined, dates),
        if (!_student) MetaRow(Icons.groups_outlined, 'Sĩ số ${c['enrolled']}/${c['max_students']}'),
        if (_student) ...[
          const SizedBox(height: 8),
          Text(debt > 0 ? 'Học phí còn nợ ${vnd(debt)}' : 'Đã đóng đủ học phí',
              style: TextStyle(fontWeight: FontWeight.w600, color: debt > 0 ? AppColors.danger : AppColors.ok)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = Api.i.user ?? {};
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Chào buổi sáng' : (h < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _f;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
          Text(_student ? 'Lớp bạn đang học' : 'Lớp bạn phụ trách',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          FutureBuilder(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return SoftCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(child: Text('${snap.error}', style: const TextStyle(color: AppColors.danger))),
                    TextButton(onPressed: _reload, child: const Text('Thử lại')),
                  ]),
                );
              }
              final list = (snap.data as List?) ?? [];
              if (list.isEmpty) {
                return SoftCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const IconBox(Icons.info_outline, AppColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Text(widget.note, style: const TextStyle(color: AppColors.muted, height: 1.4))),
                  ]),
                );
              }
              return Column(children: [for (final c in list) _classCard(c as Map)]);
            },
          ),
        ],
      ),
    );
  }
}
