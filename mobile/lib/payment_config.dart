/// Thông tin tài khoản nhận học phí của trung tâm (hiện trên màn hình Đóng học phí).
/// Đổi tài khoản: thay ảnh assets/images/payment_qr.png và sửa các dòng bên dưới.
class PaymentConfig {
  PaymentConfig._();

  /// Ảnh mã QR chuyển khoản của trung tâm.
  static const qrAsset = 'assets/images/payment_qr.png';

  /// Tên chủ tài khoản (in trên mã QR).
  static const accountName = 'NGUYEN THI THAO';

  /// Nội dung chuyển khoản để trung tâm đối soát: "MYA <mã học viên> <mã lớp>".
  /// Phải khớp với cách server tạo transfer_code trong database/payment_requests.sql.
  static String transferCode(int? studentId, int classId) => 'MYA ${studentId ?? ''} $classId';
}
