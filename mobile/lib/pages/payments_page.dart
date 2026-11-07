import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Học phí: tab Chờ xác nhận (học viên báo chuyển khoản), Công nợ (thu tiền) và Lịch sử thu.
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late Future<dynamic> _debts = Api.i.get('/payments/debts');
  late Future<dynamic> _history = Api.i.get('/payments');
  late Future<dynamic> _requests = Api.i.paymentRequests(status: 'PENDING');

  void _reload() => setState(() {
        _debts = Api.i.get('/payments/debts');
        _history = Api.i.get('/payments');
        _requests = Api.i.paymentRequests(status: 'PENDING');
      });

  Future<void> _confirmRequest(Map r) async {
    if (!await confirm(context,
        'Xác nhận đã nhận ${vnd(r['amount'])} từ ${r['student_name']}?\nNội dung CK: ${r['transfer_code']}')) {
      return;
    }
    if (!mounted) return;
    if (await guard(context, () => Api.i.confirmPaymentRequest(int.parse('${r['id']}')))) {
      _reload();
      if (mounted) toast(context, 'Đã xác nhận và ghi nhận khoản thu');
    }
  }

  Future<void> _rejectRequest(Map r) async {
    final v = await showForm(context, 'Từ chối chuyển khoản', [
      const Field('reason', 'Lý do (vd: chưa nhận được tiền, sai số tiền)', required: true),
    ]);
    if (v == null || !mounted) return;
    if (await guard(context, () => Api.i.rejectPaymentRequest(int.parse('${r['id']}'), v['reason']?.toString()))) {
      _reload();
    }
  }

  Widget _requestList() => Loader(
        future: _requests,
        onRetry: _reload,
        builder: (data) {
          final list = data as List;
          if (list.isEmpty) return const EmptyState('Không có chuyển khoản nào chờ xác nhận');
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i] as Map;
              return SoftCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    InitialAvatar(r['student_name']),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['student_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${r['class_name']}', style: const TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                    Text(vnd(r['amount']),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ]),
                  const SizedBox(height: 8),
                  Text('Nội dung CK: ${r['transfer_code']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Báo lúc ${fmtDateTime(r['created_at'])}${r['student_phone'] == null ? '' : ' • SĐT ${r['student_phone']}'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  const Text('Kiểm tra tài khoản ngân hàng đã nhận đúng số tiền và nội dung rồi mới xác nhận.',
                      style: TextStyle(color: AppColors.amber, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _rejectRequest(r),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Từ chối'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(onPressed: () => _confirmRequest(r), child: const Text('Đã nhận tiền')),
                    ),
                  ]),
                ]),
              );
            },
          );
        },
      );

  Future<void> _pay(Map d) async {
    final v = await showForm(
      context,
      'Thu học phí - ${d['student_name']}',
      [
        const Field('amount', 'Số tiền (VNĐ)', type: FieldType.number, required: true),
        Field('method', 'Hình thức', type: FieldType.dropdown, required: true, options: opts(payMethods)),
        const Field('note', 'Ghi chú'),
      ],
      initial: {'amount': d['debt'], 'method': 'CASH'},
    );
    if (v == null || !mounted) return;
    final ok = await guard(context, () => Api.i.post('/payments', {...v, 'enrollment_id': d['enrollment_id']}));
    if (ok) {
      _reload();
      if (mounted) toast(context, 'Đã ghi nhận thanh toán');
    }
  }

  Future<void> _delete(Map p) async {
    if (!await confirm(context, 'Xóa khoản thu ${vnd(p['amount'])} của ${p['student_name']}?')) return;
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/payments/${p['id']}'))) _reload();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          styledTabs(['Chờ xác nhận', 'Công nợ', 'Lịch sử thu']),
          Expanded(
            child: TabBarView(children: [
              _requestList(),
              Loader(
                future: _debts,
                onRetry: _reload,
                builder: (data) {
                  final list = data as List;
                  if (list.isEmpty) return const EmptyState('Chưa có học viên nào ghi danh');
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final d = list[i] as Map;
                      final debt = d['debt'] as num;
                      return SoftCard(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            InitialAvatar(d['student_name']),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${d['student_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('${d['class_name']}', style: const TextStyle(color: AppColors.muted)),
                              ]),
                            ),
                            if (debt <= 0) const Icon(Icons.check_circle, color: AppColors.ok),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(spacing: 16, runSpacing: 4, children: [
                            Text('Học phí: ${vnd(d['fee'])}', style: const TextStyle(color: AppColors.muted)),
                            Text('Đã đóng: ${vnd(d['paid'])}', style: const TextStyle(color: AppColors.muted)),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: Text(debt > 0 ? 'Còn nợ ${vnd(debt)}' : 'Đã đóng đủ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: debt > 0 ? AppColors.danger : AppColors.ok)),
                            ),
                            if (debt > 0)
                              FilledButton.tonal(onPressed: () => _pay(d), child: const Text('Thu tiền')),
                          ]),
                        ]),
                      );
                    },
                  );
                },
              ),
              Loader(
                future: _history,
                onRetry: _reload,
                builder: (data) {
                  final list = data as List;
                  if (list.isEmpty) return const EmptyState('Chưa có khoản thu nào');
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i] as Map;
                      return SoftCard(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                          leading: const IconBox(Icons.payments_outlined, AppColors.ok),
                          title: Text('${p['student_name']} • ${vnd(p['amount'])}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${p['class_name']} • ${payMethods[p['method']] ?? p['method']} • '
                              '${fmtDateTime(p['paid_at'])}${p['note'] == null ? '' : '\n${p['note']}'}',
                              style: const TextStyle(color: AppColors.muted)),
                          isThreeLine: p['note'] != null,
                          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
                        ),
                      );
                    },
                  );
                },
              ),
            ]),
          ),
        ]),
      );
}
