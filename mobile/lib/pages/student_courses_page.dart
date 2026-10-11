import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Học viên: danh sách khóa học của trung tâm + các lớp đang mở để đăng ký.
class StudentCoursesPage extends StatefulWidget {
  const StudentCoursesPage({super.key});
  @override
  State<StudentCoursesPage> createState() => _StudentCoursesPageState();
}

class _StudentCoursesPageState extends State<StudentCoursesPage> {
  late Future<dynamic> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    final courses = await Api.i.get('/courses') as List;
    final classes = await Api.i.get('/classes') as List;
    return {'courses': courses, 'classes': classes};
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _register(Map cls) async {
    if (!await confirm(context, 'Đăng ký lớp "${cls['name']}"?')) return;
    if (!mounted) return;
    final ok = await guard(context, () => Api.i.post('/classes/${cls['id']}/enroll'));
    if (ok && mounted) {
      Navigator.pop(context);
      toast(context, 'Đăng ký thành công!');
      _reload();
    }
  }

  void _openClasses(Map course, List classes) {
    final open = classes.where((c) => c['course_id'] == course['id'] && c['status'] == 'OPEN').toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        builder: (ctx, scrollCtl) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Các lớp của "${course['name']}"',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Expanded(
              child: open.isEmpty
                  ? const EmptyState('Hiện chưa có lớp nào đang mở đăng ký')
                  : ListView.builder(
                      controller: scrollCtl,
                      itemCount: open.length,
                      itemBuilder: (_, i) {
                        final c = open[i] as Map;
                        final full = (c['enrolled'] as num) >= (c['max_students'] as num);
                        return SoftCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            MetaRow(Icons.person_outline, 'GV: ${c['teacher_name'] ?? 'chưa phân công'}'),
                            MetaRow(Icons.schedule, '${c['schedule'] ?? 'Chưa có lịch'}'),
                            MetaRow(Icons.groups_outlined, 'Sĩ số ${c['enrolled']}/${c['max_students']}'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: full ? null : () => _register(c),
                                child: Text(full ? 'Lớp đã đầy' : 'Đăng ký lớp này'),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Loader(
        future: _f,
        onRetry: _reload,
        builder: (data) {
          final d = data as Map;
          final courses = d['courses'] as List;
          final classes = d['classes'] as List;
          if (courses.isEmpty) return const EmptyState('Trung tâm chưa có khóa học nào');
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _f;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: courses.length,
              itemBuilder: (_, i) {
                final c = courses[i] as Map;
                final openCount =
                    classes.where((x) => x['course_id'] == c['id'] && x['status'] == 'OPEN').length;
                return SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const IconBox(Icons.menu_book_outlined, AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('${c['level'] ?? ''} • ${c['duration_weeks'] ?? 0} tuần',
                              style: const TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                    if (c['description'] != null) ...[
                      const SizedBox(height: 10),
                      Text('${c['description']}', style: const TextStyle(color: AppColors.muted)),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Text(vnd(c['fee']),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 15)),
                      const Spacer(),
                      Text(openCount > 0 ? '$openCount lớp đang mở' : 'Chưa có lớp mở',
                          style: TextStyle(
                              color: openCount > 0 ? AppColors.ok : AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () => _openClasses(c, classes),
                        child: const Text('Xem lớp & Đăng ký'),
                      ),
                    ),
                  ]),
                );
              },
            ),
          );
        },
      );
}
