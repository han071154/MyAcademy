import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'class_detail_page.dart';

/// Admin: quản lý toàn bộ lớp. mine = true: lớp của giáo viên/học viên đang đăng nhập.
class ClassesPage extends StatefulWidget {
  final bool mine;
  const ClassesPage({super.key, this.mine = false});
  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  late Future<dynamic> _f = _load();

  bool get _admin => Api.i.role == 'ADMIN' && !widget.mine;
  Future<dynamic> _load() => Api.i.get(widget.mine ? '/my/classes' : '/classes');
  void _reload() => setState(() { _f = _load(); });

  Future<void> _edit([Map? c]) async {
    List courses, teachers;
    try {
      courses = await Api.i.get('/courses') as List;
      teachers = await Api.i.get('/users', query: {'role': 'TEACHER'}) as List;
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    if (!mounted) return;
    final v = await showForm(
      context,
      c == null ? 'Thêm lớp học' : 'Sửa lớp học',
      [
        const Field('name', 'Tên lớp', required: true),
        Field('course_id', 'Khóa học',
            type: FieldType.dropdown,
            required: true,
            options: [for (final x in courses) (x['id'] as Object, '${x['name']}')]),
        Field('teacher_id', 'Giáo viên',
            type: FieldType.dropdown,
            options: [for (final x in teachers) (x['id'] as Object, '${x['full_name']}')]),
        const Field('start_date', 'Ngày bắt đầu', type: FieldType.date),
        const Field('end_date', 'Ngày kết thúc', type: FieldType.date),
        const Field('schedule', 'Lịch học (VD: T2-T4 18:00-19:30)'),
        const Field('room', 'Phòng học'),
        const Field('max_students', 'Sĩ số tối đa', type: FieldType.number),
        Field('status', 'Trạng thái', type: FieldType.dropdown, required: true, options: opts(classStatus)),
      ],
      initial: c == null ? {'status': 'OPEN', 'max_students': 20} : Map<String, dynamic>.from(c),
    );
    if (v == null || !mounted) return;
    final ok = await guard(
        context, () => c == null ? Api.i.post('/classes', v) : Api.i.put('/classes/${c['id']}', v));
    if (ok) _reload();
  }

  Future<void> _delete(Map c) async {
    if (!await confirm(context, 'Xóa lớp "${c['name']}"? Danh sách ghi danh, điểm danh, học phí của lớp cũng bị xóa.')) {
      return;
    }
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/classes/${c['id']}'))) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton:
            _admin ? FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)) : null,
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final list = data as List;
            if (list.isEmpty) return const EmptyState('Chưa có lớp học');
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _f;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4, bottom: 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i] as Map;
                  final room = c['room'] == null ? '' : '  •  P.${c['room']}';
                  return SoftCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassDetailPage(c: c)));
                      if (mounted) _reload();
                    },
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['name']}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 4),
                          MetaRow(Icons.person_outline, 'GV: ${c['teacher_name'] ?? 'chưa phân công'}'),
                          MetaRow(Icons.schedule, '${c['schedule'] ?? 'Chưa có lịch'}$room'),
                          MetaRow(Icons.groups_outlined, 'Sĩ số ${c['enrolled']}/${c['max_students']}'),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Pill(classStatus[c['status']] ?? '${c['status']}', statusColor(c['status'])),
                        if (_admin)
                          PopupMenuButton<String>(
                            onSelected: (s) => s == 'edit' ? _edit(c) : _delete(c),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(value: 'delete', child: Text('Xóa')),
                            ],
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(top: 14, right: 6),
                            child: Icon(Icons.chevron_right, color: AppColors.muted),
                          ),
                      ]),
                    ]),
                  );
                },
              ),
            );
          },
        ),
      );
}
