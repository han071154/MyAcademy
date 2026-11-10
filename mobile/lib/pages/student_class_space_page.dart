import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'student_assignment_detail_page.dart';
import 'student_pay_page.dart';

/// Học viên chỉ vào lớp khi đã có ít nhất 1 khoản học phí được ghi nhận (hoặc lớp miễn phí).
/// Server cũng chặn theo đúng quy tắc này (database/class_access.sql).
bool canEnterClass(Map c) =>
    (num.tryParse('${c['paid']}') ?? 0) > 0 || (num.tryParse('${c['fee']}') ?? 0) <= 0;

/// Mở không gian lớp; chưa đóng tiền thì báo lý do và gợi ý đóng học phí.
Future<void> openStudentClass(BuildContext context, Map c) async {
  if (canEnterClass(c)) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentClassSpacePage(classData: c)));
    return;
  }
  var pending = false;
  Map? rejected;
  try {
    final reqs = await Api.i.paymentRequests();
    pending = reqs.any((r) => '${r['class_id']}' == '${c['id']}' && r['status'] == 'PENDING');
    rejected = pending ? null : latestRejectedRequest(reqs, c['id']);
  } catch (_) {}
  if (!context.mounted) return;
  final pay = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(
          pending
              ? Icons.hourglass_top_rounded
              : (rejected != null ? Icons.cancel_rounded : Icons.lock_outline_rounded),
          color: rejected != null ? AppColors.danger : AppColors.amber),
      title: Text(pending ? 'Đang chờ xác nhận' : (rejected != null ? 'Chuyển khoản bị từ chối' : 'Lớp chưa mở')),
      content: Text(pending
          ? 'Bạn đã báo chuyển khoản cho lớp "${c['name']}". Lớp sẽ mở ngay khi trung tâm xác nhận đã nhận tiền.'
          : (rejected != null
              ? '${rejectedMessage(rejected)}\nLớp sẽ mở khi trung tâm xác nhận khoản đóng mới.'
              : 'Bạn cần đóng ít nhất một đợt học phí cho lớp "${c['name']}" và được trung tâm xác nhận thì mới vào lớp được.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(pending ? 'Đã hiểu' : 'Để sau')),
        if (!pending)
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(rejected != null ? 'Đóng lại học phí' : 'Đóng học phí')),
      ],
    ),
  );
  if (pay == true && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPayPage(classData: c)));
  }
}

class StudentClassSpacePage extends StatefulWidget {
  final Map classData;
  const StudentClassSpacePage({super.key, required this.classData});

  @override
  State<StudentClassSpacePage> createState() => _StudentClassSpacePageState();
}

class _StudentClassSpacePageState extends State<StudentClassSpacePage> {
  late Future<dynamic> _assignments = _loadAssignments();
  late Future<dynamic> _attendance = _loadAttendance();

  int get _classId => (widget.classData['id'] as num).toInt();

  /// Bài tập của lớp + bài nộp của tôi (để hiện trạng thái từng bài).
  Future<dynamic> _loadAssignments() async {
    final r = await Future.wait([Api.i.get('/classes/$_classId/assignments'), Api.i.get('/my/submissions')]);
    final mine = {for (final x in (r[1] as List)) '${x['assignment_id']}': x};
    return [for (final a in (r[0] as List)) {...(a as Map), '_sub': mine['${a['id']}']}];
  }

  Widget _statusPill(Map a, bool isOverdue) {
    final sub = a['_sub'] as Map?;
    if (sub == null) {
      return Pill(isOverdue ? 'Quá hạn' : 'Chưa nộp', isOverdue ? AppColors.danger : AppColors.amber);
    }
    if (sub['score'] != null) return Pill('Điểm ${sub['score']}', AppColors.ok);
    return const Pill('Đã nộp • chờ chấm', AppColors.primary);
  }
  Future<dynamic> _loadAttendance() => Api.i.get('/classes/$_classId/my-attendance');

  void _reloadAll() {
    setState(() {
      _assignments = _loadAssignments();
      _attendance = _loadAttendance();
    });
  }

  // ---------------- Tab 1: Bài tập ----------------
  Widget _tabAssignments() {
    return RefreshIndicator(
      onRefresh: () async => _reloadAll(),
      child: FutureBuilder(
        future: _assignments,
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
                  FilledButton.tonal(onPressed: _reloadAll, child: const Text('Thử lại')),
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
                  padding: EdgeInsets.all(28),
                  child: Column(children: [
                    IconBox(Icons.assignment_turned_in_outlined, AppColors.primary, size: 52),
                    SizedBox(height: 16),
                    Text('Chưa có bài tập nào', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    SizedBox(height: 8),
                    Text(
                      'Giảng viên chưa giao bài tập cho lớp này. Hãy quay lại sau nhé!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.4),
                    ),
                  ]),
                ),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final a = list[i] as Map;
              final due = a['due_date'] == null ? null : DateTime.tryParse('${a['due_date']}');
              final isOverdue = due != null && due.isBefore(DateTime.now());

              return SoftCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => StudentAssignmentDetailPage(assignment: a)),
                  );
                  _reloadAll();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const IconBox(Icons.task_alt_outlined, AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 4),
                        if (due != null)
                          Text(
                            'Hạn nộp: ${fmtDateTime(due.toIso8601String())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOverdue ? AppColors.danger : AppColors.muted,
                              fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                      ]),
                    ),
                    _statusPill(a, isOverdue),
                  ]),
                  if (a['description'] != null && a['description'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${a['description']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------- Tab 2: Điểm danh của tôi ----------------
  Widget _tabAttendance() {
    return RefreshIndicator(
      onRefresh: () async => _reloadAll(),
      child: FutureBuilder(
        future: _attendance,
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
                  FilledButton.tonal(onPressed: _reloadAll, child: const Text('Thử lại')),
                ]),
              ),
            );
          }

          final list = (snap.data as List?) ?? [];
          final present = list.where((x) => x['status'] == 'PRESENT').length;
          final lateCount = list.where((x) => x['status'] == 'LATE').length;
          final absent = list.where((x) => x['status'] == 'ABSENT').length;
          // Chưa có buổi nào được điểm danh thì chưa có tỷ lệ (không hiện 100%).
          final rate = list.isNotEmpty ? (((present + lateCount) / list.length) * 100).toStringAsFixed(0) : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Thẻ thống kê điểm danh
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('CHUYÊN CẦN CỦA BẠN',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(rate == null ? 'Chưa có buổi học' : 'Tỷ lệ: $rate%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Column(children: [
                        Text('$present', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                        const SizedBox(height: 2),
                        const Text('Có mặt', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    Expanded(
                      child: Column(children: [
                        Text('$lateCount', style: const TextStyle(color: Color(0xFFFFD58A), fontWeight: FontWeight.w800, fontSize: 22)),
                        const SizedBox(height: 2),
                        const Text('Đi muộn', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    Expanded(
                      child: Column(children: [
                        Text('$absent', style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w800, fontSize: 22)),
                        const SizedBox(height: 2),
                        const Text('Vắng mặt', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ]),
              ),

              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Lịch sử các buổi học', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${list.length} buổi', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),

              if (list.isEmpty)
                const SoftCard(
                  padding: EdgeInsets.all(24),
                  child: Column(children: [
                    Icon(Icons.event_available_outlined, size: 40, color: AppColors.muted),
                    SizedBox(height: 10),
                    Text('Chưa có dữ liệu điểm danh', style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Giảng viên chưa điểm danh buổi học nào cho bạn trong lớp này.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                )
              else
                for (final item in list) ...[
                  SoftCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      IconBox(
                        item['status'] == 'PRESENT'
                            ? Icons.check_circle_outline
                            : (item['status'] == 'LATE' ? Icons.access_time : Icons.cancel_outlined),
                        item['status'] == 'PRESENT'
                            ? AppColors.ok
                            : (item['status'] == 'LATE' ? AppColors.amber : AppColors.danger),
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Ngày: ${fmtDate(item['session_date'])}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          if (item['note'] != null && item['note'].toString().trim().isNotEmpty)
                            Text('Ghi chú: ${item['note']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      Pill(
                        item['status'] == 'PRESENT'
                            ? 'Có mặt'
                            : (item['status'] == 'LATE' ? 'Đi muộn' : 'Vắng mặt'),
                        item['status'] == 'PRESENT'
                            ? AppColors.ok
                            : (item['status'] == 'LATE' ? AppColors.amber : AppColors.danger),
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

  // ---------------- Tab 3: Thông tin lớp ----------------
  Widget _tabInfo() {
    final c = widget.classData;
    final fee = num.tryParse('${c['fee']}') ?? 0;
    final paid = num.tryParse('${c['paid']}') ?? 0;
    final debt = fee - paid;
    final dates = c['start_date'] == null ? null : '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              Pill(classStatusLabel(c['status'], role: 'STUDENT'), statusColor(c['status'])),
            ]),
            if (c['course_name'] != null) ...[
              const SizedBox(height: 4),
              Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            ],
            const Divider(height: 24),
            MetaRow(Icons.person_outline, 'Giảng viên: ${c['teacher_name'] ?? 'Chưa phân công'}'),
            MetaRow(Icons.schedule, 'Lịch học: ${c['schedule'] ?? 'Chưa có lịch'}'),
            if (c['room'] != null) MetaRow(Icons.meeting_room_outlined, 'Phòng học: ${c['room']}'),
            if (dates != null) MetaRow(Icons.date_range_outlined, 'Thời gian: $dates'),
          ]),
        ),
        const SizedBox(height: 16),

        // Học phí
        SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Học phí của lớp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Học phí gốc:', style: TextStyle(color: AppColors.muted)),
              Text(vnd(fee), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Đã thanh toán:', style: TextStyle(color: AppColors.muted)),
              Text(vnd(paid), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ok)),
            ]),
            const Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Còn nợ:', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(
                vnd(debt),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: debt > 0 ? AppColors.danger : AppColors.ok,
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.classData['name']}'),
          bottom: styledTabs(['Bài tập', 'Điểm danh', 'Thông tin lớp']),
        ),
        body: TabBarView(
          children: [
            _tabAssignments(),
            _tabAttendance(),
            _tabInfo(),
          ],
        ),
      ),
    );
  }
}

