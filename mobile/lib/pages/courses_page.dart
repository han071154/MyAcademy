import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  late Future<dynamic> _f = Api.i.get('/courses');
  void _reload() => setState(() { _f = Api.i.get('/courses'); });

  Future<void> _edit([Map? c]) async {
    final v = await showForm(
      context,
      c == null ? 'Thêm khóa học' : 'Sửa khóa học',
      const [
        Field('name', 'Tên khóa học', required: true),
        Field('level', 'Trình độ'),
        Field('duration_weeks', 'Thời lượng (tuần)', type: FieldType.number),
        Field('fee', 'Học phí (VNĐ)', type: FieldType.number, required: true),
        Field('description', 'Mô tả'),
      ],
      initial: c == null ? null : Map<String, dynamic>.from(c),
    );
    if (v == null || !mounted) return;
    final ok = await guard(
        context, () => c == null ? Api.i.post('/courses', v) : Api.i.put('/courses/${c['id']}', v));
    if (ok) _reload();
  }

  Future<void> _delete(Map c) async {
    if (!await confirm(context, 'Xóa khóa học "${c['name']}"?')) return;
    if (!mounted) return;
    if (await guard(context, () => Api.i.delete('/courses/${c['id']}'))) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final list = data as List;
            if (list.isEmpty) return const EmptyState('Chưa có khóa học');
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _f;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i] as Map;
                  return SoftCard(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                      leading: const IconBox(Icons.menu_book_outlined, AppColors.primary),
                      title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${c['level'] ?? ''} • ${c['duration_weeks'] ?? 0} tuần\n'
                          'Học phí: ${vnd(c['fee'])}',
                          style: const TextStyle(color: AppColors.muted)),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (s) => s == 'edit' ? _edit(c) : _delete(c),
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
      );
}
