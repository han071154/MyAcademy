import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Chi tiết lớp: thông tin + danh sách học viên + điểm danh.
/// Học viên chỉ xem thông tin lớp; giáo viên điểm danh; admin thêm/xóa học viên.
class ClassDetailPage extends StatelessWidget {
  final Map c;
  const ClassDetailPage({super.key, required this.c});

  Widget _info() => SoftCard(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['course_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Pill(classStatus[c['status']] ?? '${c['status']}', statusColor(c['status'])),
          ]),
          MetaRow(Icons.person_outline, 'Giáo viên: ${c['teacher_name'] ?? 'chưa phân công'}'),
          MetaRow(Icons.schedule, '${c['schedule'] ?? '—'}   Phòng: ${c['room'] ?? '—'}'),
          MetaRow(Icons.date_range_outlined, '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}'),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final id = (c['id'] as num).toInt();
    if (Api.i.role == 'STUDENT') {
      return Scaffold(appBar: AppBar(title: Text('${c['name']}')), body: ListView(children: [_info()]));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${c['name']}'),
          bottom: styledTabs(['Học viên', 'Điểm danh']),
        ),
        body: Column(children: [
          _info(),
          Expanded(child: TabBarView(children: [_StudentsTab(classId: id), _AttendanceTab(classId: id)])),
        ]),
      ),
    );
  }
}

// ---------------- Tab học viên ----------------
class _StudentsTab extends StatefulWidget {
  final int classId;
  const _StudentsTab({required this.classId});
  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  late Future<dynamic> _f = _load();
  List _current = [];

  bool get _admin => Api.i.role == 'ADMIN';
  Future<dynamic> _load() async {
    final r = await Api.i.get('/classes/${widget.classId}/students') as List;
    _current = r;
    return r;
  }

  void _reload() => setState(() { _f = _load(); });

  Future<void> _add() async {
    List all;
    try {
      all = await Api.i.get('/users', query: {'role': 'STUDENT'}) as List;
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    final joined = _current.map((e) => e['student_id']).toSet();
    final free = all.where((s) => s['active'] == true && !joined.contains(s['id'])).toList();
    if (!mounted) return;
    if (free.isEmpty) {
      toast(context, 'Không còn học viên nào để thêm');
      return;
    }
    final v = await showForm(context, 'Thêm học viên vào lớp', [
      Field('student_id', 'Học viên',
          type: FieldType.dropdown,
          required: true,
          options: [for (final s in free) (s['id'] as Object, '${s['full_name']} (${s['email']})')]),
    ]);
    if (v == null || !mounted) return;
    if (await guard(context, () => Api.i.post('/classes/${widget.classId}/enroll', v))) _reload();
  }

  Future<void> _remove(Map s) async {
    if (!await confirm(context, 'Xóa ${s['full_name']} khỏi lớp? (điểm danh, học phí của học viên trong lớp cũng bị xóa)')) {
      return;
    }
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/enrollments/${s['enrollment_id']}'))) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton:
            _admin ? FloatingActionButton(onPressed: _add, child: const Icon(Icons.person_add)) : null,
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final list = data as List;
            if (list.isEmpty) return const EmptyState('Lớp chưa có học viên');
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i] as Map;
                return SoftCard(
                  child: ListTile(
                    leading: InitialAvatar(s['full_name']),
                    title: Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s['phone'] ?? s['email']}', style: const TextStyle(color: AppColors.muted)),
                    trailing: _admin
                        ? IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _remove(s))
                        : null,
                  ),
                );
              },
            );
          },
        ),
      );
}

// ---------------- Tab điểm danh ----------------
class _AttendanceTab extends StatefulWidget {
  final int classId;
  const _AttendanceTab({required this.classId});
  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  DateTime _date = DateTime.now();
  final Map<int, String> _st = {}; // enrollment_id -> PRESENT / ABSENT / LATE
  late Future<dynamic> _f = _load();
  bool _saving = false;

  String get _d => DateFormat('yyyy-MM-dd').format(_date);

  Future<dynamic> _load() async {
    final r = await Api.i.get('/classes/${widget.classId}/attendance', query: {'date': _d}) as List;
    _st
      ..clear()
      ..addAll({for (final x in r) (x['enrollment_id'] as num).toInt(): (x['status'] ?? 'PRESENT') as String});
    if (mounted) setState(() {}); // vẽ lại nút "Lưu điểm danh" (nằm ngoài Loader) sau khi có dữ liệu
    return r;
  }

  void _reload() => setState(() { _f = _load(); });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) {
      _date = d;
      _reload();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await guard(
      context,
      () => Api.i.post('/attendance', {
        'class_id': widget.classId,
        'date': _d,
        'records': [
          for (final e in _st.entries) {'enrollment_id': e.key, 'status': e.value}
        ],
      }),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) toast(context, 'Đã lưu điểm danh ngày ${fmtDate(_d)}');
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          leading: const Icon(Icons.event),
          title: Text('Ngày ${fmtDate(_d)}'),
          trailing: TextButton(onPressed: _pickDate, child: const Text('Đổi ngày')),
        ),
        Expanded(
          child: Loader(
            future: _f,
            onRetry: _reload,
            builder: (data) {
              final list = data as List;
              if (list.isEmpty) return const EmptyState('Lớp chưa có học viên');
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i] as Map;
                  final id = (s['enrollment_id'] as num).toInt();
                  return SoftCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'PRESENT', label: Text('Có mặt')),
                          ButtonSegment(value: 'LATE', label: Text('Trễ')),
                          ButtonSegment(value: 'ABSENT', label: Text('Vắng')),
                        ],
                        selected: {_st[id] ?? 'PRESENT'},
                        onSelectionChanged: (v) => setState(() => _st[id] = v.first),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving || _st.isEmpty ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Lưu điểm danh'),
            ),
          ),
        ),
      ]);
}
