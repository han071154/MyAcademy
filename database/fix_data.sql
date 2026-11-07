-- =====================================================================
-- MyAcademy - DỌN DỮ LIỆU CŨ (chạy 1 lần, chạy lại vẫn an toàn)
--
-- Chạy SAU khi đã chạy lại database/student_rules.sql (cần hàm sync_class_status).
-- Kết quả hiện ở cuối: danh sách những chỗ còn cần admin tự xem lại.
-- =====================================================================

begin;

-- 1. Trạng thái lớp theo ngày: lớp đã khai giảng → Đang học, đã qua ngày kết thúc → Đã kết thúc.
select sync_class_status();

-- 2. Lớp "Đang học" mà không có học viên nào (vd Giao tiếp cơ bản K04) → coi như không mở được, đóng lại.
--    Admin muốn mở lại: vào Quản lý lớp, sửa trạng thái + ngày khai giảng mới.
update classes cl set status = 'CLOSED'
where cl.status = 'ONGOING'
  and not exists (select 1 from enrollments e where e.class_id = cl.id);

-- 3. Email viết hoa (vd TuanHa19@gmail.com) → chữ thường cho thống nhất với tài khoản đăng nhập.
update users set email = lower(trim(email)) where email <> lower(trim(email));
update auth.users set email = lower(trim(email)) where email <> lower(trim(email));

-- 4. Số điện thoại: bỏ khoảng trắng / dấu chấm / gạch ngang; số sai định dạng (vd 03245678, 012345678)
--    thì xóa đi để trang Hồ sơ nhắc người dùng tự nhập lại số đúng.
update users set phone = regexp_replace(phone, '[\s.-]', '', 'g') where phone ~ '[\s.-]';
update users set phone = null where phone is not null and phone !~ '^(0|\+84)[0-9]{9}$';

--    Từ nay database tự chặn số điện thoại sai định dạng (kể cả admin nhập).
alter table users drop constraint if exists users_phone_format;
alter table users add constraint users_phone_format check (phone is null or phone ~ '^(0|\+84)[0-9]{9}$');

-- 5. Giảng viên mẫu (@center.com) thiếu ngày sinh / địa chỉ → điền thông tin mẫu.
update users set dob = coalesce(dob, date '1988-03-15'), address = coalesce(address, '12 Nguyễn Huệ, Quận 1, TP.HCM')
where email = 'gv.lan@center.com';
update users set dob = coalesce(dob, date '1985-08-02'), address = coalesce(address, '45 Lê Duẩn, Quận 1, TP.HCM')
where email = 'gv.minh@center.com';
update users set dob = coalesce(dob, date '1982-11-20'), address = coalesce(address, '7 Pasteur, Quận 3, TP.HCM')
where email = 'gv.john@center.com';

-- 6. Tài khoản thử trùng người "Nguyễn Thị Thảo" (anxua30@gmail.com):
--    bỏ các lớp chưa đóng đồng nào (để không cộng nợ ảo vào báo cáo) và khóa tài khoản.
--    Tài khoản chính nguyenthithao5002@gmail.com KHÔNG bị đụng tới.
delete from enrollments e
using users u
where u.id = e.student_id and u.email = 'anxua30@gmail.com'
  and not exists (select 1 from payments p where p.enrollment_id = e.id);
update users set active = false where email = 'anxua30@gmail.com';
update auth.users set banned_until = 'infinity' where lower(email) = 'anxua30@gmail.com';

commit;

-- ---------------------------------------------------------------------
-- KẾT QUẢ: những chỗ còn cần admin tự xem lại (không có dòng nào = dữ liệu đã sạch)
-- ---------------------------------------------------------------------
select 'Học 2 lớp cùng khóa' as van_de, u.full_name as nguoi, u.email,
       co.name || ': ' || string_agg(cl.name, ', ') as chi_tiet
from enrollments e
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
join courses co on co.id = cl.course_id
where cl.status <> 'CLOSED'
group by u.id, u.full_name, u.email, co.name
having count(*) > 1

union all
select 'Thiếu thông tin hồ sơ', full_name, email,
       concat_ws(', ', case when phone is null then 'SĐT' end,
                       case when dob is null then 'ngày sinh' end,
                       case when address is null then 'địa chỉ' end)
from users
where active and role <> 'ADMIN' and (phone is null or dob is null or address is null)

union all
select 'Lớp đang mở chưa có giảng viên', null, null, name
from classes where status <> 'CLOSED' and teacher_id is null

order by 1, 2;
