import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<dynamic> _f = Api.i.get('/reports/summary');
  void _reload() => setState(() => _f = Api.i.get('/reports/summary'));

  num _n(dynamic v) => num.tryParse('$v') ?? 0;

  Widget _hero(BuildContext context, Map s) {
    final debt = _n(s['total_debt']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Thu tháng này', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text(vnd(s['month_revenue']),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _heroStat('Tổng đã thu', vnd(s['total_revenue']), Colors.white)),
          Container(width: 1, height: 36, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(child: _heroStat('Công nợ', vnd(debt), debt > 0 ? const Color(0xFFFFD58A) : Colors.white)),
        ]),
      ]),
    );
  }

  Widget _heroStat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      );

  Widget _stat(IconData icon, String label, dynamic value, Color color) => Expanded(
        child: SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconBox(icon, color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      );

  Widget _monthly(List monthly) {
    num maxV = 0;
    for (final m in monthly) {
      final v = _n(m['total']);
      if (v > maxV) maxV = v;
    }
    return SoftCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        for (final m in monthly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 64, child: Text('${m['month']}', style: const TextStyle(color: AppColors.muted))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: maxV == 0 ? 0 : (_n(m['total']) / maxV).toDouble(),
                    minHeight: 10,
                    color: AppColors.primary,
                    backgroundColor: tint(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(vnd(m['total']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Loader(
        future: _f,
        onRetry: _reload,
        builder: (data) {
          final s = data as Map;
          final monthly = (s['monthly'] as List?) ?? [];
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _f;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _hero(context, s),
                const SizedBox(height: 16),
                Row(children: [
                  _stat(Icons.school_outlined, 'Học viên', s['students'], AppColors.primary),
                  const SizedBox(width: 12),
                  _stat(Icons.person_outline, 'Giáo viên', s['teachers'], const Color(0xFF3B6FD4)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _stat(Icons.menu_book_outlined, 'Khóa học', s['courses'], AppColors.amber),
                  const SizedBox(width: 12),
                  _stat(Icons.class_outlined, 'Lớp đang mở', s['active_classes'], const Color(0xFF8A5BD4)),
                ]),
                const SizedBox(height: 24),
                Text('Doanh thu theo tháng',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (monthly.isEmpty)
                  const SoftCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('Chưa có khoản thu nào', style: TextStyle(color: AppColors.muted))),
                  )
                else
                  _monthly(monthly),
              ],
            ),
          );
        },
      );
}
