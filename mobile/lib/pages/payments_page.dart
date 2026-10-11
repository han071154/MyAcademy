import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Học phí: tab Công nợ (thu tiền) và tab Lịch sử thu.
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late Future<dynamic> _debts = Api.i.get('/payments/debts');
  late Future<dynamic> _history = Api.i.get('/payments');

  void _reload() => setState(() {
        _debts = Api.i.get('/payments/debts');
        _history = Api.i.get('/payments');
      });

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
        length: 2,
        child: Column(children: [
          styledTabs(['Công nợ', 'Lịch sử thu']),
          Expanded(
            child: TabBarView(children: [
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
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
                          leading: InitialAvatar(d['student_name']),
                          title: Text('${d['student_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${d['class_name']}\n'
                              'Học phí ${vnd(d['fee'])} • Đã đóng ${vnd(d['paid'])}\n'
                              '${debt > 0 ? 'Còn nợ ${vnd(debt)}' : 'Đã đóng đủ'}',
                              style: TextStyle(color: debt > 0 ? AppColors.danger : AppColors.muted)),
                          isThreeLine: true,
                          trailing: debt > 0
                              ? FilledButton.tonal(onPressed: () => _pay(d), child: const Text('Thu tiền'))
                              : const Icon(Icons.check_circle, color: AppColors.ok),
                        ),
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
