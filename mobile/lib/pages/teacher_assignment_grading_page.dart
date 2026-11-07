import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class TeacherAssignmentGradingPage extends StatefulWidget {
  final Map assignment;
  const TeacherAssignmentGradingPage({super.key, required this.assignment});

  @override
  State<TeacherAssignmentGradingPage> createState() => _TeacherAssignmentGradingPageState();
}

class _TeacherAssignmentGradingPageState extends State<TeacherAssignmentGradingPage> {
  late Future<List<dynamic>> _f = _load();

  int get _assignmentId => (widget.assignment['id'] as num).toInt();
  int get _classId => (widget.assignment['class_id'] as num).toInt();

  Future<List<dynamic>> _load() => Future.wait([
        Api.i.get('/classes/$_classId/students'),
        Api.i.get('/assignments/$_assignmentId/submissions'),
      ]);

  void _reload() => setState(() {
        _f = _load();
      });

  Widget _previewFile(String? url, String? name) => FilePreview(url: url, name: name, height: 260);

  void _openGradingSheet(BuildContext context, Map student, Map? submission) {
    if (submission == null) {
      toast(context, 'Học viên chưa nộp bài');
      return;
    }

    final scoreCtrl = TextEditingController(text: submission['score'] != null ? '${submission['score']}' : '');
    final feedbackCtrl = TextEditingController(text: submission['feedback'] ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Chấm bài: ${student['full_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(
                        'Nộp lúc: ${fmtDateTime(submission['submitted_at'])}'
                        '${submission['is_late'] == true ? ' • Nộp muộn' : ''}',
                        style: TextStyle(
                            color: submission['is_late'] == true ? AppColors.danger : AppColors.muted, fontSize: 12)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
              const Divider(height: 24),

              // Nội dung ghi chú của học viên
              if (submission['notes'] != null && submission['notes'].toString().trim().isNotEmpty) ...[
                const Text('Nội dung bài làm / Ghi chú:', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text('${submission['notes']}', style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
                const SizedBox(height: 14),
              ],

              // Ảnh hoặc file nộp
              if (submission['file_url'] != null) ...[
                const Text('Tệp / Ảnh bài nộp:', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                const SizedBox(height: 6),
                _previewFile(submission['file_url']?.toString(), submission['file_name']?.toString()),
                const SizedBox(height: 16),
              ],

              // Nhập điểm
              TextField(
                controller: scoreCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco(
                  labelText: 'Điểm số (Thang điểm 10) *',
                  hintText: 'VD: 8.5, 9, 10...',
                  prefixIcon: const Icon(Icons.stars_rounded, color: AppColors.ok),
                ),
              ),
              const SizedBox(height: 12),

              // Nhập nhận xét
              TextField(
                controller: feedbackCtrl,
                maxLines: 3,
                decoration: deco(
                  labelText: 'Nhận xét của giảng viên',
                  hintText: 'Nhập lời khuyên, nhận xét cho bài làm của học viên...',
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final scoreVal = num.tryParse(scoreCtrl.text.trim());
                          if (scoreVal == null || scoreVal < 0 || scoreVal > 10) {
                            toast(context, 'Điểm số phải từ 0 đến 10');
                            return;
                          }

                          setSheetState(() => saving = true);
                          try {
                            await Api.i.put('/submissions/${submission['id']}/grade', {
                              'score': scoreVal,
                              'feedback': feedbackCtrl.text.trim(),
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              toast(context, 'Đã chấm điểm thành công!');
                              _reload();
                            }
                          } catch (e) {
                            if (mounted) toast(context, 'Lỗi chấm điểm: $e');
                          } finally {
                            if (mounted) setSheetState(() => saving = false);
                          }
                        },
                  icon: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(saving ? 'Đang lưu...' : 'Lưu điểm & Nhận xét'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final due = a['due_date'] == null ? null : DateTime.tryParse('${a['due_date']}');

    return Scaffold(
      appBar: AppBar(title: const Text('Chấm điểm bài tập')),
      body: FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }

          final results = snap.data as List<dynamic>;
          final students = (results[0] as List?) ?? [];
          final submissions = (results[1] as List?) ?? [];

          final subMap = <int, Map>{};
          for (final s in submissions) {
            subMap[(s['student_id'] as num).toInt()] = s as Map;
          }

          final gradedCount = submissions.where((s) => s['score'] != null).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Thông tin bài tập
              SoftCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 6),
                  if (due != null)
                    Text('Hạn nộp: ${fmtDateTime(due.toIso8601String())}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const Divider(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    Column(children: [
                      Text('${students.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const Text('Sĩ số lớp', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                    Column(children: [
                      Text('${submissions.length}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      const Text('Đã nộp bài', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                    Column(children: [
                      Text('$gradedCount',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ok)),
                      const Text('Đã chấm điểm', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ]),
                ]),
              ),

              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Danh sách học viên', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('${students.length} học viên', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),

              if (students.isEmpty)
                const SoftCard(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Lớp dạy chưa có học viên nào.', style: TextStyle(color: AppColors.muted)),
                  ),
                )
              else
                for (final st in students) ...[
                  Builder(builder: (_) {
                    final sId = (st['student_id'] as num).toInt();
                    final sub = subMap[sId];
                    final isSubmitted = sub != null;
                    final isGraded = isSubmitted && sub['score'] != null;

                    return SoftCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        InitialAvatar(st['full_name'], radius: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            if (isSubmitted)
                              Text(
                                  'Nộp lúc: ${fmtDateTime(sub['submitted_at'])}'
                                  '${sub['is_late'] == true ? ' • Nộp muộn' : ''}',
                                  style: TextStyle(
                                      color: sub['is_late'] == true ? AppColors.danger : AppColors.muted,
                                      fontSize: 12))
                            else
                              const Text('Chưa nộp bài', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                          ]),
                        ),
                        if (isGraded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF93C5FD)),
                            ),
                            child: Text('${sub['score']} đ',
                                style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        FilledButton(
                          onPressed: isSubmitted ? () => _openGradingSheet(context, st as Map, sub) : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: isGraded ? const Color(0xFF0F766E) : AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(isGraded ? 'Sửa điểm' : 'Chấm bài', style: const TextStyle(fontSize: 12)),
                        ),
                      ]),
                    );
                  }),
                ],
            ],
          );
        },
      ),
    );
  }
}

