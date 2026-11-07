import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'class_detail_page.dart';
import 'courses_page.dart';

class TeacherDashboardPage extends StatefulWidget {
  final void Function(int tabIndex)? onSelectTab;
  const TeacherDashboardPage({super.key, this.onSelectTab});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  late Future<dynamic> _f = Api.i.get('/my/classes');

  void _reload() => setState(() {
        _f = Api.i.get('/my/classes');
      });

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

  Widget _greeting(BuildContext context) {
    final u = Api.i.user ?? {};
    final h = DateTime.now().hour;
    final text = h < 12 ? 'Chào buổi sáng' : (h < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
    return Row(children: [
      InitialAvatar(u['full_name'], radius: 26),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Giảng viên',
                  style: TextStyle(color: Color(0xFF1E40AF), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 2),
          Text('${u['full_name'] ?? 'Thầy/Cô'}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  static int _count(List classes, String status) => classes.where((c) => c['status'] == status).length;

  /// Học viên đang theo học: chỉ tính lớp chưa kết thúc.
  static int _currentStudents(List classes) => classes
      .where((c) => c['status'] != 'CLOSED')
      .fold<int>(0, (sum, c) => sum + ((c['enrolled'] as num?)?.toInt() ?? 0));

  Widget _heroCard(BuildContext context, List classes) {
    final ongoing = _count(classes, 'ONGOING');
    final totalStudents = _currentStudents(classes);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x332563EB), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Expanded(
            child: Row(children: [
              Icon(Icons.workspace_premium_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Flexible(
                child: Text('GIẢNG VIÊN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$ongoing lớp đang dạy',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('Quản lý giảng dạy & Điểm danh',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lớp phụ trách', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 2),
              Text('${classes.length} lớp',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
          ),
          Container(width: 1, height: 36, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Học viên đang học', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 2),
              Text('$totalStudents học viên',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
          ),
        ]),
      ]),
    );
  }

  void _showAttendancePicker(BuildContext context, List classes) {
    if (classes.isEmpty) {
      toast(context, 'Bạn chưa có lớp dạy nào để điểm danh');
      return;
    }
    if (classes.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ClassDetailPage(c: classes.first as Map, initialTabIndex: 1)),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chọn lớp cần điểm danh', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final c in classes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: const IconBox(Icons.checklist_rtl_rounded, AppColors.primary),
                title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${c['schedule'] ?? 'Chưa có lịch'} • Phòng ${c['room'] ?? '—'}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ClassDetailPage(c: c as Map, initialTabIndex: 1)),
                  );
                },
              ),
          ]),
        ),
      ),
    );
  }

  Widget _quickLinks(BuildContext context, List classes) {
    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: SoftCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: onTap,
            child: Column(children: [
              IconBox(icon, color),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        );

    return Row(children: [
      tile(Icons.checklist_rtl_rounded, 'Điểm danh', AppColors.primary, () => _showAttendancePicker(context, classes)),
      const SizedBox(width: 10),
      tile(Icons.class_outlined, 'Lớp tôi dạy', const Color(0xFF2563EB), () => widget.onSelectTab?.call(1)),
      const SizedBox(width: 10),
      tile(Icons.menu_book_outlined, 'Khóa học', AppColors.amber, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Danh mục khóa học')), body: const CoursesPage())),
        );
      }),
      const SizedBox(width: 10),
      tile(Icons.person_outline, 'Hồ sơ', AppColors.ok, () => widget.onSelectTab?.call(2)),
    ]);
  }

  Widget _stat(IconData icon, String label, dynamic value, Color color) => Expanded(
        child: SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconBox(icon, color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('$value', maxLines: 1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                Text(label, maxLines: 2, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      );

  Widget _classCard(BuildContext context, Map c) {
    final max = (c['max_students'] as num?)?.toInt() ?? 20;
    final enrolled = (c['enrolled'] as num?)?.toInt() ?? 0;
    final ratio = (max > 0 ? (enrolled / max) : 0.0).clamp(0.0, 1.0);
    final dates = c['start_date'] == null ? null : '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}';

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (c['course_name'] != null)
                Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Pill(classStatusLabel(c['status'], role: 'TEACHER'), statusColor(c['status'])),
        ]),
        const SizedBox(height: 10),
        MetaRow(Icons.schedule, '${c['schedule'] ?? 'Chưa xếp lịch'}'),
        if (c['room'] != null) MetaRow(Icons.meeting_room_outlined, 'Phòng học: ${c['room']}'),
        if (dates != null) MetaRow(Icons.event_outlined, dates),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Sĩ số lớp:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                Text('$enrolled/$max học viên', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(ratio >= 1.0 ? AppColors.danger : AppColors.primary),
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ClassDetailPage(c: c, initialTabIndex: 0)),
                );
              },
              icon: const Icon(Icons.people_outline, size: 18),
              label: const Text('Danh sách HV'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ClassDetailPage(c: c, initialTabIndex: 1)),
                );
              },
              icon: const Icon(Icons.checklist_rtl_rounded, size: 18),
              label: const Text('Điểm danh'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _f;
      },
      child: FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                  const SizedBox(height: 12),
                  Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Thử lại')),
                ]),
              ),
            );
          }

          final classes = (snap.data as List?) ?? [];
          final ongoing = _count(classes, 'ONGOING');
          final upcoming = _count(classes, 'OPEN');
          final closed = _count(classes, 'CLOSED');
          final totalStudents = _currentStudents(classes);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _greeting(context),
              const SizedBox(height: 16),
              _heroCard(context, classes),
              const SizedBox(height: 16),
              _quickLinks(context, classes),
              const SizedBox(height: 16),
              Row(children: [
                _stat(Icons.play_circle_outline, 'Đang giảng dạy', ongoing, AppColors.ok),
                const SizedBox(width: 12),
                _stat(Icons.event_available_outlined, 'Sắp khai giảng', upcoming, AppColors.primary),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _stat(Icons.task_alt_outlined, 'Đã kết thúc', closed, AppColors.amber),
                const SizedBox(width: 12),
                _stat(Icons.groups_outlined, 'Học viên đang học', totalStudents, const Color(0xFF0D9488)),
              ]),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Lớp dạy phụ trách',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${classes.length} lớp', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              if (classes.isEmpty)
                SoftCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    const IconBox(Icons.school_outlined, AppColors.primary, size: 56),
                    const SizedBox(height: 16),
                    const Text('Chưa có lớp dạy được phân công',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text(
                      'Thầy/Cô hiện chưa có lớp dạy nào. Hãy liên hệ Quản trị viên để được phân công lớp giảng dạy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Làm mới'),
                    ),
                  ]),
                )
              else
                for (final c in classes) _classCard(context, c as Map),
            ],
          );
        },
      ),
    );
  }
}
