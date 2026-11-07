import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'course_detail_page.dart';

/// Học viên: danh sách khóa học của trung tâm. Bấm vào 1 khóa để xem chi tiết và đăng ký lớp.
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
    final mine = await Api.i.get('/my/classes') as List;
    // Khóa học mà học viên đang có lớp (chưa kết thúc).
    final myCourses = mine.where((c) => c['status'] != 'CLOSED').map((c) => c['course_id']).toSet();
    return {'courses': courses, 'classes': classes, 'myCourses': myCourses};
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _open(Map course) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Loader(
        future: _f,
        onRetry: _reload,
        builder: (data) {
          final d = data as Map;
          final courses = d['courses'] as List;
          final classes = d['classes'] as List;
          final myCourses = d['myCourses'] as Set;
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
                final joined = myCourses.contains(c['id']);
                return SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  onTap: () => _open(c),
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
                      if (joined)
                        const Pill('Đã đăng ký', AppColors.ok)
                      else
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
                        onPressed: () => _open(c),
                        child: Text(joined ? 'Xem chi tiết khóa học' : 'Xem chi tiết & Đăng ký'),
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
