# Quản lý trung tâm ngoại ngữ

Flutter (`mobile/`) → Supabase Cloud (trực tiếp, không cần backend Java)

## 1. Thiết lập Supabase (Chỉ làm 1 lần duy nhất)
1. Mở project trên [supabase.com](https://supabase.com).
2. Vào **SQL Editor** → Mở file `database/supabase_setup.sql`, dán toàn bộ nội dung và bấm **Run**.
   *(File này sẽ cấu hình quyền, bảng `assignments`, `submissions`, các view thống kê, tạo sẵn tài khoản Admin `admin@center.com` / mật khẩu `123456`).*

## 2. Chạy ứng dụng Flutter
Từ nay về sau, **bạn chỉ cần duy nhất 1 lệnh**:
```bash
cd mobile
flutter run
```
- Không cần cài đặt hay chạy backend Spring Boot.
- Không cần thiết lập biến môi trường phức tạp (`DB_URL`, `JWT_SECRET`,...).
- Flutter tự kết nối trực tiếp đến Supabase qua internet.

## 3. Các tính năng chính theo vai trò
- **Học viên (Student)**:
  - Trang chủ cá nhân hóa với Thẻ học viên, học phí đã nộp & công nợ, lịch học.
  - Tab **Lớp học**: Hiển thị trực tiếp các lớp đã đăng ký.
  - Mỗi lớp học có không gian riêng gồm:
    - **Bài tập**: Xem đề bài, hạn nộp, nộp bài bằng **file** hoặc **ảnh**, xem điểm số và nhận xét từ giảng viên.
    - **Điểm danh của tôi**: Thống kê số buổi có mặt / trễ / vắng và tỷ lệ chuyên cần.
    - **Thông tin lớp**: Xem lịch học, phòng học, học phí, giảng viên.
    - Nút đăng ký thêm khóa học mới (`StudentCoursesPage`).
- **Giáo viên (Teacher)**:
  - Trang chủ giảng viên: Lớp phụ trách, tổng số học viên, nút điểm danh nhanh.
  - Trong từng lớp dạy:
    - **Học viên**: Xem danh sách học viên trong lớp.
    - **Điểm danh**: Điểm danh từng buổi (Có mặt / Trễ / Vắng) kèm ghi chú.
    - **Bài tập**: Giao bài tập mới (hạn nộp, file đề bài đính kèm).
    - **Chấm điểm**: Xem danh sách học viên đã nộp, xem file/ảnh bài làm, chấm điểm (thang 10) và gửi nhận xét.
- **Quản trị viên (Admin)**:
  - Dashboard tổng quan doanh thu, thống kê 6 tháng.
  - Quản lý học viên, giáo viên, khóa học, lớp học và thu học phí.

## 4. Cấu trúc mã nguồn
```
database/supabase_setup.sql             Bảng assignments, submissions, views, RPC, RLS
mobile/lib/api.dart                     Supabase Client API + File/Image Upload
mobile/lib/pages/student_classes_page.dart         Danh sách lớp đã đăng ký của học viên
mobile/lib/pages/student_class_space_page.dart     Không gian lớp (Bài tập, Điểm danh, Thông tin)
mobile/lib/pages/student_assignment_detail_page.dart Chi tiết bài tập & nộp bài dạng file/ảnh
mobile/lib/pages/teacher_assignment_grading_page.dart Chấm điểm bài nộp & gửi nhận xét của GV
mobile/lib/pages/class_detail_page.dart            Chi tiết lớp (Học viên, Điểm danh, Giao bài)
```
