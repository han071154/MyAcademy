import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'student_pay_page.dart';

/// Học viên: học phí từng lớp, nút đóng tiền bằng chuyển khoản (QR),
/// các lần chuyển khoản đang chờ xác nhận và lịch sử đã đóng.
class StudentPaymentsPage extends StatefulWidget {
  const StudentPaymentsPage({super.key});
  @override
  State<StudentPaymentsPage> createState() => _StudentPaymentsPageState();
}

class _StudentPaymentsPageState extends State<StudentPaymentsPage> {
  late Future<List<dynamic>> _f = _load();

  // RLS chỉ trả về lớp và phiếu thu của chính học viên đang đăng nhập.
  Future<List<dynamic>> _load() =>
      Future.wait([Api.i.get('/my/classes'), Api.i.get('/payments'), Api.i.paymentRequests()]);

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

  Future<void> _pay(Map c) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPayPage(classData: c)));

  Future<void> _cancelRequest(Map r) async {
    if (!await confirm(context, 'Hủy báo chuyển khoản ${vnd(r['amount'])}?')) return;
    if (!mounted) return;
    await guard(context, () => Api.i.cancelPaymentRequest(int.parse('${r['id']}')));
  }

  static const _reqStatus = {
    'PENDING': ('Chờ xác nhận', AppColors.amber),
    'CONFIRMED': ('Đã xác nhận', AppColors.ok),
    'REJECTED': ('Bị từ chối', AppColors.danger),
  };

  Widget _request(Map r) {
    final st = _reqStatus[r['status']] ?? ('${r['status']}', AppColors.muted);
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(children: [
        const IconBox(Icons.qr_code_2_rounded, AppColors.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(vnd(r['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Pill(st.$1, st.$2),
            ]),
            const SizedBox(height: 2),
            Text('${r['class_name'] ?? ''} • ${fmtDateTime(r['created_at'])}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            if (r['status'] == 'REJECTED' && r['reject_reason'] != null)
              Text('Lý do: ${r['reject_reason']}', style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ]),
        ),
        if (r['status'] == 'PENDING')
          IconButton(
            tooltip: 'Hủy',
            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            onPressed: () => _cancelRequest(r),
          ),
      ]),
    );
  }

  void _reload() => setState(() {
        _f = _load();
      });

  num _n(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;

  Widget _howToPay() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tint(AppColors.primary), borderRadius: BorderRadius.circular(14)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bấm "Đóng học phí" ở lớp cần đóng rồi chuyển khoản theo mã QR, hoặc đóng tiền mặt tại quầy '
              'trung tâm. Khoản chuyển khoản được tính sau khi trung tâm xác nhận.',
              style: TextStyle(height: 1.4),
            ),
          ),
        ]),
      );

  Widget _classFee(Map c, List reqs) {
    final fee = _n(c['fee']);
    final paid = _n(c['paid']);
    final debt = fee - paid;
    final pending = reqs
        .where((r) => r['class_id'] == c['id'] && r['status'] == 'PENDING')
        .fold<num>(0, (s, r) => s + _n(r['amount']));
    final progress = fee > 0 ? (paid / fee).clamp(0, 1).toDouble() : 1.0;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Pill(debt <= 0 ? 'Đã đóng đủ' : (pending >= debt ? 'Chờ xác nhận' : 'Còn nợ'),
              debt <= 0 ? AppColors.ok : (pending >= debt ? AppColors.amber : AppColors.danger)),
        ]),
        if (c['course_name'] != null)
          Text('${c['course_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: tint(AppColors.danger),
            color: AppColors.ok,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Đã đóng ${vnd(paid)} / ${vnd(fee)}', style: const TextStyle(fontSize: 13))),
          if (debt > 0)
            Text('Nợ ${vnd(debt)}',
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        if (pending > 0)
          Text('Đang chờ xác nhận ${vnd(pending)}',
              style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600, fontSize: 13)),
        if (debt - pending > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _pay(c),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text('Đóng học phí (${vnd(debt - pending)})'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _payment(Map p) => SoftCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const IconBox(Icons.receipt_long_outlined, AppColors.ok),
          title: Text(vnd(p['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${p['class_name'] ?? ''}\n'
            '${fmtDateTime(p['paid_at'])} • ${payMethods[p['method']] ?? p['method'] ?? ''}'
            '${(p['note'] ?? '').toString().trim().isNotEmpty ? '\n${p['note']}' : ''}',
          ),
          isThreeLine: true,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Học phí của tôi')),
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final r = data as List;
            final classes = (r[0] as List?) ?? [];
            final payments = (r[1] as List?) ?? [];
            final reqs = (r[2] as List?) ?? [];
            final openReqs = reqs.where((x) => x['status'] != 'CONFIRMED').toList();
            final totalFee = classes.fold<num>(0, (s, c) => s + _n(c['fee']));
            final totalPaid = classes.fold<num>(0, (s, c) => s + _n(c['paid']));
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _f;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _howToPay(),
                  const SizedBox(height: 16),
                  if (classes.isNotEmpty)
                    Row(children: [
                      Expanded(child: _total('Tổng học phí', vnd(totalFee), AppColors.primary)),
                      const SizedBox(width: 10),
                      Expanded(child: _total('Đã đóng', vnd(totalPaid), AppColors.ok)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _total('Còn nợ', vnd(totalFee - totalPaid),
                            totalFee - totalPaid > 0 ? AppColors.danger : AppColors.ok),
                      ),
                    ]),
                  const SizedBox(height: 20),
                  const Text('Học phí theo lớp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (classes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Bạn chưa đăng ký lớp nào nên chưa có học phí.',
                          style: TextStyle(color: AppColors.muted)),
                    )
                  else
                    for (final c in classes) _classFee(c as Map, reqs),
                  if (openReqs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Chuyển khoản đã báo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 10),
                    for (final x in openReqs) _request(x as Map),
                  ],
                  const SizedBox(height: 16),
                  const Text('Lịch sử đóng tiền', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Chưa có lần đóng tiền nào.', style: TextStyle(color: AppColors.muted)),
                    )
                  else
                    for (final p in payments) _payment(p as Map),
                ],
              ),
            );
          },
        ),
      );

  Widget _total(String label, String value, Color color) => SoftCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ]),
      );
}
