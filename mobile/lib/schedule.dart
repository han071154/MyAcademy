/// Đọc chuỗi lịch học của lớp, vd "T2-T4-T6 18:00-19:30", "T7-CN 08:00-10:00".
/// Thứ theo DateTime.weekday: 1 = Thứ 2 ... 7 = Chủ nhật.
class ClassSlot {
  final int weekday;
  final int startMin, endMin; // phút tính từ 00:00
  const ClassSlot(this.weekday, this.startMin, this.endMin);

  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String get timeText => '${_hm(startMin)} - ${_hm(endMin)}';
}

const weekdayNames = {1: 'Thứ 2', 2: 'Thứ 3', 3: 'Thứ 4', 4: 'Thứ 5', 5: 'Thứ 6', 6: 'Thứ 7', 7: 'Chủ nhật'};

final _timeRe = RegExp(r'(\d{1,2})[:h](\d{2})\s*[-–]\s*(\d{1,2})[:h](\d{2})');
final _dayRe = RegExp(r'\b(T\s?[2-7]|CN|Thứ\s?[2-7]|Chủ\s?nhật)\b', caseSensitive: false);

/// Trả về danh sách buổi trong tuần; rỗng nếu không đọc được (lịch ghi tự do).
List<ClassSlot> parseSchedule(String? text) {
  if (text == null || text.trim().isEmpty) return const [];
  final t = _timeRe.firstMatch(text);
  if (t == null) return const [];
  final start = int.parse(t.group(1)!) * 60 + int.parse(t.group(2)!);
  final end = int.parse(t.group(3)!) * 60 + int.parse(t.group(4)!);
  final days = <int>{};
  for (final m in _dayRe.allMatches(text.substring(0, t.start))) {
    final tok = m.group(0)!.toLowerCase().replaceAll(' ', '');
    if (tok == 'cn' || tok.startsWith('chủ')) {
      days.add(7);
    } else {
      final n = int.tryParse(tok.substring(tok.length - 1));
      if (n != null && n >= 2 && n <= 7) days.add(n - 1); // "T2" = thứ Hai = weekday 1
    }
  }
  return [for (final d in days.toList()..sort()) ClassSlot(d, start, end)];
}
