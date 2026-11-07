# Quản lý trung tâm ngoại ngữ

Flutter (`mobile/`) → Supabase Cloud (PostgreSQL + Auth + Storage), không cần server riêng

## 1. Thiết lập Supabase (Chỉ làm 1 lần duy nhất)
1. Mở project trên [supabase.com](https://supabase.com).
2. Vào **SQL Editor**:
   - Cài mới: chạy `database/schema.sql`, sau đó chạy `database/supabase_setup.sql`.
   - Đã có dữ liệu: chỉ chạy `database/supabase_setup.sql`. Tài khoản cũ được chuyển sang Supabase Auth và **giữ nguyên mật khẩu**.
   - Chạy lại file này nhiều lần vẫn an toàn.
   - Sau đó chạy `database/student_signup.sql` để bật chức năng **học viên tự đăng ký**. Mỗi lần chạy lại `supabase_setup.sql` thì chạy lại file này.
   - Tiếp theo chạy `database/student_rules.sql`: khóa nộp lại bài đã chấm, server tự ghi giờ nộp và chặn nộp sau hạn, mỗi khóa học chỉ đăng ký 1 lớp đang học. Chạy lại `supabase_setup.sql` thì cũng chạy lại file này.
   - Cuối cùng chạy `database/payment_requests.sql`: học viên đóng học phí bằng chuyển khoản theo mã QR, admin xác nhận ở mục Học phí → tab *Chờ xác nhận*. Đổi tài khoản nhận tiền: thay ảnh `mobile/assets/images/payment_qr.png` và sửa `mobile/lib/payment_config.dart`.
   - Dữ liệu cũ từ trước: chạy `database/fix_data.sql` (sau `student_rules.sql`) để đồng bộ trạng thái lớp, chuẩn hóa email/SĐT và liệt kê chỗ còn thiếu. Xem toàn bộ dữ liệu: `database/inspect_data.sql`.
   - (Tùy chọn) chạy `database/demo_data.sql` để có dữ liệu mẫu đủ tình huống. Danh sách tài khoản demo nằm ở đầu file; mật khẩu tài khoản demo mới tạo là `Demo@1234`.
3. Vào **Authentication → Sign In / Providers**:
   - Tắt **Allow new users to sign up**. Học viên vẫn tự đăng ký được trong app qua hàm `register_student` (chỉ tạo được vai trò Học viên); tài khoản giảng viên do admin tạo.
   - Đặt **Minimum password length** = 8.
4. Vào **Authentication → Emails → Reset Password**: thêm mã `{{ .Token }}` vào nội dung email, ví dụ `Mã đặt lại mật khẩu của bạn: {{ .Token }}`. App dùng mã này cho chức năng *Quên mật khẩu*.
5. Khi dùng thật, cấu hình **Custom SMTP** (Authentication → Emails → SMTP Settings). SMTP mặc định của Supabase chỉ gửi được tới email thành viên của project và giới hạn vài email mỗi giờ.

Tài khoản Admin mặc định: `admin@center.com` / `123456`. Bạn **bắt buộc phải đổi mật khẩu ở lần đăng nhập đầu**.

### Bảo mật & phân quyền
- Đăng nhập bằng **Supabase Auth**. Mật khẩu chỉ nằm trong `auth.users` (đã băm), bảng `users` không còn cột mật khẩu.
- Mọi bảng đều bật **RLS**. Khách chưa đăng nhập (anon) không đọc hay ghi được gì. Quyền theo vai trò được kiểm tra ở server:
  - Admin: toàn quyền.
  - Giảng viên: chỉ xem lớp mình dạy, điểm danh, giao bài và chấm bài lớp đó. Không sửa được khóa học hay học phí.
  - Học viên: chỉ xem lớp, điểm danh, học phí, bài nộp của mình. Không tự cho điểm được.
- Các hàm RPC tự xác định người gọi theo phiên đăng nhập, không tin `user_id`/`role` gửi từ app.
- Admin tạo tài khoản thì **phải nhập mật khẩu khởi tạo** (không còn mặc định `123456`). Người dùng bị bắt đổi mật khẩu ở lần đăng nhập đầu. Admin đặt lại mật khẩu cũng vậy.
- Bucket `submissions` để **private**. Tệp chỉ xem được qua link tạm thời (signed URL, hết hạn sau 1 giờ), và chỉ người có quyền với bài tập hoặc bài nộp đó mới tạo được link.

## 2. Chạy ứng dụng Flutter
Từ nay về sau, **bạn chỉ cần duy nhất 1 lệnh**:
```bash
cd mobile
flutter run
```
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
database/supabase_setup.sql             Supabase Auth, RLS, views, RPC, Storage policy
mobile/lib/pages/password_pages.dart    Quên mật khẩu, bắt đổi mật khẩu lần đầu
mobile/lib/api.dart                     Supabase Client API + File/Image Upload
mobile/lib/pages/student_classes_page.dart         Danh sách lớp đã đăng ký của học viên
mobile/lib/pages/student_class_space_page.dart     Không gian lớp (Bài tập, Điểm danh, Thông tin)
mobile/lib/pages/student_assignment_detail_page.dart Chi tiết bài tập & nộp bài dạng file/ảnh
mobile/lib/pages/teacher_assignment_grading_page.dart Chấm điểm bài nộp & gửi nhận xét của GV
mobile/lib/pages/class_detail_page.dart            Chi tiết lớp (Học viên, Điểm danh, Giao bài)
```
