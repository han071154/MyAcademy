-- =====================================================================
-- MyAcademy - XEM TOÀN BỘ DỮ LIỆU (chỉ đọc, không sửa gì)
--
-- Cách dùng trong Supabase → SQL Editor:
--   Supabase chỉ hiện kết quả của câu lệnh CUỐI CÙNG được chạy.
--   → Bôi đen 1 câu (từ "select" tới dấu ";") rồi bấm Run (hoặc Ctrl + Enter)
--     để xem từng bảng một.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TỔNG QUAN: mỗi loại dữ liệu có bao nhiêu dòng
-- ---------------------------------------------------------------------
select 'Admin'              as loai, count(*) as so_luong from users where role = 'ADMIN'
union all select 'Giảng viên',        count(*) from users where role = 'TEACHER'
union all select 'Học viên',          count(*) from users where role = 'STUDENT'
union all select 'Tài khoản bị khóa', count(*) from users where not active
union all select 'Khóa học',          count(*) from courses
union all select 'Lớp học',           count(*) from classes
union all select 'Lượt ghi danh',     count(*) from enrollments
union all select 'Khoản thu',         count(*) from payments
union all select 'Báo chuyển khoản',  count(*) from payment_requests
union all select 'Bài tập',           count(*) from assignments
union all select 'Bài nộp',           count(*) from submissions
union all select 'Lượt điểm danh',    count(*) from attendances;


-- ---------------------------------------------------------------------
-- 2. ADMIN
-- ---------------------------------------------------------------------
select u.id, u.full_name as ho_ten, u.email, u.phone as sdt, u.active as dang_hoat_dong,
       u.must_change_password as phai_doi_mk, a.last_sign_in_at as dang_nhap_gan_nhat
from users u left join auth.users a on a.id = u.auth_id
where u.role = 'ADMIN'
order by u.id;


-- ---------------------------------------------------------------------
-- 3. GIẢNG VIÊN: thông tin + số lớp theo trạng thái + số học viên
-- ---------------------------------------------------------------------
select u.id, u.full_name as ho_ten, u.email, u.phone as sdt, u.dob as ngay_sinh, u.address as dia_chi,
       u.active as dang_hoat_dong,
       count(cl.id)                                         as tong_lop,
       count(cl.id) filter (where cl.status = 'ONGOING')    as dang_day,
       count(cl.id) filter (where cl.status = 'OPEN')       as sap_khai_giang,
       count(cl.id) filter (where cl.status = 'CLOSED')     as da_ket_thuc,
       coalesce(sum((select count(*) from enrollments e where e.class_id = cl.id)), 0) as tong_hoc_vien,
       a.last_sign_in_at as dang_nhap_gan_nhat
from users u
left join classes cl on cl.teacher_id = u.id
left join auth.users a on a.id = u.auth_id
where u.role = 'TEACHER'
group by u.id, a.last_sign_in_at
order by u.id;


-- ---------------------------------------------------------------------
-- 4. HỌC VIÊN: thông tin + số lớp + học phí / đã đóng / còn nợ
-- ---------------------------------------------------------------------
select u.id, u.full_name as ho_ten, u.email, u.phone as sdt, u.dob as ngay_sinh, u.address as dia_chi,
       u.active as dang_hoat_dong, u.must_change_password as phai_doi_mk,
       count(d.enrollment_id)          as so_lop,
       coalesce(sum(d.fee), 0)         as tong_hoc_phi,
       coalesce(sum(d.paid), 0)        as da_dong,
       coalesce(sum(d.debt), 0)        as con_no,
       u.created_at                    as ngay_tao_tk,
       a.last_sign_in_at               as dang_nhap_gan_nhat
from users u
left join enrollments e on e.student_id = u.id
left join v_debts d on d.enrollment_id = e.id
left join auth.users a on a.id = u.auth_id
where u.role = 'STUDENT'
group by u.id, a.last_sign_in_at
order by u.id;


-- ---------------------------------------------------------------------
-- 5. KHÓA HỌC: học phí + số lớp + số học viên
-- ---------------------------------------------------------------------
select co.id, co.name as khoa_hoc, co.level as trinh_do, co.duration_weeks as so_tuan, co.fee as hoc_phi,
       count(distinct cl.id) as so_lop,
       count(e.id)           as so_hoc_vien,
       co.description        as mo_ta
from courses co
left join classes cl on cl.course_id = co.id
left join enrollments e on e.class_id = cl.id
group by co.id
order by co.id;


-- ---------------------------------------------------------------------
-- 6. LỚP HỌC: khóa, giảng viên, lịch, sĩ số, trạng thái
-- ---------------------------------------------------------------------
select cl.id, cl.name as lop, co.name as khoa_hoc, t.full_name as giang_vien,
       case cl.status when 'OPEN' then 'Đang mở đăng ký' when 'ONGOING' then 'Đang học' else 'Đã kết thúc' end as trang_thai,
       cl.start_date as khai_giang, cl.end_date as ket_thuc, cl.schedule as lich_hoc, cl.room as phong,
       (select count(*) from enrollments e where e.class_id = cl.id) || '/' || cl.max_students as si_so,
       co.fee as hoc_phi
from classes cl
join courses co on co.id = cl.course_id
left join users t on t.id = cl.teacher_id
order by cl.id;


-- ---------------------------------------------------------------------
-- 7. GHI DANH: ai học lớp nào, đóng bao nhiêu, còn nợ bao nhiêu
-- ---------------------------------------------------------------------
select e.id as ma_ghi_danh, u.full_name as hoc_vien, u.email, cl.name as lop, cl.status as trang_thai_lop,
       d.fee as hoc_phi, d.paid as da_dong, d.debt as con_no,
       (select coalesce(sum(r.amount), 0) from payment_requests r
         where r.enrollment_id = e.id and r.status = 'PENDING') as cho_xac_nhan,
       e.enrolled_at as ngay_dang_ky
from enrollments e
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
join v_debts d on d.enrollment_id = e.id
order by cl.id, u.full_name;


-- ---------------------------------------------------------------------
-- 8. LỊCH SỬ THU TIỀN (mới nhất trước)
-- ---------------------------------------------------------------------
select p.id, p.paid_at as ngay_thu, p.student_name as hoc_vien, p.class_name as lop, p.amount as so_tien,
       case p.method when 'CASH' then 'Tiền mặt' when 'TRANSFER' then 'Chuyển khoản' when 'CARD' then 'Thẻ' else p.method end as hinh_thuc,
       p.note as ghi_chu
from v_payments p
order by p.paid_at desc;


-- ---------------------------------------------------------------------
-- 9. HỌC VIÊN BÁO CHUYỂN KHOẢN (chờ xác nhận / đã xác nhận / bị từ chối)
-- ---------------------------------------------------------------------
select r.id, r.created_at as ngay_bao, r.student_name as hoc_vien, r.class_name as lop, r.amount as so_tien,
       r.transfer_code as noi_dung_ck,
       case r.status when 'PENDING' then 'Chờ xác nhận' when 'CONFIRMED' then 'Đã xác nhận' else 'Bị từ chối' end as trang_thai,
       r.reject_reason as ly_do_tu_choi, r.reviewed_at as ngay_xu_ly
from v_payment_requests r
order by (r.status = 'PENDING') desc, r.created_at desc;


-- ---------------------------------------------------------------------
-- 10. BÀI TẬP: hạn nộp + đã nộp / đã chấm / nộp muộn
-- ---------------------------------------------------------------------
select a.id, cl.name as lop, a.title as bai_tap, t.full_name as giang_vien, a.due_date as han_nop,
       case when a.due_date < now() then 'Đã hết hạn' else 'Còn hạn' end as tinh_trang,
       (select count(*) from enrollments e where e.class_id = a.class_id)                    as si_so,
       count(s.id)                                                                           as da_nop,
       count(s.id) filter (where s.score is not null)                                        as da_cham,
       count(s.id) filter (where s.score is null)                                            as cho_cham,
       count(s.id) filter (where a.due_date is not null and s.submitted_at > a.due_date)     as nop_muon
from assignments a
join classes cl on cl.id = a.class_id
left join users t on t.id = a.teacher_id
left join submissions s on s.assignment_id = a.id
group by a.id, cl.name, t.full_name
order by a.class_id, a.due_date;


-- ---------------------------------------------------------------------
-- 11. BÀI NỘP CHI TIẾT: ai nộp, lúc nào, có muộn không, điểm bao nhiêu
-- ---------------------------------------------------------------------
select s.id, a.title as bai_tap, s.student_name as hoc_vien, s.submitted_at as luc_nop,
       case when s.is_late then 'Nộp muộn' else 'Đúng hạn' end as dung_han,
       coalesce(s.score::text, 'Chưa chấm') as diem, s.feedback as nhan_xet,
       s.notes as ghi_chu_hoc_vien, s.file_name as tep_dinh_kem
from v_submissions s
join assignments a on a.id = s.assignment_id
order by a.id, s.student_name;


-- ---------------------------------------------------------------------
-- 12. ĐIỂM DANH TỔNG HỢP: mỗi học viên trong mỗi lớp
-- ---------------------------------------------------------------------
select cl.name as lop, u.full_name as hoc_vien,
       count(at.id)                                         as so_buoi,
       count(at.id) filter (where at.status = 'PRESENT')    as co_mat,
       count(at.id) filter (where at.status = 'LATE')       as di_tre,
       count(at.id) filter (where at.status = 'ABSENT')     as vang,
       case when count(at.id) = 0 then null
            else round(100.0 * count(at.id) filter (where at.status <> 'ABSENT') / count(at.id)) end as ty_le_chuyen_can
from enrollments e
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
left join attendances at on at.enrollment_id = e.id
group by cl.id, cl.name, u.full_name
order by cl.id, u.full_name;


-- ---------------------------------------------------------------------
-- 13. ĐIỂM DANH CHI TIẾT TỪNG BUỔI (mới nhất trước)
-- ---------------------------------------------------------------------
select at.session_date as ngay, cl.name as lop, u.full_name as hoc_vien,
       case at.status when 'PRESENT' then 'Có mặt' when 'LATE' then 'Đi trễ' else 'Vắng' end as trang_thai,
       at.note as ghi_chu
from attendances at
join enrollments e on e.id = at.enrollment_id
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
order by at.session_date desc, cl.name, u.full_name;


-- ---------------------------------------------------------------------
-- 14. TRA CỨU 1 HỌC VIÊN THEO EMAIL (sửa email trong dấu nháy rồi chạy)
-- ---------------------------------------------------------------------
select u.full_name as ho_ten, cl.name as lop, cl.status as trang_thai_lop,
       d.fee as hoc_phi, d.paid as da_dong, d.debt as con_no,
       (select count(*) from submissions s join assignments a on a.id = s.assignment_id
         where s.student_id = u.id and a.class_id = cl.id) as bai_da_nop,
       (select count(*) from assignments a where a.class_id = cl.id) as tong_bai_tap,
       (select count(*) from attendances at where at.enrollment_id = e.id and at.status = 'ABSENT') as buoi_vang
from users u
left join enrollments e on e.student_id = u.id
left join classes cl on cl.id = e.class_id
left join v_debts d on d.enrollment_id = e.id
where lower(u.email) = lower('nguyenthithao5002@gmail.com')
order by cl.id;


-- ---------------------------------------------------------------------
-- 15. TRA CỨU 1 GIẢNG VIÊN THEO EMAIL (sửa email trong dấu nháy rồi chạy)
-- ---------------------------------------------------------------------
select u.full_name as giang_vien, cl.name as lop, cl.status as trang_thai_lop, cl.schedule as lich_hoc,
       (select count(*) from enrollments e where e.class_id = cl.id) as si_so,
       (select count(*) from assignments a where a.class_id = cl.id) as so_bai_tap,
       (select count(*) from submissions s join assignments a on a.id = s.assignment_id
         where a.class_id = cl.id and s.score is null) as bai_cho_cham
from users u
left join classes cl on cl.teacher_id = u.id
where lower(u.email) = lower('anxua40@gmail.com')
order by cl.id;
