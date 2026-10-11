# Quản lý trung tâm ngoại ngữ

Flutter (mobile/) → Java Spring Boot API (backend/) → Supabase PostgreSQL (database/)

## 1. Database (Supabase)
1. Tạo project trên supabase.com.
2. SQL Editor → dán toàn bộ `database/schema.sql` → Run.
3. Connect → lấy chuỗi **Session pooler** (host dạng `aws-0-<region>.pooler.supabase.com`, port 5432,
   user `postgres.<project-ref>`). Dùng pooler vì host trực tiếp của Supabase thường chỉ có IPv6.

## 2. Backend (Java 17+, Maven)
```bash
cd backend
export DB_URL="jdbc:postgresql://aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require"
export DB_USER="postgres.<project-ref>"
export DB_PASSWORD="<mật khẩu database>"
export JWT_SECRET="<chuỗi bí mật ≥ 32 ký tự>"
mvn spring-boot:run
```
Lần chạy đầu tự tạo admin: `admin@center.com` / `admin123` (đổi bằng ADMIN_EMAIL, ADMIN_PASSWORD).
Trên Windows PowerShell dùng `$env:DB_URL="..."`. Hoặc tạo Run Configuration trong IDE với các biến môi trường trên.

## 3. Flutter
```bash
cd mobile
flutter create --project-name center_app --platforms=android,ios,web .   # sinh thư mục nền tảng, giữ nguyên lib/ và pubspec.yaml
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080/api
```
- Android emulator: `10.0.2.2`. Điện thoại thật: IP LAN của máy (VD `http://192.168.1.10:8080/api`)
  hoặc `adb reverse tcp:8080 tcp:8080` rồi dùng `http://localhost:8080/api`.
- Android chặn HTTP thường: thêm `android:usesCleartextTraffic="true"` vào thẻ `<application>` trong
  `android/app/src/main/AndroidManifest.xml` (chỉ dùng khi dev).

## Quy trình thử nhanh
1. Đăng nhập admin → thêm giáo viên, học viên (mật khẩu mặc định 123456).
2. Lớp học → thêm lớp (chọn khóa học + giáo viên) → mở lớp → thêm học viên.
3. Đăng nhập giáo viên → Lớp tôi dạy → tab Điểm danh.
4. Admin → Học phí → Thu tiền; Tổng quan xem thống kê.
5. Đăng nhập học viên → xem lịch học của mình.

## Phân quyền
| Vai trò | Quyền |
|---|---|
| ADMIN | Toàn bộ |
| TEACHER | Xem lớp mình dạy, danh sách học viên, điểm danh |
| STUDENT | Xem lớp mình đang học |

## API
| Method | Đường dẫn | Ghi chú |
|---|---|---|
| POST | /api/auth/login | công khai |
| GET | /api/auth/me · POST /api/auth/change-password | đã đăng nhập |
| GET/POST/PUT/DELETE | /api/users (?role=&q=) | admin |
| GET | /api/courses | đã đăng nhập; POST/PUT/DELETE: admin |
| GET | /api/classes, /api/classes/{id} | đã đăng nhập; POST/PUT/DELETE: admin |
| GET | /api/my/classes | lớp của tôi |
| GET | /api/classes/{id}/students | admin, giáo viên phụ trách |
| POST | /api/classes/{id}/enroll · DELETE /api/enrollments/{id} | admin |
| GET | /api/classes/{id}/attendance?date= · POST /api/attendance | admin, giáo viên phụ trách |
| GET/POST/DELETE | /api/payments · GET /api/payments/debts | admin |
| GET | /api/reports/summary | admin |

## Cấu trúc
```
database/schema.sql     6 bảng: users, courses, classes, enrollments, attendances, payments
backend/…/controller    Auth, User, Course, Class (+ghi danh, điểm danh), Payment, Report
backend/…/security      JWT + phân quyền theo vai trò
mobile/lib/api.dart     Dio client, lưu token
mobile/lib/widgets.dart Form động, Loader, tiện ích dùng chung
mobile/lib/pages/       login, home(drawer theo vai trò), dashboard, users, courses, classes, class_detail, payments
```

## Hạn chế / hướng mở rộng
- Học viên/giáo viên dùng chung bảng `users` (cột role); lịch học lưu dạng chữ (`schedule`).
- Mới là bản cơ bản: chưa có phân trang, quên mật khẩu, upload ảnh, thông báo đẩy.
- Trước khi triển khai thật: đổi JWT_SECRET, mật khẩu admin, giới hạn CORS trong `SecurityConfig`.
