import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class StudentAssignmentDetailPage extends StatefulWidget {
  final Map assignment;
  const StudentAssignmentDetailPage({super.key, required this.assignment});

  @override
  State<StudentAssignmentDetailPage> createState() => _StudentAssignmentDetailPageState();
}

class _StudentAssignmentDetailPageState extends State<StudentAssignmentDetailPage> {
  late Future<dynamic> _f = _load();
  bool _submitting = false;

  Uint8List? _pickedBytes;
  String? _pickedName;
  String? _pickedMime;
  final _notesCtrl = TextEditingController();

  Future<dynamic> _load() => Api.i.get('/assignments/${widget.assignment['id']}/my-submission');

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedBytes = bytes;
        _pickedName = file.name;
        _pickedMime = file.mimeType ?? 'image/jpeg';
      });
    }
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isNotEmpty) {
      final f = files.first;
      final bytes = await f.readAsBytes();
      setState(() {
        _pickedBytes = bytes;
        _pickedName = f.name;
        _pickedMime = f.name.contains('.') ? 'application/${f.name.split('.').last}' : 'application/octet-stream';
      });
    }
  }

  Future<void> _submit() async {
    if (_pickedBytes == null && _notesCtrl.text.trim().isEmpty) {
      toast(context, 'Vui lòng chọn ảnh/tệp nộp bài hoặc nhập nội dung');
      return;
    }

    setState(() => _submitting = true);
    try {
      String? fileUrl;
      String? fileName;
      if (_pickedBytes != null) {
        fileName = _pickedName ?? 'submission_${DateTime.now().millisecondsSinceEpoch}';
        fileUrl = await Api.i.uploadFile(fileName, _pickedBytes!, mimeType: _pickedMime);
      }

      await Api.i.post('/assignments/${widget.assignment['id']}/submit', {
        // Gửi cả khi null: nộp lại chỉ có chữ thì xóa tệp của lần nộp trước.
        'file_url': fileUrl,
        'file_name': fileName,
        'notes': _notesCtrl.text.trim(),
      });

      if (mounted) {
        toast(context, 'Nộp bài tập thành công!');
        setState(() {
          _pickedBytes = null;
          _pickedName = null;
          _pickedMime = null;
          _notesCtrl.clear();
        });
        _reload();
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi nộp bài: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _notice(IconData icon, Color color, String text) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tint(color), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _previewWidget(String? url, String? name) => FilePreview(url: url, name: name, height: 220);

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final due = a['due_date'] == null ? null : DateTime.tryParse('${a['due_date']}');
    final isOverdue = due != null && due.isBefore(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết bài tập')),
      body: FutureBuilder(
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
                  const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.danger),
                  const SizedBox(height: 12),
                  Text('Không tải được bài nộp của bạn:\n${snap.error}',
                      textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _reload, child: const Text('Thử lại')),
                ]),
              ),
            );
          }

          final submission = snap.data as Map?;
          final isGraded = submission != null && submission['score'] != null;
          final submittedAt = submission == null ? null : DateTime.tryParse('${submission['submitted_at']}');
          final isLate = due != null && submittedAt != null && submittedAt.isAfter(due);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Thông tin đề bài
              SoftCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text('${a['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    ),
                    if (submission != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isGraded ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isGraded ? const Color(0xFF93C5FD) : const Color(0xFF6EE7B7)),
                        ),
                        child: Text(
                          isGraded
                              ? 'Điểm: ${submission['score']}/10'
                              : (isLate ? 'Nộp muộn' : 'Đã nộp bài'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: isGraded ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOverdue ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isOverdue ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D)),
                        ),
                        child: Text(
                          isOverdue ? 'Quá hạn' : 'Chưa nộp',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isOverdue ? AppColors.danger : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  if (due != null)
                    MetaRow(
                      Icons.schedule,
                      'Hạn nộp: ${fmtDateTime(due.toIso8601String())}',
                    ),
                  const SizedBox(height: 12),
                  const Text('Yêu cầu bài tập:', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  Text(
                    a['description'] != null && a['description'].toString().trim().isNotEmpty
                        ? '${a['description']}'
                        : 'Không có ghi chú thêm.',
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  if (a['attachment_url'] != null) ...[
                    const SizedBox(height: 14),
                    const Text('Tệp đề bài đính kèm:', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                    const SizedBox(height: 6),
                    _previewWidget(a['attachment_url']?.toString(), a['attachment_name']?.toString()),
                  ],
                ]),
              ),

              const SizedBox(height: 20),

              // Nếu đã có điểm và nhận xét
              if (isGraded) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Row(children: [
                        Icon(Icons.stars_rounded, color: AppColors.ok, size: 24),
                        SizedBox(width: 8),
                        Text('ĐÁNH GIÁ TỪ GIẢNG VIÊN',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ok)),
                      ]),
                      Text('${submission['score']} / 10',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ok)),
                    ]),
                    if (submission['feedback'] != null && submission['feedback'].toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Nhận xét:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Text('"${submission['feedback']}"',
                          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Color(0xFF166534))),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Nếu đã nộp trước đó -> hiển thị bài nộp
              if (submission != null) ...[
                SoftCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Bài nộp của bạn', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Nộp lúc: ${fmtDateTime(submission['submitted_at'])}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                    if (isLate) ...[
                      const SizedBox(height: 6),
                      const Pill('Nộp muộn (sau hạn chót)', AppColors.danger),
                    ],
                    if (submission['notes'] != null && submission['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('${submission['notes']}', style: const TextStyle(fontSize: 14)),
                    ],
                    if (submission['file_url'] != null) ...[
                      const SizedBox(height: 12),
                      _previewWidget(submission['file_url']?.toString(), submission['file_name']?.toString()),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // Bài đã chấm điểm thì khóa, không cho nộp lại.
              if (isGraded)
                _notice(Icons.lock_outline, AppColors.muted,
                    'Bài tập đã được chấm điểm nên không thể nộp lại. Nếu cần, hãy liên hệ giảng viên.')
              // Qua hạn nộp thì khóa, không cho nộp / nộp lại (server cũng chặn).
              else if (isOverdue)
                _notice(
                    Icons.lock_clock_outlined,
                    AppColors.danger,
                    submission == null
                        ? 'Đã hết hạn nộp bài lúc ${fmtDateTime(due.toIso8601String())}. Bạn không thể nộp nữa, '
                            'nếu có lý do chính đáng hãy liên hệ giảng viên.'
                        : 'Đã hết hạn nộp bài lúc ${fmtDateTime(due.toIso8601String())}, bài nộp ở trên là bài cuối cùng '
                            'của bạn và không thể nộp lại.')
              else ...[
                // Form nộp / nộp lại bài tập
                Text(
                  submission == null ? 'Nộp bài tập' : 'Nộp lại bài tập',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                if (submission != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Bài nộp mới sẽ thay thế hoàn toàn bài nộp cũ (cả nội dung và tệp).',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                if (due != null)
                  _notice(Icons.schedule, AppColors.amber,
                      'Hạn nộp: ${fmtDateTime(due.toIso8601String())}. Sau thời điểm này sẽ không nộp được nữa.'),
                const SizedBox(height: 10),
                SoftCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: deco(
                        labelText: 'Ghi chú / Câu trả lời bài tập',
                        hintText: 'Nhập nội dung bài làm hoặc lời nhắn gửi giảng viên...',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Nút chọn đính kèm
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Chọn ảnh'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Chụp ảnh'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: const Text('Tệp file'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ]),

                    // Hiển thị tệp vừa chọn
                    if (_pickedBytes != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_pickedName ?? 'Tệp đã chọn',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
                            onPressed: () => setState(() {
                              _pickedBytes = null;
                              _pickedName = null;
                              _pickedMime = null;
                            }),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(_submitting ? 'Đang tải lên...' : (submission == null ? 'Nộp bài ngay' : 'Nộp lại bài tập')),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

