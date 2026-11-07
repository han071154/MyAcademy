import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'student_class_space_page.dart';
import 'student_courses_page.dart';
import 'student_pay_page.dart';

class StudentClassesPage extends StatefulWidget {
  const StudentClassesPage({super.key});

  @override
  State<StudentClassesPage> createState() => _StudentClassesPageState();
}

class _StudentClassesPageState extends State<StudentClassesPage> {
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

  Widget _classCard(BuildContext context, Map c) {
    final fee = num.tryParse('${c['fee']}') ?? 0;
    final paid = num.tryParse('${c['paid']}') ?? 0;
    final debt = fee - paid;
    final dates = c['start_date'] == null ? null : '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}';

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StudentClassSpacePage(classData: c)),
        );
        _reload();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              if (c['course_name'] != null)
                Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Pill(classStatusLabel(c['status'], role: 'STUDENT'), statusColor(c['status'])),
        ]),
        const SizedBox(height: 10),
        MetaRow(Icons.person_outline, 'Giảng viên: ${c['teacher_name'] ?? 'Chưa phân công'}'),
        MetaRow(Icons.schedule, 'Lịch học: ${c['schedule'] ?? 'Chưa có lịch'}'),
        if (c['room'] != null) MetaRow(Icons.meeting_room_outlined, 'Phòng: ${c['room']}'),
        if (dates != null) MetaRow(Icons.event_outlined, dates),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            debt > 0 ? 'Còn nợ: ${vnd(debt)}' : 'Đã nộp đủ học phí',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: debt > 0 ? AppColors.danger : AppColors.ok,
            ),
          ),
          const Row(children: [
            Text('Vào lớp học', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.primary),
          ]),
        ]),
        if (debt > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPayPage(classData: c)));
                _reload();
              },
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Đóng học phí'),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Đăng ký khóa học mới')), body: const StudentCoursesPage())),
          );
          _reload();
        },
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text('Đăng ký lớp mới'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                  const SizedBox(height: 12),
                  Text('${snap.error}', style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Thử lại')),
                ]),
              );
            }

            final list = (snap.data as List?) ?? [];
            if (list.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  SoftCard(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      const IconBox(Icons.menu_book_rounded, AppColors.primary, size: 60),
                      const SizedBox(height: 18),
                      const Text('Bạn chưa đăng ký lớp nào',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text(
                        'Hãy duyệt qua danh sách các khóa học của trung tâm và chọn lớp học phù hợp để bắt đầu ngay.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: const Text('Đăng ký khóa học')),
                                body: const StudentCoursesPage(),
                              ),
                            ),
                          );
                          _reload();
                        },
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Khám phá khóa học ngay'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ]),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: list.length,
              itemBuilder: (context, i) => _classCard(context, list[i] as Map),
            );
          },
        ),
      ),
    );
  }
}

