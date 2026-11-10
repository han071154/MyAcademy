import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'schedule_page.dart';
import 'student_class_space_page.dart';
import 'student_courses_page.dart';
import 'student_pay_page.dart';
import 'student_payments_page.dart';

class StudentDashboardPage extends StatefulWidget {
  final void Function(int tabIndex)? onSelectTab;
  const StudentDashboardPage({super.key, this.onSelectTab});

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  late Future<List<dynamic>> _f = _load();

  Future<List<dynamic>> _load() => Future.wait([
        Api.i.get('/my/classes'),
        Api.i.get('/classes'),
        // Các lần báo chuyển khoản (chờ xác nhận / bị từ chối...); lỗi (vd chưa chạy payment_requests.sql) thì coi như không có.
        Api.i.paymentRequests().catchError((_) => []),
      ]);

  void _reload() => setState(() {
        _f = _load();
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

  Widget _greeting(BuildContext context) {
    final u = Api.i.user ?? {};
    final h = DateTime.now().hour;
    final text = h < 12 ? 'Chào buổi sáng' : (h < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
    return Row(children: [
      InitialAvatar(u['full_name'], radius: 26),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFCCFBF1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Học viên',
                  style: TextStyle(color: Color(0xFF0F766E), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 2),
          Text('${u['full_name'] ?? 'Học viên'}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  void _openPayments(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentPaymentsPage()));

  void _openCourses(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(appBar: AppBar(title: const Text('Đăng ký khóa học')), body: const StudentCoursesPage()),
        ),
      );

  /// Lớp đang học thật sự: đã khai giảng, chưa kết thúc và đã được vào lớp (đã đóng ít nhất 1 đợt).
  /// Không tính lớp chưa khai giảng hay lớp còn khóa vì chưa đóng tiền.
  static int _activeCount(List classes) =>
      classes.where((c) => c['status'] == 'ONGOING' && canEnterClass(c as Map)).length;

  /// Số khóa học đang tuyển sinh: có ít nhất 1 lớp còn nhận đăng ký (đang mở, chưa khai giảng).
  static int _openCourseCount(List allClasses) {
    final today = DateUtils.dateOnly(DateTime.now());
    return allClasses
        .where((c) {
          final start = DateTime.tryParse('${c['start_date'] ?? ''}');
          return c['status'] == 'OPEN' && (start == null || start.isAfter(today));
        })
        .map((c) => c['course_id'])
        .toSet()
        .length;
  }

  // Màu vàng hổ phách cho trạng thái "Chờ xác nhận" trên thẻ học viên.
  static const _waitBg = Color(0xFFFFD58A);
  static const _waitText = Color(0xFF7C4A03);

  /// Khối nổi bật khi toàn bộ học phí còn lại đã báo chuyển khoản, đang chờ trung tâm xác nhận.
  Widget _waitingBox(BuildContext context, num totalPending) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x26FFD58A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _waitBg, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: _waitBg, shape: BoxShape.circle),
              child: const Icon(Icons.hourglass_top_rounded, color: _waitText, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Học phí đang chờ xác nhận',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(vnd(totalPending),
                      style: const TextStyle(color: _waitBg, fontWeight: FontWeight.w800, fontSize: 26)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Bạn đã báo chuyển khoản. Học phí được tính và lớp được mở ngay khi trung tâm xác nhận đã nhận tiền.',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openPayments(context),
              style: FilledButton.styleFrom(backgroundColor: _waitBg, foregroundColor: _waitText),
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: const Text('Xem trạng thái học phí', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );

  Widget _heroCard(BuildContext context, List classes, num totalPaid, num totalDebt, num totalPending) {
    final noClass = classes.isEmpty;
    // Toàn bộ số nợ đã báo chuyển khoản, chỉ còn chờ trung tâm xác nhận.
    final waiting = totalDebt > 0 && totalPending >= totalDebt;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x330D9488), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Expanded(
            child: Row(children: [
              Icon(Icons.badge_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Flexible(
                child: Text('THẺ HỌC VIÊN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              // Đang chờ xác nhận: nhãn màu vàng cho nổi bật trên nền xanh.
              color: waiting ? _waitBg : const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (waiting) ...[
                const Icon(Icons.hourglass_top_rounded, size: 14, color: _waitText),
                const SizedBox(width: 4),
              ],
              Text(noClass ? 'Chưa có lớp' : (waiting ? 'Chờ xác nhận' : (totalDebt > 0 ? 'Còn nợ' : 'Đã nộp đủ')),
                  style: TextStyle(
                      color: waiting ? _waitText : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (noClass) ...[
          const Text('Tình trạng học phí', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('Bạn chưa đăng ký lớp nào',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
        ] else if (waiting) ...[
          _waitingBox(context, totalPending),
        ] else if (totalDebt > 0) ...[
          const Text('Học phí còn nợ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(vnd(totalDebt),
              style: const TextStyle(color: Color(0xFFFFD58A), fontWeight: FontWeight.w700, fontSize: 24)),
          if (totalPending > 0) ...[
            const SizedBox(height: 2),
            Text('Trong đó ${vnd(totalPending)} đang chờ xác nhận',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _openPayments(context),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0F766E)),
            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
            label: const Text('Đóng học phí ngay'),
          ),
        ] else ...[
          const Text('Tình trạng học phí', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text('Đã hoàn thành 100%',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
          ]),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lớp đang học', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 2),
              Text('${_activeCount(classes)} lớp',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
          ),
          Container(width: 1, height: 36, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Đã thanh toán', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 2),
              Text(vnd(totalPaid),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _quickLinks(BuildContext context, List classes) {
    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: SoftCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: onTap,
            child: Column(children: [
              IconBox(icon, color),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        );

    return Row(children: [
      tile(Icons.add_shopping_cart_outlined, 'Đăng ký lớp', AppColors.primary, () => _openCourses(context)),
      const SizedBox(width: 10),
      tile(Icons.payments_outlined, 'Học phí', AppColors.ok,
          () => _openPayments(context)),
      const SizedBox(width: 10),
      tile(Icons.calendar_month_outlined, 'Lịch học', const Color(0xFF0F766E), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulePage()))),
      const SizedBox(width: 10),
      tile(Icons.person_outline, 'Hồ sơ', AppColors.amber, () => widget.onSelectTab?.call(2)),
    ]);
  }

  Widget _stat(IconData icon, String label, dynamic value, Color color) => Expanded(
        child: SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconBox(icon, color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Số tiền dài (vd 2.000.000 đ) thì thu nhỏ chữ cho vừa, không bị cắt "2.000...."
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('$value', maxLines: 1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Text(label, maxLines: 2, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      );

  Widget _classCard(BuildContext context, Map c) {
    final fee = num.tryParse('${c['fee']}') ?? 0;
    final paid = num.tryParse('${c['paid']}') ?? 0;
    final debt = fee - paid;
    final dates = c['start_date'] == null ? null : '${fmtDate(c['start_date'])} → ${fmtDate(c['end_date'])}';

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (c['course_name'] != null)
                Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Pill(classStatusLabel(c['status'], role: 'STUDENT'), statusColor(c['status'])),
        ]),
        const SizedBox(height: 10),
        MetaRow(Icons.person_outline, 'Giảng viên: ${c['teacher_name'] ?? 'Chưa phân công'}'),
        MetaRow(Icons.schedule, '${c['schedule'] ?? 'Chưa có lịch'}'),
        if (c['room'] != null) MetaRow(Icons.meeting_room_outlined, 'Phòng học: ${c['room']}'),
        if (dates != null) MetaRow(Icons.event_outlined, dates),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: debt > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: debt > 0 ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
          ),
          child: Row(children: [
            Icon(debt > 0 ? Icons.error_outline : Icons.check_circle_outline,
                size: 16, color: debt > 0 ? AppColors.danger : AppColors.ok),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                debt > 0 ? 'Học phí còn nợ: ${vnd(debt)}' : 'Đã thanh toán đủ học phí',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: debt > 0 ? AppColors.danger : AppColors.ok),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => openStudentClass(context, c),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('Xem chi tiết lớp học'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                  const SizedBox(height: 12),
                  Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Thử lại')),
                ]),
              ),
            );
          }

          final results = snap.data as List<dynamic>;
          final classes = (results[0] as List?) ?? [];
          final allClasses = (results[1] as List?) ?? [];
          final reqs = (results[2] as List?) ?? [];

          final totalFee = classes.fold<num>(0, (sum, c) => sum + (num.tryParse('${c['fee']}') ?? 0));
          final totalPaid = classes.fold<num>(0, (sum, c) => sum + (num.tryParse('${c['paid']}') ?? 0));
          final totalDebt = totalFee - totalPaid;
          final totalPending = reqs
              .where((r) => r['status'] == 'PENDING')
              .fold<num>(0, (sum, r) => sum + (num.tryParse('${r['amount']}') ?? 0));
          // Lớp còn nợ mà lần báo chuyển khoản gần nhất bị trung tâm từ chối → báo cho học viên.
          final rejected = [
            for (final c in classes)
              if ((num.tryParse('${c['fee']}') ?? 0) - (num.tryParse('${c['paid']}') ?? 0) > 0)
                if (latestRejectedRequest(reqs, c['id']) case final r?) (c as Map, r),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _greeting(context),
              const SizedBox(height: 16),
              _heroCard(context, classes, totalPaid, totalDebt, totalPending),
              const SizedBox(height: 16),
              for (final (c, r) in rejected)
                RejectedNotice(r, onPay: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPayPage(classData: c)));
                  _reload();
                }),
              _quickLinks(context, classes),
              const SizedBox(height: 16),
              // Số tiền đã có ở thẻ học viên phía trên nên ở đây chỉ hiện số lớp / số khóa.
              Row(children: [
                _stat(Icons.school_outlined, 'Lớp đã đăng ký', classes.length, AppColors.primary),
                const SizedBox(width: 12),
                _stat(Icons.menu_book_outlined, 'Khóa đang tuyển sinh', _openCourseCount(allClasses), AppColors.amber),
              ]),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Lớp học của tôi',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${classes.length} lớp', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              if (classes.isEmpty)
                SoftCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    const IconBox(Icons.menu_book_rounded, AppColors.primary, size: 56),
                    const SizedBox(height: 16),
                    const Text('Bạn chưa tham gia lớp nào',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text(
                      'Khám phá danh sách các khóa học chất lượng cao tại trung tâm và đăng ký lớp học ngay hôm nay!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => _openCourses(context),
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Khám phá khóa học ngay'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ]),
                )
              else
                for (final c in classes) _classCard(context, c as Map),
            ],
          );
        },
      ),
    );
  }
}
