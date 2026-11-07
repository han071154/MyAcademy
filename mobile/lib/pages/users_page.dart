import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../validators.dart';
import '../widgets.dart';

/// Danh sách + thêm/sửa/xóa học viên (role = STUDENT) hoặc giáo viên (role = TEACHER).
class UsersPage extends StatefulWidget {
  final String role;
  const UsersPage({super.key, required this.role});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  late Future<dynamic> _f = _load();

  String get _label => widget.role == 'TEACHER' ? 'giảng viên' : 'học viên';

  Future<dynamic> _load() => Api.i.get('/users', query: {
        'role': widget.role,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });

  void _reload() => setState(() { _f = _load(); });

  Future<void> _edit([Map? u]) async {
    final v = await showForm(
      context,
      u == null ? 'Thêm $_label' : 'Sửa $_label',
      [
        const Field('full_name', 'Họ tên', required: true, validator: V.name),
        const Field('email', 'Email', required: true, validator: V.email, keyboard: TextInputType.emailAddress),
        const Field('phone', 'Số điện thoại', required: true, validator: V.phone, keyboard: TextInputType.phone),
        Field('dob', 'Ngày sinh', type: FieldType.date, required: true, firstDate: DateTime(1900), lastDate: V.latestDob),
        const Field('address', 'Địa chỉ', required: true, validator: V.address),
        Field(
            'password',
            u == null
                ? 'Mật khẩu khởi tạo (≥ ${Api.minPasswordLength} ký tự)'
                : 'Đặt lại mật khẩu (bỏ trống nếu không đổi)',
            type: FieldType.password,
            required: u == null),
        if (u != null) const Field('active', 'Đang hoạt động', type: FieldType.check),
      ],
      initial: u == null ? null : Map<String, dynamic>.from(u),
    );
    if (v == null || !mounted) return;
    if (v['phone'] != null) v['phone'] = V.cleanPhone('${v['phone']}');
    final pw = v['password']?.toString() ?? '';
    if ((u == null || pw.isNotEmpty) && pw.length < Api.minPasswordLength) {
      toast(context, 'Mật khẩu tối thiểu ${Api.minPasswordLength} ký tự');
      return;
    }
    final ok = await guard(
      context,
      () => u == null
          ? Api.i.post('/users', {...v, 'role': widget.role})
          : Api.i.put('/users/${u['id']}', v),
    );
    if (ok) {
      if (pw.isNotEmpty && mounted) toast(context, 'Người dùng sẽ phải đổi mật khẩu ở lần đăng nhập tới');
      _reload();
    }
  }

  Future<void> _delete(Map u) async {
    if (!await confirm(context, 'Xóa ${u['full_name']}?')) return;
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/users/${u['id']}'))) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _reload(),
              decoration: deco(
                hintText: 'Tìm theo tên, email, SĐT',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _reload),
              ),
            ),
          ),
          Expanded(
            child: Loader(
              future: _f,
              onRetry: _reload,
              builder: (data) {
                final list = data as List;
                if (list.isEmpty) return const EmptyState('Chưa có dữ liệu');
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _f;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 2, bottom: 88),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final u = list[i] as Map;
                      final active = u['active'] == true;
                      return SoftCard(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                          leading: InitialAvatar(u['full_name']),
                          title: Row(children: [
                            Flexible(
                              child: Text('${u['full_name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            if (!active) ...[const SizedBox(width: 8), const Pill('Đã khóa', AppColors.danger)],
                          ]),
                          subtitle: Text('${u['email']}${u['phone'] == null ? '' : '\n${u['phone']}'}',
                              style: const TextStyle(color: AppColors.muted)),
                          isThreeLine: u['phone'] != null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (s) => s == 'edit' ? _edit(u) : _delete(u),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(value: 'delete', child: Text('Xóa')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      );
}
