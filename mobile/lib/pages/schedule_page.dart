import 'package:flutter/material.dart';

import '../api.dart';
import '../schedule.dart';
import '../theme.dart';
import '../widgets.dart';

/// Thời khóa biểu theo tuần, xem được tuần trước / tuần sau (bấm mũi tên, vuốt ngang, hoặc chọn ngày).
/// Mỗi ngày chỉ hiện buổi học thật sự diễn ra hôm đó (trong khoảng khai giảng → kết thúc của lớp).
/// Dùng chung cho học viên và giảng viên (dữ liệu từ /my/classes).
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _Session {
  final Map cls;
  final ClassSlot slot;
  const _Session(this.cls, this.slot);
}

class _SchedulePageState extends State<SchedulePage> {
  late Future<dynamic> _f = Api.i.get('/my/classes');
  void _reload() => setState(() => _f = Api.i.get('/my/classes'));

  static DateTime get _today => DateUtils.dateOnly(DateTime.now());
  static DateTime _mondayOf(DateTime d) => DateUtils.dateOnly(d).subtract(Duration(days: d.weekday - 1));

  /// Thứ 2 của tuần đang xem.
  DateTime _week = _mondayOf(DateTime.now());

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');
  static String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// Lớp có học vào ngày [d] không: trong khoảng khai giảng → kết thúc.
  /// Lớp đã đóng (CLOSED) thì chỉ còn các buổi trước hôm nay (lớp có thể bị đóng sớm).
  static bool _runsOn(Map c, DateTime d) {
    final s = _date(c['start_date']);
    final e = _date(c['end_date']);
    if (s != null && d.isBefore(s)) return false;
    if (e != null && d.isAfter(e)) return false;
    if (c['status'] == 'CLOSED' && !d.isBefore(_today)) return false;
    return true;
  }

  List<_Session> _sessionsOn(List<_Session> all, DateTime d) =>
      all.where((x) => x.slot.weekday == d.weekday && _runsOn(x.cls, d)).toList()
        ..sort((a, b) => a.slot.startMin.compareTo(b.slot.startMin));

  /// Buổi học gần nhất chưa kết thúc, tìm trong 3 tuần tới.
  (DateTime, _Session)? _next(List<_Session> all) {
    final now = DateTime.now();
    for (var i = 0; i < 21; i++) {
      final d = _today.add(Duration(days: i));
      for (final x in _sessionsOn(all, d)) {
        if (d.add(Duration(minutes: x.slot.endMin)).isAfter(now)) return (d, x);
      }
    }
    return null;
  }

  void _goWeek(int delta) => setState(() => _week = _week.add(Duration(days: 7 * delta)));

  Future<void> _pickWeek() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _week,
      firstDate: DateTime(_today.year - 2),
      lastDate: DateTime(_today.year + 2),
      helpText: 'Chọn 1 ngày trong tuần muốn xem',
    );
    if (d != null) setState(() => _week = _mondayOf(d));
  }

  String _dayLabel(DateTime d) {
    final diff = d.difference(_today).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Ngày mai';
    return '${weekdayNames[d.weekday]}, ${_dm(d)}';
  }

  Widget _nextCard((DateTime, _Session)? n) {
    if (n == null) {
      return const SoftCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.all(16),
        child: Row(children: [
          IconBox(Icons.event_busy_outlined, AppColors.muted),
          SizedBox(width: 12),
          Expanded(child: Text('Không có buổi học nào trong 3 tuần tới.', style: TextStyle(color: AppColors.muted))),
        ]),
      );
    }
    final (d, x) = n;
    final live = !d.add(Duration(minutes: x.slot.startMin)).isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0D9488)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(live ? 'ĐANG DIỄN RA' : 'BUỔI HỌC TIẾP THEO',
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text('${_dayLabel(d)} • ${x.slot.timeText}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${x.cls['name']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          'Phòng ${x.cls['room'] ?? '—'}'
          '${Api.i.role == 'STUDENT' && x.cls['teacher_name'] != null ? ' • GV ${x.cls['teacher_name']}' : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
      ]),
    );
  }

  /// Thanh chọn tuần: ‹  10/11 – 16/11 (Tuần này)  ›
  Widget _weekBar() {
    final end = _week.add(const Duration(days: 6));
    final diff = _week.difference(_mondayOf(DateTime.now())).inDays ~/ 7;
    final rel = switch (diff) {
      0 => 'Tuần này',
      -1 => 'Tuần trước',
      1 => 'Tuần sau',
      < 0 => '${-diff} tuần trước',
      _ => '$diff tuần sau',
    };
    return SoftCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(tooltip: 'Tuần trước', icon: const Icon(Icons.chevron_left), onPressed: () => _goWeek(-1)),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickWeek,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Text('${_dm(_week)} – ${_dm(end)}/${end.year}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(rel, style: TextStyle(color: diff == 0 ? AppColors.primary : AppColors.muted, fontSize: 13)),
                  const SizedBox(width: 4),
                  const Icon(Icons.calendar_month_outlined, size: 14, color: AppColors.muted),
                ]),
              ]),
            ),
          ),
        ),
        if (diff != 0)
          TextButton(onPressed: () => setState(() => _week = _mondayOf(DateTime.now())), child: const Text('Hôm nay')),
        IconButton(tooltip: 'Tuần sau', icon: const Icon(Icons.chevron_right), onPressed: () => _goWeek(1)),
      ]),
    );
  }

  Widget _sessionTile(_Session x, DateTime day) {
    final c = x.cls;
    final start = _date(c['start_date']);
    final end = _date(c['end_date']);
    final firstDay = start != null && DateUtils.isSameDay(start, day);
    final lastDay = end != null && DateUtils.isSameDay(end, day);
    final past = day.add(Duration(minutes: x.slot.endMin)).isBefore(DateTime.now());
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: SoftCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: tint(AppColors.primary), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(x.slot.timeText.split(' - ').first,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
              Text(x.slot.timeText.split(' - ').last, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                'Phòng ${c['room'] ?? '—'}'
                '${Api.i.role == 'STUDENT' ? ' • GV ${c['teacher_name'] ?? 'chưa phân công'}' : ' • ${c['enrolled'] ?? 0} học viên'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (firstDay || lastDay || past) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (firstDay) const Pill('Buổi khai giảng', AppColors.amber),
                  if (lastDay) const Pill('Buổi cuối khóa', AppColors.danger),
                  if (past) const Pill('Đã học', AppColors.muted),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Api.i.role == 'TEACHER' ? 'Lịch dạy' : 'Thời khóa biểu')),
        body: Loader(
          future: _f,
          onRetry: _reload,
          builder: (data) {
            final classes = (data as List).cast<Map>();
            final sessions = <_Session>[];
            final unknown = <Map>[];
            for (final c in classes) {
              final slots = parseSchedule(c['schedule']?.toString());
              if (slots.isEmpty && c['status'] != 'CLOSED') unknown.add(c);
              sessions.addAll(slots.map((s) => _Session(c, s)));
            }
            final isThisWeek = DateUtils.isSameDay(_week, _mondayOf(DateTime.now()));
            final days = [for (var i = 0; i < 7; i++) _week.add(Duration(days: i))];
            final weekCount = days.fold<int>(0, (n, d) => n + _sessionsOn(sessions, d).length);

            return GestureDetector(
              // Vuốt ngang để đổi tuần.
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 300) _goWeek(v < 0 ? 1 : -1);
              },
              child: RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _f;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (isThisWeek) ...[
                      _nextCard(_next(sessions)),
                      const SizedBox(height: 14),
                    ],
                    _weekBar(),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        weekCount == 0 ? 'Không có buổi học nào trong tuần' : '$weekCount buổi học trong tuần',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                    for (final d in days) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Row(children: [
                          Text('${weekdayNames[d.weekday]} • ${_dm(d)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: DateUtils.isSameDay(d, _today) ? AppColors.primary : null)),
                          if (DateUtils.isSameDay(d, _today)) ...[
                            const SizedBox(width: 8),
                            const Pill('Hôm nay', AppColors.primary),
                          ],
                        ]),
                      ),
                      ...() {
                        final list = _sessionsOn(sessions, d);
                        if (list.isEmpty) {
                          return [
                            const Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 10),
                              child: Text('Không có lịch', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            ),
                          ];
                        }
                        return [for (final x in list) _sessionTile(x, d), const SizedBox(height: 6)];
                      }(),
                    ],
                    if (unknown.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Lịch chưa cố định', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      for (final c in unknown)
                        SoftCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${c['schedule'] ?? 'Chưa xếp lịch'} • Phòng ${c['room'] ?? '—'}'),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    const Text('Bấm ‹ › hoặc vuốt ngang để xem tuần trước / tuần sau. Bấm vào ngày để chọn tuần bất kỳ.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
