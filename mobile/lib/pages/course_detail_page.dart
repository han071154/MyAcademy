import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_page.dart';
import 'student_pay_page.dart';

/// Học viên: chi tiết 1 khóa học + các lớp đang mở. Đăng ký xong chuyển thẳng sang đóng học phí.
class CourseDetailPage extends StatefulWidget {
  final Map course;
  const CourseDetailPage({super.key, required this.course});
  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  late Future<Map<String, dynamic>> _f = _load();

  Map get _c => widget.course;

  Future<Map<String, dynamic>> _load() async {
    final all = (await Api.i.get('/classes') as List).cast<Map>();
    final mine = (await Api.i.get('/my/classes') as List).cast<Map>();
    final classes = all.where((x) => x['course_id'] == _c['id']).toList();
    // Lớp (chưa kết thúc) của khóa này mà học viên đã đăng ký: mỗi khóa chỉ được 1 lớp.
    final joined = mine.where((x) => x['course_id'] == _c['id'] && x['status'] != 'CLOSED').toList();
    // Lớp đang có chuyển khoản chờ xác nhận: không cho tự hủy (server cũng chặn).
    final pending = joined.isEmpty
        ? <String>{}
        : (await Api.i.paymentRequests(status: 'PENDING').catchError((_) => []))
            .map((r) => '${r['class_id']}')
            .toSet();
    return {'classes': classes, 'joined': joined, 'pending': pending};
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _register(Map cls) async {
    final ok = await confirm(
        context,
        'Đăng ký lớp "${cls['name']}"?\nHọc phí: ${vnd(cls['fee'])}. Bạn có thể đóng ngay bằng chuyển khoản.\n'
        'Lưu ý: chỗ của bạn được giữ 3 ngày, quá hạn chưa đóng học phí thì đăng ký tự hủy.');
    if (!ok || !mounted) return;
    if (!await guard(context, () => Api.i.post('/classes/${cls['id']}/enroll'))) return;
    if (!mounted) return;
    // Đăng ký xong → sang màn đóng học phí, đóng xong (hoặc để sau) → "Lớp học của tôi".
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => StudentPayPage(classData: cls, afterRegister: true)),
    );
  }

  Future<void> _cancel(Map cls) async {
    if (!await confirm(context, 'Hủy đăng ký lớp "${cls['name']}"?')) return;
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/my/classes/${cls['id']}'))) {
      if (mounted) toast(context, 'Đã hủy đăng ký');
      _reload();
    }
  }

  Widget _info(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppColors.muted)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _header() => SoftCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconBox(Icons.menu_book_outlined, AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${_c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
          ]),
          const SizedBox(height: 14),
          _info(Icons.signal_cellular_alt, 'Trình độ', '${_c['level'] ?? 'Không yêu cầu'}'),
          _info(Icons.timelapse, 'Thời lượng', '${_c['duration_weeks'] ?? '—'} tuần'),
          _info(Icons.payments_outlined, 'Học phí', vnd(_c['fee'])),
          const SizedBox(height: 10),
          const Text('Giới thiệu khóa học', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            (_c['description'] ?? '').toString().trim().isEmpty ? 'Chưa có mô tả.' : '${_c['description']}',
            style: const TextStyle(height: 1.4),
          ),
        ]),
      );

  Widget _classCard(Map c, List joined, Set pending) {
    final mine = joined.cast<Map?>().firstWhere((j) => j!['id'] == c['id'], orElse: () => null);
    final isMine = mine != null;
    final paid = num.tryParse('${mine?['paid'] ?? 0}') ?? 0;
    final hasPending = pending.contains('${c['id']}');
    final otherJoined = joined.where((j) => j['id'] != c['id']).toList();
    final full = (c['enrolled'] as num) >= (c['max_students'] as num);
    final start = DateTime.tryParse('${c['start_date'] ?? ''}');
    final today = DateUtils.dateOnly(DateTime.now());
    final started = start != null && !start.isAfter(today);
    final open = c['status'] == 'OPEN' && !started;

    Widget action;
    if (isMine) {
      action = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          onPressed: () => HomePage.goToTab(context, 1),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Đã đăng ký • Vào Lớp học của tôi'),
        ),
        // Chỉ tự hủy được khi lớp chưa khai giảng, chưa đóng tiền, không có chuyển khoản chờ xác nhận.
        if (open && paid <= 0 && !hasPending)
          TextButton(
            onPressed: () => _cancel(c),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Hủy đăng ký'),
          )
        else if (open)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              hasPending
                  ? 'Bạn có khoản chuyển khoản đang chờ xác nhận. Muốn hủy lớp, vui lòng liên hệ trung tâm.'
                  : 'Bạn đã đóng học phí. Muốn hủy lớp, vui lòng liên hệ trung tâm.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
      ]);
    } else if (otherJoined.isNotEmpty) {
      action = Text('Bạn đã đăng ký lớp "${otherJoined.first['name']}" của khóa này',
          style: const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic));
    } else {
      action = FilledButton(
        onPressed: !open || full ? null : () => _register(c),
        child: Text(started
            ? 'Lớp đã khai giảng'
            : (!open ? 'Không nhận đăng ký' : (full ? 'Lớp đã đầy' : 'Đăng ký lớp này'))),
      );
    }

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          // Chỉ ghi "Đang học" cho lớp mình đã đăng ký; lớp khác ghi "Đang diễn ra" để không hiểu nhầm.
          Pill(classStatusLabel(c['status'], role: isMine ? 'STUDENT' : null), statusColor(c['status'])),
        ]),
        const SizedBox(height: 8),
        MetaRow(Icons.person_outline, 'Giảng viên: ${c['teacher_name'] ?? 'chưa phân công'}'),
        MetaRow(Icons.schedule, 'Lịch học: ${c['schedule'] ?? 'chưa có lịch'}'),
        MetaRow(Icons.meeting_room_outlined, 'Phòng: ${c['room'] ?? '—'}'),
        if (c['start_date'] != null)
          MetaRow(Icons.event_outlined, 'Khai giảng ${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}'),
        MetaRow(Icons.groups_outlined, 'Sĩ số ${c['enrolled']}/${c['max_students']}'),
        const SizedBox(height: 12),
        action,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chi tiết khóa học')),
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final d = data as Map;
            final classes = (d['classes'] as List).cast<Map>();
            final joined = d['joined'] as List;
            final pending = d['pending'] as Set;
            // Lớp đang mở lên trước, lớp đã kết thúc ẩn đi.
            final shown = classes.where((c) => c['status'] != 'CLOSED').toList()
              ..sort((a, b) => (a['status'] == 'OPEN' ? 0 : 1).compareTo(b['status'] == 'OPEN' ? 0 : 1));
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _f;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _header(),
                  const SizedBox(height: 20),
                  const Text('Các lớp học', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 10),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState('Hiện chưa có lớp nào của khóa học này'),
                    )
                  else
                    for (final c in shown) _classCard(c, joined, pending),
                ],
              ),
            );
          },
        ),
      );
}
