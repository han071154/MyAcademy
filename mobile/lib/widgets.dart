import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'theme.dart';

// ---------- Định dạng ----------
String vnd(dynamic n) =>
    '${NumberFormat.decimalPattern('vi').format(n is num ? n : (num.tryParse('$n') ?? 0))} đ';

String fmtDate(dynamic s) {
  final d = DateTime.tryParse('${s ?? ''}');
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d.toLocal());
}

String fmtDateTime(dynamic s) {
  final d = DateTime.tryParse('${s ?? ''}');
  return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
}

String initial(dynamic name) {
  final s = '${name ?? ''}'.trim();
  return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
}

const classStatus = {'OPEN': 'Đang tuyển sinh', 'ONGOING': 'Đang diễn ra', 'CLOSED': 'Đã kết thúc'};

String classStatusLabel(String? status, {String? role}) {
  final r = role?.toUpperCase();
  if (status == 'ONGOING') {
    if (r == 'TEACHER') return 'Đang dạy';
    if (r == 'STUDENT') return 'Đang học';
    return 'Đang diễn ra';
  }
  return classStatus[status] ?? (status ?? '');
}
const payMethods = {'CASH': 'Tiền mặt', 'TRANSFER': 'Chuyển khoản', 'CARD': 'Thẻ'};

List<(Object, String)> opts(Map<String, String> m) => [for (final e in m.entries) (e.key, e.value)];

// ---------- Thông báo / xác nhận ----------
void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Chạy thao tác API; lỗi thì hiện thông báo. Trả về true nếu thành công.
Future<bool> guard(BuildContext c, Future<void> Function() f) async {
  try {
    await f();
    return true;
  } catch (e) {
    // Dùng hộp thoại thay vì SnackBar: SnackBar bị bảng chọn (bottom sheet) / hộp thoại che mất
    if (c.mounted) {
      await showDialog<void>(
        context: c,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Không thực hiện được'),
          content: Text('$e'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        ),
      );
    }
    return false;
  }
}

Future<bool> confirm(BuildContext c, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đồng ý')),
        ],
      ),
    ) ??
    false;

// ---------- Hiển thị dữ liệu bất đồng bộ ----------
class Loader extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(dynamic data) builder;
  final VoidCallback onRetry;
  const Loader({super.key, required this.future, required this.builder, required this.onRetry});

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const IconBox(Icons.cloud_off_outlined, AppColors.danger, size: 56),
                  const SizedBox(height: 16),
                  Text('${s.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: onRetry, child: const Text('Thử lại')),
                ]),
              ),
            );
          }
          return builder(s.data);
        },
      );
}

// ---------- Form động dùng chung ----------
enum FieldType { text, number, date, password, dropdown, check }

class Field {
  final String key, label;
  final FieldType type;
  final List<(Object, String)> options;
  final bool required;
  const Field(this.key, this.label,
      {this.type = FieldType.text, this.options = const [], this.required = false});
}

/// Hiện form thêm/sửa. Trả về Map giá trị (trường bỏ trống = null) hoặc null nếu hủy.
Future<Map<String, dynamic>?> showForm(BuildContext context, String title, List<Field> fields,
        {Map<String, dynamic>? initial}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormDialog(title: title, fields: fields, initial: initial ?? {}),
    );

class _FormDialog extends StatefulWidget {
  final String title;
  final List<Field> fields;
  final Map<String, dynamic> initial;
  const _FormDialog({required this.title, required this.fields, required this.initial});
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _key = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, Object?> _val = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial[f.key];
      switch (f.type) {
        case FieldType.dropdown:
          _val[f.key] = f.options.any((o) => o.$1 == v) ? v : null;
        case FieldType.check:
          _val[f.key] = v ?? true;
        case FieldType.password:
          _ctl[f.key] = TextEditingController();
        case FieldType.number:
          _ctl[f.key] = TextEditingController(
              text: v == null ? '' : (v is num && v == v.roundToDouble() ? '${v.toInt()}' : '$v'));
        default:
          _ctl[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.type == FieldType.dropdown || f.type == FieldType.check) {
        out[f.key] = _val[f.key];
        continue;
      }
      final t = _ctl[f.key]!.text.trim();
      out[f.key] = t.isEmpty ? null : (f.type == FieldType.number ? num.tryParse(t) : t);
    }
    Navigator.pop(context, out);
  }

  Widget _input(Field f) {
    String? Function(String?)? required =
        f.required ? (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null : null;
    switch (f.type) {
      case FieldType.dropdown:
        return DropdownButtonFormField<Object>(
          value: _val[f.key],
          isExpanded: true,
          decoration: deco(labelText: f.label + (f.required ? ' *' : '')),
          items: [for (final o in f.options) DropdownMenuItem<Object>(value: o.$1, child: Text(o.$2))],
          validator: (v) => f.required && v == null ? 'Bắt buộc' : null,
          onChanged: (v) => _val[f.key] = v,
        );
      case FieldType.check:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _val[f.key] == true,
          onChanged: (v) => setState(() => _val[f.key] = v ?? false),
        );
      case FieldType.date:
        final c = _ctl[f.key]!;
        return TextFormField(
          controller: c,
          readOnly: true,
          decoration: deco(
            labelText: f.label + (f.required ? ' *' : ''),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          validator: required,
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
              firstDate: DateTime(1950),
              lastDate: DateTime(2100),
            );
            if (d != null) c.text = DateFormat('yyyy-MM-dd').format(d);
          },
        );
      case FieldType.number:
        return TextFormField(
          controller: _ctl[f.key],
          keyboardType: TextInputType.number,
          decoration: deco(labelText: f.label + (f.required ? ' *' : '')),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return f.required ? 'Bắt buộc' : null;
            return num.tryParse(v.trim()) == null ? 'Phải là số' : null;
          },
        );
      case FieldType.password:
        return TextFormField(
          controller: _ctl[f.key],
          obscureText: true,
          decoration: deco(labelText: f.label + (f.required ? ' *' : '')),
          validator: required,
        );
      case FieldType.text:
        return TextFormField(
          controller: _ctl[f.key],
          decoration: deco(labelText: f.label + (f.required ? ' *' : '')),
          validator: required,
        );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _key,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final f in widget.fields)
                  Padding(padding: const EdgeInsets.only(top: 8), child: _input(f)),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: _submit, child: const Text('Lưu')),
        ],
      );
}


// ---------- Thành phần giao diện dùng chung ----------
InputDecoration deco({String? labelText, String? hintText, Widget? prefixIcon, Widget? suffixIcon}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: b(AppColors.line),
    enabledBorder: b(AppColors.line),
    focusedBorder: b(AppColors.primary, 1.6),
    errorBorder: b(AppColors.danger),
    focusedErrorBorder: b(AppColors.danger, 1.6),
    labelStyle: const TextStyle(color: AppColors.muted),
    hintStyle: const TextStyle(color: AppColors.muted),
  );
}

/// Thẻ trắng bo góc, viền mảnh (thay cho Card mặc định).
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  const SoftCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 6, 16, 6),
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.line),
          ),
          child: InkWell(onTap: onTap, child: Padding(padding: padding ?? EdgeInsets.zero, child: child)),
        ),
      );
}

/// Ô vuông bo tròn chứa icon, nền nhạt theo màu.
class IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBox(this.icon, this.color, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tint(color), borderRadius: BorderRadius.circular(size / 3)),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Avatar chữ cái đầu của tên.
class InitialAvatar extends StatelessWidget {
  final dynamic name;
  final double radius;
  const InitialAvatar(this.name, {super.key, this.radius = 22});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: tint(AppColors.primary),
        child: Text(initial(name),
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
      );
}

/// Nhãn nhỏ (trạng thái).
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tint(color), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

Color statusColor(dynamic status) {
  switch (status) {
    case 'ONGOING':
      return AppColors.primary;
    case 'OPEN':
      return AppColors.amber;
    default:
      return AppColors.muted;
  }
}

/// Một dòng thông tin: icon nhỏ + chữ.
class MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const MetaRow(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted, height: 1.3))),
        ]),
      );
}

/// Trạng thái rỗng.
class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const IconBox(Icons.inbox_outlined, AppColors.muted, size: 56),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: AppColors.muted)),
        ]),
      );
}

TabBar styledTabs(List<String> labels) => TabBar(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      tabs: [for (final l in labels) Tab(text: l)],
    );
