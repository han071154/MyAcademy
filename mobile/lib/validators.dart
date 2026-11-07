import 'api.dart';

/// Kiểm tra dữ liệu nhập, dùng chung cho form Đăng ký / Sửa hồ sơ / Đổi mật khẩu.
/// Trả về câu báo lỗi, hoặc null nếu hợp lệ. Server vẫn kiểm tra lại lần nữa.
class V {
  V._();

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phoneRe = RegExp(r'^(0|\+84)[0-9]{9}$');

  /// Bỏ khoảng trắng, dấu chấm, gạch ngang trong số điện thoại.
  static String cleanPhone(String s) => s.replaceAll(RegExp(r'[\s.-]'), '');

  static String? required(String? v, String msg) => (v == null || v.trim().isEmpty) ? msg : null;

  static String? name(String? v) {
    final e = required(v, 'Vui lòng nhập họ tên');
    if (e != null) return e;
    if (v!.trim().length < 2) return 'Họ tên quá ngắn';
    if (v.trim().length > 100) return 'Họ tên tối đa 100 ký tự';
    return null;
  }

  static String? email(String? v) {
    final e = required(v, 'Vui lòng nhập email');
    if (e != null) return e;
    if (!_emailRe.hasMatch(v!.trim())) return 'Email không đúng định dạng (vd: ten@gmail.com)';
    return null;
  }

  static String? phone(String? v) {
    final e = required(v, 'Vui lòng nhập số điện thoại');
    if (e != null) return e;
    if (!_phoneRe.hasMatch(cleanPhone(v!))) return 'Số điện thoại gồm 10 số, bắt đầu bằng 0';
    return null;
  }

  static String? address(String? v) {
    final e = required(v, 'Vui lòng nhập địa chỉ');
    if (e != null) return e;
    if (v!.trim().length > 255) return 'Địa chỉ tối đa 255 ký tự';
    return null;
  }

  static String? password(String? v, {String empty = 'Vui lòng nhập mật khẩu'}) {
    if (v == null || v.isEmpty) return empty;
    if (v.length < Api.minPasswordLength) {
      return 'Mật khẩu phải có ít nhất ${Api.minPasswordLength} ký tự (còn thiếu ${Api.minPasswordLength - v.length})';
    }
    if (v.length > 72) return 'Mật khẩu tối đa 72 ký tự';
    return null;
  }

  static String? Function(String?) confirm(String Function() original) => (v) {
        if (v == null || v.isEmpty) return 'Vui lòng nhập lại mật khẩu';
        if (v != original()) return 'Mật khẩu nhập lại không khớp';
        return null;
      };

  /// Ngày sinh hợp lệ: từ năm 1900 tới cách đây ít nhất 5 năm.
  static DateTime get latestDob {
    final n = DateTime.now();
    return DateTime(n.year - 5, n.month, n.day);
  }
}
