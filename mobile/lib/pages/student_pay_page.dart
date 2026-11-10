import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../payment_config.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_page.dart';

/// Lần báo chuyển khoản MỚI NHẤT của lớp [classId] nếu đã bị trung tâm từ chối, ngược lại null.
/// Học viên báo chuyển khoản lại (yêu cầu mới) thì lần bị từ chối cũ không còn là mới nhất → hết cảnh báo.
/// [reqs] là danh sách từ Api.paymentRequests(), đã sắp xếp mới nhất trước.
Map? latestRejectedRequest(List reqs, dynamic classId) {
  for (final r in reqs) {
    if ('${r['class_id']}' != '$classId') continue;
    return r['status'] == 'REJECTED' ? r as Map : null;
  }
  return null;
}

/// Câu báo cho học viên biết khoản chuyển khoản bị từ chối và lý do.
String rejectedMessage(Map r) {
  final reason = (r['reject_reason'] ?? '').toString().trim();
  return 'Trung tâm đã từ chối khoản chuyển ${vnd(r['amount'])} bạn báo lúc ${fmtDateTime(r['created_at'])}'
      '${r['class_name'] != null ? ' cho lớp "${r['class_name']}"' : ''}. '
      '${reason.isEmpty ? 'Trung tâm chưa nhận được khoản tiền này.' : 'Lý do: $reason.'} '
      'Vui lòng kiểm tra lại giao dịch và đóng lại học phí.';
}

/// Hộp cảnh báo màu đỏ: lần chuyển khoản gần nhất bị từ chối.
class RejectedNotice extends StatelessWidget {
  final Map request;
  final VoidCallback? onPay;
  const RejectedNotice(this.request, {super.key, this.onPay});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint(AppColors.danger),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.cancel_rounded, color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text('Chuyển khoản bị từ chối',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(rejectedMessage(request), style: const TextStyle(height: 1.4)),
          if (onPay != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPay,
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Đóng lại học phí'),
              ),
            ),
          ],
        ]),
      );
}

/// Học viên đóng học phí 1 lớp bằng chuyển khoản: quét QR → chuyển đúng số tiền + nội dung
/// → bấm "Tôi đã chuyển khoản" → chờ trung tâm xác nhận.
class StudentPayPage extends StatefulWidget {
  /// Lớp cần đóng (cần có id, name, fee; có thể có paid, course_name).
  final Map classData;

  /// true khi mở ngay sau lúc đăng ký lớp: xong thì chuyển sang tab "Lớp học của tôi".
  final bool afterRegister;
  const StudentPayPage({super.key, required this.classData, this.afterRegister = false});

  @override
  State<StudentPayPage> createState() => _StudentPayPageState();
}

class _StudentPayPageState extends State<StudentPayPage> {
  late Future<Map<String, dynamic>> _f = _load();
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sending = false;

  int get _classId => int.parse('${widget.classData['id']}');

  num _n(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;

  /// Lấy lại học phí đã đóng + yêu cầu đang chờ (số liệu mới nhất từ server).
  Future<Map<String, dynamic>> _load() async {
    final mine = await Api.i.get('/my/classes') as List;
    final cls = mine.cast<Map>().firstWhere((c) => '${c['id']}' == '$_classId', orElse: () => widget.classData);
    final reqs = (await Api.i.paymentRequests()).cast<Map>().where((r) => '${r['class_id']}' == '$_classId').toList();
    final fee = _n(cls['fee']);
    final paid = _n(cls['paid']);
    final pending = reqs.where((r) => r['status'] == 'PENDING').fold<num>(0, (s, r) => s + _n(r['amount']));
    final due = fee - paid - pending;
    if (_amount.text.isEmpty && due > 0) _amount.text = due.toStringAsFixed(0);
    // Lần báo gần nhất bị từ chối và vẫn còn phải đóng → hiện lý do để học viên biết vì sao chưa được tính tiền.
    final rejected = due > 0 ? latestRejectedRequest(reqs, _classId) : null;
    return {'cls': cls, 'fee': fee, 'paid': paid, 'pending': pending, 'due': due, 'reqs': reqs, 'rejected': rejected};
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _done() {
    if (widget.afterRegister) {
      HomePage.goToTab(context, 1); // về "Lớp học của tôi"
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) toast(context, 'Đã sao chép $what');
  }

  Future<void> _submit(num due) async {
    if (!_form.currentState!.validate()) return;
    final amount = num.parse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (!await confirm(context, 'Xác nhận bạn đã chuyển khoản ${vnd(amount)} cho lớp "${widget.classData['name']}"?')) {
      return;
    }
    setState(() => _sending = true);
    try {
      await Api.i.createPaymentRequest(_classId, amount);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          icon: const Icon(Icons.hourglass_top_rounded, color: AppColors.amber, size: 40),
          title: const Text('Đã gửi xác nhận'),
          content: const Text(
            'Trung tâm sẽ kiểm tra tài khoản và xác nhận khoản chuyển của bạn (thường trong giờ làm việc). '
            'Bạn theo dõi trạng thái ở mục Học phí trên trang chủ.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
        ),
      );
      if (mounted) _done();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _sending = false);
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Text(value, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ]),
      );

  Widget _copyField(String label, String value, String what) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
          ),
          IconButton(
            tooltip: 'Sao chép',
            icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
            onPressed: () => _copy(value, what),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Đóng học phí')),
        body: Loader(
          future: _f,
          onRetry: () => setState(() => _f = _load()),
          builder: (data) {
            final d = data as Map;
            final due = d['due'] as num;
            final pending = d['pending'] as num;
            final paid = d['paid'] as num;
            final code = PaymentConfig.transferCode(Api.i.userId, _classId);
            // Hạn giữ chỗ: chưa đóng đồng nào và chưa báo chuyển khoản thì quá hạn sẽ tự hủy đăng ký.
            final holdUntil = (d['cls'] as Map)['hold_until'];
            final showHold = holdUntil != null && paid <= 0 && pending <= 0;
            return Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                if (widget.afterRegister)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: tint(AppColors.ok), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: AppColors.ok),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Đăng ký lớp "${widget.classData['name']}" thành công! Hãy đóng học phí để giữ chỗ.',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                if (d['rejected'] != null) RejectedNotice(d['rejected'] as Map),
                if (showHold)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: tint(AppColors.amber), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.timer_outlined, color: AppColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chỗ của bạn được giữ đến ${fmtDateTime(holdUntil)}. '
                          'Quá hạn mà chưa đóng hoặc chưa báo chuyển khoản thì đăng ký sẽ tự hủy.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                SoftCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${widget.classData['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    _row('Học phí', vnd(d['fee'])),
                    _row('Đã đóng', vnd(d['paid']), color: AppColors.ok),
                    if (pending > 0) _row('Đang chờ xác nhận', vnd(pending), color: AppColors.amber),
                    const Divider(),
                    _row('Còn phải đóng', vnd(due > 0 ? due : 0),
                        color: due > 0 ? AppColors.danger : AppColors.ok, bold: true),
                  ]),
                ),
                const SizedBox(height: 16),
                if (due <= 0) ...[
                  EmptyState(pending > 0
                      ? 'Khoản chuyển của bạn đang chờ trung tâm xác nhận.'
                      : 'Bạn đã đóng đủ học phí lớp này. Cảm ơn bạn!'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _done,
                    child: Text(widget.afterRegister ? 'Vào Lớp học của tôi' : 'Quay lại'),
                  ),
                ] else ...[
                  const Text('Bước 1: Quét mã QR bằng app ngân hàng',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(PaymentConfig.qrAsset, width: 260, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('Chủ tài khoản: ${PaymentConfig.accountName}',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 18),
                  const Text('Bước 2: Nhập đúng số tiền và nội dung chuyển khoản',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) {
                      final n = num.tryParse((v ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
                      if (n == null || n <= 0) return 'Vui lòng nhập số tiền';
                      if (n > due) return 'Tối đa ${vnd(due)}';
                      return null;
                    },
                    decoration: deco(labelText: 'Số tiền chuyển (VNĐ)', prefixIcon: const Icon(Icons.payments_outlined))
                        .copyWith(
                      helperText: 'Có thể đóng một phần, mặc định là toàn bộ số còn lại',
                      suffixIcon: IconButton(
                        tooltip: 'Sao chép',
                        icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                        onPressed: () => _copy(_amount.text, 'số tiền'),
                      ),
                    ),
                  ),
                  _copyField('Nội dung chuyển khoản (bắt buộc ghi đúng)', code, 'nội dung'),
                  const SizedBox(height: 18),
                  const Text('Bước 3: Chuyển xong, bấm nút bên dưới',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : () => _submit(due),
                      icon: _sending
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: const Text('Tôi đã chuyển khoản'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _sending ? null : _done,
                    child: const Text('Để sau / Đóng tiền mặt tại trung tâm'),
                  ),
                ],
              ]),
            );
          },
        ),
      );
}
