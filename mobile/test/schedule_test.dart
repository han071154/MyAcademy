import 'package:center_app/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> days(String s) => parseSchedule(s).map((e) => e.weekday).toList();

  test('đọc các kiểu lịch đang có trong dữ liệu', () {
    expect(days('T2-T4-T6 18:00-19:30'), [1, 3, 5]);
    expect(days('T3-T5 19:45-21:00'), [2, 4]);
    expect(days('T7-CN 08:00-10:00'), [6, 7]);
    expect(days('T7 14:00-16:00'), [6]);
    expect(days('T3-T5-T7 17:30-19:00'), [2, 4, 6]);
  });

  test('giờ học', () {
    final s = parseSchedule('T2-T4 19:45-21:00').first;
    expect(s.startMin, 19 * 60 + 45);
    expect(s.endMin, 21 * 60);
    expect(s.timeText, '19:45 - 21:00');
  });

  test('cách viết khác', () {
    expect(days('Thứ 2, Thứ 5 8h00-9h30'), [1, 4]);
    expect(days('t3 - cn 18:00 - 20:00'), [2, 7]);
  });

  test('không đọc được thì trả rỗng', () {
    expect(parseSchedule(null), isEmpty);
    expect(parseSchedule(''), isEmpty);
    expect(parseSchedule('Liên hệ trung tâm'), isEmpty);
  });
}
