import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'teacher_assignment_grading_page.dart';

/// Chi tiết lớp: thông tin + danh sách học viên + điểm danh + bài tập (giao bài & chấm điểm).
class ClassDetailPage extends StatelessWidget {
  final Map c;
  final int initialTabIndex;
  const ClassDetailPage({super.key, required this.c, this.initialTabIndex = 0});

  Widget _info() => SoftCard(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['course_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Pill(classStatusLabel(c['status'], role: Api.i.role), statusColor(c['status'])),
          ]),
          MetaRow(Icons.person_outline, 'Giảng viên: ${c['teacher_name'] ?? 'chưa phân công'}'),
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
      initialIndex: initialTabIndex,
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${c['name']}'),
          bottom: styledTabs(['Học viên', 'Điểm danh', 'Bài tập']),
        ),
        body: Column(children: [
          _info(),
          Expanded(
            child: TabBarView(children: [
              _StudentsTab(classId: id),
              _AttendanceTab(classId: id),
              _TeacherAssignmentsTab(classData: c),
            ]),
          ),
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
            if (list.isEmpty) return const EmptyState('Lớp chưa có học viên nào');
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = list[i] as Map;
                return SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    InitialAvatar(s['full_name']),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${s['email']}${s['phone'] != null ? ' • ${s['phone']}' : ''}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    ),
                    if (_admin)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 20),
                        onPressed: () => _remove(s),
                      ),
                  ]),
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
    if (mounted) setState(() {});
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('Ngày: ${fmtDate(_d)}'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                for (final k in _st.keys.toList()) {
                  _st[k] = 'PRESENT';
                }
                setState(() {});
              },
              child: const Text('Tất cả có mặt'),
            ),
          ]),
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

// ---------------- Tab bài tập (Giáo viên) ----------------
class _TeacherAssignmentsTab extends StatefulWidget {
  final Map classData;
  const _TeacherAssignmentsTab({required this.classData});

  @override
  State<_TeacherAssignmentsTab> createState() => _TeacherAssignmentsTabState();
}

class _TeacherAssignmentsTabState extends State<_TeacherAssignmentsTab> {
  late Future<dynamic> _f = _load();

  int get _classId => (widget.classData['id'] as num).toInt();

  Future<dynamic> _load() => Api.i.get('/classes/$_classId/assignments');

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _createAssignment() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    TimeOfDay dueTime = const TimeOfDay(hour: 23, minute: 59);
    Uint8List? pickedBytes;
    String? pickedName;
    String? pickedMime;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Giao bài tập mới', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: deco(labelText: 'Tiêu đề bài tập *', hintText: 'VD: Bài tập ngữ pháp tuần 3...'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: deco(labelText: 'Mô tả / Đề bài', hintText: 'Nhập yêu cầu và hướng dẫn làm bài...'),
                ),
                const SizedBox(height: 14),
                const Text('Hạn nộp bài:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: due,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setSheetState(() => due = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(DateFormat('dd/MM/yyyy').format(due),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: dueTime);
                        if (t != null) setSheetState(() => dueTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(dueTime.format(context),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('Tệp đính kèm (nếu có):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final f = await picker.pickImage(source: ImageSource.gallery);
                        if (f != null) {
                          final b = await f.readAsBytes();
                          setSheetState(() {
                            pickedBytes = b;
                            pickedName = f.name;
                            pickedMime = f.mimeType ?? 'image/jpeg';
                          });
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: const Text('Đính kèm ảnh',
                          style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final files = await FilePicker.pickFiles();
                        if (files.isNotEmpty) {
                          final f = files.first;
                          final b = await f.readAsBytes();
                          setSheetState(() {
                            pickedBytes = b;
                            pickedName = f.name;
                            pickedMime = f.name.contains('.') ? 'application/${f.name.split('.').last}' : null;
                          });
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.attach_file, size: 16),
                      label: const Text('Đính kèm file',
                          style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
                if (pickedName != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle, size: 16, color: AppColors.ok),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedName!,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => setSheetState(() {
                          pickedBytes = null;
                          pickedName = null;
                          pickedMime = null;
                        }),
                        child: const Icon(Icons.close, size: 18, color: AppColors.muted),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (titleCtrl.text.trim().isEmpty) {
                              toast(context, 'Vui lòng nhập tiêu đề bài tập');
                              return;
                            }

                            setSheetState(() => saving = true);
                            try {
                              String? fileUrl;
                              if (pickedBytes != null && pickedName != null) {
                                fileUrl = await Api.i.uploadFile(pickedName!, pickedBytes!, mimeType: pickedMime);
                              }

                              final finalDue = DateTime(due.year, due.month, due.day, dueTime.hour, dueTime.minute);
                              await Api.i.post('/assignments', {
                                'class_id': _classId,
                                'title': titleCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'due_date': finalDue.toIso8601String(),
                                if (fileUrl != null) 'attachment_url': fileUrl,
                                if (pickedName != null) 'attachment_name': pickedName,
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                toast(context, 'Đã giao bài tập mới!');
                                _reload();
                              }
                            } catch (e) {
                              if (mounted) toast(context, 'Lỗi tạo bài tập: $e');
                            } finally {
                              if (mounted) setSheetState(() => saving = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      saving ? 'Đang tạo...' : 'Giao bài tập',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAssignment(Map a) async {
    if (!await confirm(context, 'Xóa bài tập "${a['title']}"? Các bài nộp của học viên cho bài này cũng sẽ bị xóa.')) {
      return;
    }
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/assignments/${a['id']}')) && mounted) {
      toast(context, 'Đã xóa bài tập');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAssignment,
        icon: const Icon(Icons.add_task),
        label: const Text('Giao bài tập'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
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
                    const Icon(Icons.error_outline, size: 44, color: AppColors.danger),
                    const SizedBox(height: 12),
                    Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: _reload, child: const Text('Thử lại')),
                  ]),
                ),
              );
            }

            final list = (snap.data as List?) ?? [];
            if (list.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SoftCard(
                    padding: EdgeInsets.all(32),
                    child: Column(children: [
                      IconBox(Icons.assignment_outlined, AppColors.primary, size: 56),
                      SizedBox(height: 16),
                      Text('Chưa có bài tập nào', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('Hãy bấm nút "Giao bài tập" bên dưới để giao nhiệm vụ học tập cho học viên.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final a = list[i] as Map;
                final due = a['due_date'] == null ? null : DateTime.tryParse('${a['due_date']}');
                final subCount = (a['submission_count'] as num?)?.toInt() ?? 0;
                final totalSt = (a['total_students'] as num?)?.toInt() ?? 0;

                return SoftCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text('${a['title']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                        onPressed: () => _deleteAssignment(a),
                      ),
                    ]),
                    if (due != null) ...[
                      const SizedBox(height: 4),
                      MetaRow(Icons.schedule, 'Hạn nộp: ${fmtDateTime(due.toIso8601String())}'),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.people_outline, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('Đã nộp bài: $subCount / $totalSt học viên',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => TeacherAssignmentGradingPage(assignment: a)),
                          );
                          _reload();
                        },
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Xem bài nộp & Chấm điểm'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
