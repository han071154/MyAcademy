-- =====================================================================
-- MyAcademy - DỮ LIỆU MẪU ĐỂ DEMO (đủ các tình huống)
--
-- Chạy SAU: supabase_setup.sql, student_signup.sql, student_rules.sql, payment_requests.sql.
-- Chạy lại nhiều lần vẫn an toàn: cái gì đã có thì bỏ qua, không tạo trùng.
--
-- Mật khẩu của mọi tài khoản demo MỚI tạo: Demo@1234
-- Tài khoản đã có sẵn (vd bạn đã tự đăng ký nguyenthithao5002@gmail.com) thì GIỮ NGUYÊN mật khẩu cũ.
-- Ngày tháng tính theo ngày chạy file, nên lúc nào demo cũng có bài "sắp hết hạn", "quá hạn"...
--
-- TÀI KHOẢN DEMO
--   Giảng viên
--     anxua40@gmail.com          Nguyễn Kim Tuyền   dạy 4 lớp: đang dạy / đang mở / đã kết thúc / đã đầy
--     khoa.tran.demo@gmail.com   Trần Minh Khoa     dạy 1 lớp đang học
--     trang.le.demo@gmail.com    Lê Thu Trang       chưa được phân công lớp nào
--   Học viên
--     nguyenthithao5002@gmail.com Nguyễn Thị Thảo  (tài khoản của bạn) đang học 1 lớp, còn nợ, có 1 chuyển khoản
--                                 chờ xác nhận, có bài đã chấm / chờ chấm / chưa nộp / quá hạn; 1 lớp đã học xong
--     nam.le.demo@gmail.com      Lê Hoàng Nam     học viên giỏi: đóng đủ, nộp bài sớm, điểm cao
--     ha.pham.demo@gmail.com     Phạm Thu Hà      chưa đóng đồng nào, hay nộp muộn; đã đăng ký 1 lớp sắp mở (hủy được)
--     huy.do.demo@gmail.com      Đỗ Quang Huy     đóng 1 phần, chuyển khoản bị TỪ CHỐI
--     anh.vu.demo@gmail.com      Vũ Ngọc Ánh      chuyển khoản ĐÃ XÁC NHẬN, đóng đủ lớp đang học
--     tung.bui.demo@gmail.com    Bùi Thanh Tùng   học 3 lớp, 2 giảng viên; bị bắt đổi mật khẩu khi đăng nhập
--     linh.hoang.demo@gmail.com  Hoàng Mai Linh   tài khoản BỊ KHÓA (không đăng nhập được), còn nợ lớp đã kết thúc
--     bao.ngo.demo@gmail.com     Ngô Gia Bảo      học viên mới, chưa đăng ký lớp nào
--     (thiếu thông tin hồ sơ)    Đặng Văn Phúc    phuc.dang.demo@gmail.com: chưa có SĐT/ngày sinh/địa chỉ
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.payment_requests') is null then
    raise exception 'Hãy chạy database/payment_requests.sql trước khi chạy file dữ liệu mẫu';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Hàm hỗ trợ tạm thời (chỉ tồn tại trong lần chạy này)
-- ---------------------------------------------------------------------

-- Tạo tài khoản nếu chưa có (theo email). Có rồi thì trả về id, không đổi gì.
create function pg_temp.demo_user(
  p_email text, p_name text, p_role text, p_phone text, p_dob date, p_address text,
  p_must_change boolean default false, p_active boolean default true
) returns bigint language plpgsql as $$
declare
  v_id bigint;
  v_auth uuid;
begin
  select id into v_id from public.users where lower(email) = lower(p_email);
  if v_id is not null then return v_id; end if;

  select id into v_auth from auth.users where lower(email) = lower(p_email);
  if v_auth is null then
    v_auth := public._create_auth_user(p_email, 'Demo@1234');
  end if;
  insert into public.users (email, full_name, role, phone, dob, address, auth_id, must_change_password, active)
  values (lower(p_email), p_name, p_role, p_phone, p_dob, p_address, v_auth, p_must_change, p_active)
  returning id into v_id;
  if not p_active then
    update auth.users set banned_until = 'infinity' where id = v_auth;
  end if;
  return v_id;
end $$;

create function pg_temp.demo_course(p_name text, p_level text, p_weeks int, p_fee numeric, p_desc text)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  select id into v_id from public.courses where name = p_name;
  if v_id is null then
    insert into public.courses (name, level, duration_weeks, fee, description)
    values (p_name, p_level, p_weeks, p_fee, p_desc) returning id into v_id;
  end if;
  return v_id;
end $$;

create function pg_temp.demo_class(
  p_name text, p_course bigint, p_teacher bigint, p_start date, p_end date,
  p_schedule text, p_room text, p_max int, p_status text
) returns bigint language plpgsql as $$
declare v_id bigint;
begin
  select id into v_id from public.classes where name = p_name;
  if v_id is null then
    insert into public.classes (name, course_id, teacher_id, start_date, end_date, schedule, room, max_students, status)
    values (p_name, p_course, p_teacher, p_start, p_end, p_schedule, p_room, p_max, p_status) returning id into v_id;
  end if;
  return v_id;
end $$;

-- Ghi danh. Bỏ qua (trả về null) nếu học viên đã có lớp khác chưa kết thúc của cùng khóa,
-- giống quy tắc trong app (vd bạn đã tự đăng ký 1 lớp trước đó).
create function pg_temp.demo_enroll(p_student bigint, p_class bigint, p_days_ago int)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  select id into v_id from public.enrollments where student_id = p_student and class_id = p_class;
  if v_id is not null then return v_id; end if;
  if exists (select 1 from public.enrollments e join public.classes c on c.id = e.class_id
             where e.student_id = p_student and c.status <> 'CLOSED'
               and c.course_id = (select course_id from public.classes where id = p_class)) then
    raise notice 'Bỏ qua ghi danh HV % vào lớp %: đã có lớp khác cùng khóa', p_student, p_class;
    return null;
  end if;
  insert into public.enrollments (student_id, class_id, enrolled_at)
  values (p_student, p_class, now() - make_interval(days => p_days_ago)) returning id into v_id;
  return v_id;
end $$;

-- Khoản thu (không tạo trùng: nhận diện theo ghi chú).
create function pg_temp.demo_pay(p_eid bigint, p_amount numeric, p_method text, p_days_ago int, p_note text)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  if p_eid is null then return null; end if;
  select id into v_id from public.payments where enrollment_id = p_eid and note = p_note;
  if v_id is null then
    insert into public.payments (enrollment_id, amount, method, paid_at, note)
    values (p_eid, p_amount, p_method, now() - make_interval(days => p_days_ago), p_note) returning id into v_id;
  end if;
  return v_id;
end $$;

-- Yêu cầu chuyển khoản của học viên (PENDING / CONFIRMED / REJECTED).
create function pg_temp.demo_request(
  p_eid bigint, p_amount numeric, p_status text, p_days_ago int, p_reason text default null
) returns void language plpgsql as $$
declare
  v_code text;
  v_pay bigint;
  v_admin bigint := (select id from public.users where role = 'ADMIN' order by id limit 1);
begin
  if p_eid is null then return; end if;
  select 'MYA ' || student_id || ' ' || class_id into v_code from public.enrollments where id = p_eid;
  if exists (select 1 from public.payment_requests where enrollment_id = p_eid and status = p_status and amount = p_amount) then
    return;
  end if;
  if p_status = 'CONFIRMED' then
    v_pay := pg_temp.demo_pay(p_eid, p_amount, 'TRANSFER', p_days_ago - 1, 'Chuyển khoản: ' || v_code);
  end if;
  insert into public.payment_requests (enrollment_id, amount, transfer_code, status, reject_reason, payment_id,
                                       created_at, reviewed_at, reviewed_by)
  values (p_eid, p_amount, v_code, p_status, p_reason, v_pay,
          now() - make_interval(days => p_days_ago),
          case when p_status = 'PENDING' then null else now() - make_interval(days => greatest(p_days_ago - 1, 0)) end,
          case when p_status = 'PENDING' then null else v_admin end);
end $$;

create function pg_temp.demo_assignment(p_class bigint, p_teacher bigint, p_title text, p_desc text, p_due_days int)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  select id into v_id from public.assignments where class_id = p_class and title = p_title;
  if v_id is null then
    insert into public.assignments (class_id, teacher_id, title, description, due_date, created_at)
    values (p_class, p_teacher, p_title, p_desc,
            -- 23:59 giờ Việt Nam của ngày hạn nộp
            ((date_trunc('day', now() at time zone 'Asia/Ho_Chi_Minh') + make_interval(days => p_due_days)
              + interval '23 hours 59 minutes') at time zone 'Asia/Ho_Chi_Minh'),
            now() - interval '20 days')
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- Bài nộp (chèn thẳng, bỏ qua chặn hạn nộp, để có sẵn dữ liệu nộp muộn từ trước). p_submit_offset_hours: số giờ so với hạn nộp (âm = nộp sớm, dương = nộp muộn).
create function pg_temp.demo_submit(
  p_assignment bigint, p_student bigint, p_notes text, p_submit_offset_hours int,
  p_score numeric default null, p_feedback text default null
) returns void language plpgsql as $$
declare
  v_due timestamptz;
  v_at timestamptz;
begin
  if p_student is null then return; end if;
  if not exists (select 1 from public.enrollments e join public.assignments a on a.class_id = e.class_id
                 where a.id = p_assignment and e.student_id = p_student) then
    return;  -- học viên không có trong lớp (vd bị bỏ qua ghi danh)
  end if;
  select due_date into v_due from public.assignments where id = p_assignment;
  -- Giờ nộp không được ở tương lai.
  v_at := least(v_due + make_interval(hours => p_submit_offset_hours), now() - interval '1 hour');
  insert into public.submissions (assignment_id, student_id, notes, submitted_at, score, feedback, graded_at)
  values (p_assignment, p_student, p_notes, v_at, p_score, p_feedback,
          -- Chấm sau khi nộp và sau hạn 1 ngày, nhưng không quá hiện tại.
          case when p_score is null then null
               else least(greatest(v_at, v_due) + interval '1 day', now()) end)
  on conflict (assignment_id, student_id) do nothing;
end $$;

-- Điểm danh mọi buổi đã qua của lớp theo các thứ học (isodow: 1 = T2 ... 7 = CN).
-- Có mặt / Trễ / Vắng rải theo công thức cố định để mỗi học viên một kiểu.
create function pg_temp.demo_attendance(p_class bigint, p_days int[]) returns void language plpgsql as $$
declare
  v_start date;
  v_last date;
begin
  -- Chỉ các buổi đã diễn ra: từ ngày khai giảng tới hôm qua (hoặc ngày kết thúc nếu lớp đã xong).
  select start_date, least(coalesce(end_date, current_date - 1), current_date - 1)
  into v_start, v_last from public.classes where id = p_class;
  insert into public.attendances (enrollment_id, session_date, status, note)
  select e.id, d::date,
         case
           when (k + e.student_id * 3) % 11 = 0 then 'ABSENT'
           when (k + e.student_id) % 7 = 0 then 'LATE'
           else 'PRESENT'
         end,
         case
           when (k + e.student_id * 3) % 11 = 0 and k % 2 = 0 then 'Nghỉ có phép'
           when (k + e.student_id) % 7 = 0 then 'Đến muộn 10 phút'
         end
  from public.enrollments e
  cross join lateral (
    select d, row_number() over (order by d) as k
    from generate_series(v_start, v_last, interval '1 day') as d
    where extract(isodow from d) = any (p_days)
  ) s
  where e.class_id = p_class
  on conflict (enrollment_id, session_date) do nothing;
end $$;

-- ---------------------------------------------------------------------
-- Dữ liệu
-- ---------------------------------------------------------------------
do $$
declare
  -- giảng viên
  t_tuyen bigint; t_khoa bigint; t_trang bigint;
  -- học viên
  s_thao bigint; s_nam bigint; s_ha bigint; s_huy bigint; s_anh bigint;
  s_tung bigint; s_linh bigint; s_bao bigint; s_phuc bigint;
  -- khóa học
  k_ielts_f bigint; k_ielts_i bigint; k_toeic bigint; k_gt bigint; k_pa bigint; k_kid bigint;
  -- lớp
  c_ongoing bigint; c_open bigint; c_closed bigint; c_full bigint; c_noteacher bigint; c_khoa bigint;
  -- ghi danh
  e bigint;
  -- bài tập
  a1 bigint; a2 bigint; a3 bigint; a4 bigint; a5 bigint;
begin
  -- ===== Tài khoản =====
  t_tuyen := pg_temp.demo_user('anxua40@gmail.com', 'Nguyễn Kim Tuyền', 'TEACHER', '0912345601',
                               '1990-04-12', '25 Nguyễn Trãi, Thanh Xuân, Hà Nội');
  t_khoa  := pg_temp.demo_user('khoa.tran.demo@gmail.com', 'Trần Minh Khoa', 'TEACHER', '0912345602',
                               '1987-09-03', '12 Lê Lợi, Quận 1, TP.HCM');
  t_trang := pg_temp.demo_user('trang.le.demo@gmail.com', 'Lê Thu Trang', 'TEACHER', '0912345603',
                               '1995-01-20', '8 Trần Phú, Hải Châu, Đà Nẵng');

  s_thao := pg_temp.demo_user('nguyenthithao5002@gmail.com', 'Nguyễn Thị Thảo', 'STUDENT', '0987650001',
                              '2003-05-02', '102 Cầu Giấy, Hà Nội');
  s_nam  := pg_temp.demo_user('nam.le.demo@gmail.com', 'Lê Hoàng Nam', 'STUDENT', '0987650002',
                              '2002-11-15', '45 Kim Mã, Ba Đình, Hà Nội');
  s_ha   := pg_temp.demo_user('ha.pham.demo@gmail.com', 'Phạm Thu Hà', 'STUDENT', '0987650003',
                              '2004-02-28', '7 Lạch Tray, Ngô Quyền, Hải Phòng');
  s_huy  := pg_temp.demo_user('huy.do.demo@gmail.com', 'Đỗ Quang Huy', 'STUDENT', '0987650004',
                              '2001-07-09', '19 Hùng Vương, TP. Huế');
  s_anh  := pg_temp.demo_user('anh.vu.demo@gmail.com', 'Vũ Ngọc Ánh', 'STUDENT', '0987650005',
                              '2005-03-21', '66 Nguyễn Văn Cừ, Long Biên, Hà Nội');
  s_tung := pg_temp.demo_user('tung.bui.demo@gmail.com', 'Bùi Thanh Tùng', 'STUDENT', '0987650006',
                              '2000-12-01', '3 Phan Chu Trinh, Hoàn Kiếm, Hà Nội', p_must_change => true);
  s_linh := pg_temp.demo_user('linh.hoang.demo@gmail.com', 'Hoàng Mai Linh', 'STUDENT', '0987650007',
                              '2003-08-30', '90 Trần Hưng Đạo, Nam Định', p_active => false);
  s_bao  := pg_temp.demo_user('bao.ngo.demo@gmail.com', 'Ngô Gia Bảo', 'STUDENT', '0987650008',
                              '2006-06-06', '14 Lý Thường Kiệt, Hà Đông, Hà Nội');
  s_phuc := pg_temp.demo_user('phuc.dang.demo@gmail.com', 'Đặng Văn Phúc', 'STUDENT', null, null, null);

  -- ===== Khóa học =====
  k_ielts_f := pg_temp.demo_course('IELTS Foundation', 'Cơ bản', 12, 3500000, 'Nền tảng IELTS 4.5+');
  k_ielts_i := pg_temp.demo_course('IELTS Intensive', 'Nâng cao', 16, 6000000, 'Luyện thi IELTS 6.5+');
  k_toeic   := pg_temp.demo_course('TOEIC 600+', 'Trung cấp', 10, 3000000, 'Luyện thi TOEIC');
  k_gt      := pg_temp.demo_course('Giao tiếp cơ bản', 'Cơ bản', 8, 2000000, 'Tiếng Anh giao tiếp hằng ngày');
  k_pa      := pg_temp.demo_course('Luyện phát âm chuẩn', 'Mọi trình độ', 6, 1500000,
               'Sửa phát âm theo IPA, nối âm, ngữ điệu. Lớp nhỏ tối đa 3 học viên để luyện 1 kèm 1.');
  k_kid     := pg_temp.demo_course('Tiếng Anh thiếu nhi', 'Trẻ em 6-10 tuổi', 12, 2500000,
               'Học qua trò chơi, bài hát và hình ảnh. Giáo trình Cambridge Starters.');

  -- ===== Lớp học =====
  -- Cô Tuyền: đang dạy (có điểm danh, bài tập, học phí đủ kiểu)
  c_ongoing := pg_temp.demo_class('IELTS Intensive K07', k_ielts_i, t_tuyen,
               current_date - 28, current_date + 84, 'T2-T4-T6 18:00-19:30', 'P201', 15, 'ONGOING');
  -- Cô Tuyền: sắp khai giảng, đang nhận đăng ký
  c_open    := pg_temp.demo_class('TOEIC 600+ K12', k_toeic, t_tuyen,
               current_date + 10, current_date + 80, 'T3-T5 19:00-20:30', 'P305', 20, 'OPEN');
  -- Cô Tuyền: đã kết thúc
  c_closed  := pg_temp.demo_class('IELTS Foundation K04', k_ielts_f, t_tuyen,
               current_date - 120, current_date - 20, 'T7-CN 08:00-10:00', 'P102', 15, 'CLOSED');
  -- Cô Tuyền: đang mở nhưng đã đủ sĩ số (3/3) → nút "Lớp đã đầy"
  c_full    := pg_temp.demo_class('Luyện phát âm PA-K01', k_pa, t_tuyen,
               current_date + 5, current_date + 47, 'T7 14:00-16:00', 'P108', 3, 'OPEN');
  -- Chưa phân công giảng viên, chưa ai đăng ký → bạn tự đăng ký để demo luồng đóng tiền QR
  c_noteacher := pg_temp.demo_class('Tiếng Anh thiếu nhi KID-K02', k_kid, null,
               current_date + 14, current_date + 98, 'T7-CN 09:00-10:30', 'P110', 12, 'OPEN');
  -- Thầy Khoa: đang dạy
  c_khoa    := pg_temp.demo_class('Giao tiếp cơ bản GT-K11', k_gt, t_khoa,
               current_date - 21, current_date + 35, 'T3-T5 18:00-19:30', 'P203', 20, 'ONGOING');

  -- ===== Ghi danh + học phí =====
  -- Thảo (bạn): đang học, đã đóng 3tr/6tr, đang chờ xác nhận chuyển khoản 1tr → còn phải đóng 2tr
  e := pg_temp.demo_enroll(s_thao, c_ongoing, 30);
  perform pg_temp.demo_pay(e, 3000000, 'CASH', 25, 'Demo: đóng đợt 1 tại quầy');
  perform pg_temp.demo_request(e, 1000000, 'PENDING', 1);
  -- Thảo: lớp đã học xong, đóng đủ bằng chuyển khoản
  e := pg_temp.demo_enroll(s_thao, c_closed, 125);
  perform pg_temp.demo_pay(e, 3500000, 'TRANSFER', 118, 'Demo: đóng đủ học phí');

  -- Nam: học viên gương mẫu, đóng đủ mọi lớp
  e := pg_temp.demo_enroll(s_nam, c_ongoing, 32);
  perform pg_temp.demo_pay(e, 3000000, 'CASH', 27, 'Demo: đóng đợt 1');
  perform pg_temp.demo_pay(e, 3000000, 'TRANSFER', 5, 'Demo: đóng đợt 2');
  e := pg_temp.demo_enroll(s_nam, c_closed, 124);
  perform pg_temp.demo_pay(e, 3500000, 'CASH', 115, 'Demo: đóng đủ học phí');
  e := pg_temp.demo_enroll(s_nam, c_full, 3);
  perform pg_temp.demo_pay(e, 1500000, 'CARD', 2, 'Demo: quẹt thẻ');

  -- Hà: chưa đóng đồng nào; đã đăng ký lớp sắp mở (còn hủy được vì chưa đóng tiền)
  e := pg_temp.demo_enroll(s_ha, c_ongoing, 29);
  e := pg_temp.demo_enroll(s_ha, c_open, 2);

  -- Huy: đóng 1 phần, báo chuyển khoản nhưng bị từ chối
  e := pg_temp.demo_enroll(s_huy, c_ongoing, 31);
  perform pg_temp.demo_pay(e, 2000000, 'CASH', 20, 'Demo: đặt cọc');
  perform pg_temp.demo_request(e, 4000000, 'REJECTED', 4,
          'Chưa nhận được tiền, vui lòng kiểm tra lại nội dung chuyển khoản');
  e := pg_temp.demo_enroll(s_huy, c_open, 1);

  -- Ánh: chuyển khoản đã được xác nhận → đóng đủ; lớp phát âm chưa đóng
  e := pg_temp.demo_enroll(s_anh, c_ongoing, 30);
  perform pg_temp.demo_pay(e, 1000000, 'CASH', 26, 'Demo: đặt cọc');
  perform pg_temp.demo_request(e, 5000000, 'CONFIRMED', 6);
  e := pg_temp.demo_enroll(s_anh, c_full, 4);

  -- Tùng: học 3 lớp với 2 giảng viên, đóng lẻ tẻ
  e := pg_temp.demo_enroll(s_tung, c_ongoing, 33);
  perform pg_temp.demo_pay(e, 1500000, 'CASH', 24, 'Demo: đóng 1 phần');
  e := pg_temp.demo_enroll(s_tung, c_full, 5);
  perform pg_temp.demo_pay(e, 1500000, 'TRANSFER', 4, 'Demo: đóng đủ học phí');
  e := pg_temp.demo_enroll(s_tung, c_khoa, 25);
  perform pg_temp.demo_pay(e, 2000000, 'CASH', 21, 'Demo: đóng đủ học phí');

  -- Linh (bị khóa): lớp đã kết thúc mà vẫn còn nợ
  e := pg_temp.demo_enroll(s_linh, c_closed, 122);
  perform pg_temp.demo_pay(e, 1000000, 'CASH', 110, 'Demo: đặt cọc');

  -- Thầy Khoa: thêm học viên cho lớp giao tiếp
  e := pg_temp.demo_enroll(s_nam, c_khoa, 26);
  perform pg_temp.demo_pay(e, 2000000, 'TRANSFER', 22, 'Demo: đóng đủ học phí');
  e := pg_temp.demo_enroll(s_ha, c_khoa, 24);

  -- ===== Điểm danh =====
  perform pg_temp.demo_attendance(c_ongoing, array[1, 3, 5]);   -- T2-T4-T6
  perform pg_temp.demo_attendance(c_khoa, array[2, 4]);         -- T3-T5
  perform pg_temp.demo_attendance(c_closed, array[6, 7]);       -- T7-CN

  -- ===== Bài tập + bài nộp (lớp đang dạy của cô Tuyền) =====
  a1 := pg_temp.demo_assignment(c_ongoing, t_tuyen, 'Bài 1: Giới thiệu bản thân',
        'Viết đoạn văn 150 từ giới thiệu bản thân: tên, quê quán, sở thích, lý do học IELTS.', -14);
  a2 := pg_temp.demo_assignment(c_ongoing, t_tuyen, 'Bài 2: Writing Task 1 - Biểu đồ cột',
        'Mô tả biểu đồ cột về số lượng du khách (tối thiểu 150 từ). Nộp file Word hoặc ảnh chụp bài viết tay.', -3);
  a3 := pg_temp.demo_assignment(c_ongoing, t_tuyen, 'Bài 3: Speaking Part 2 - Thuyết trình 2 phút',
        'Chủ đề: Describe a place you would like to visit. Ghi âm hoặc ghi dàn ý vào phần ghi chú.', 5);
  a4 := pg_temp.demo_assignment(c_ongoing, t_tuyen, 'Bài 4: 50 từ vựng chủ đề Travel',
        'Chép 50 từ vựng kèm phiên âm và đặt câu cho 10 từ bất kỳ.', -2);

  -- Bài 1 (đã hết hạn 2 tuần): hầu hết đã chấm
  perform pg_temp.demo_submit(a1, s_thao, 'Em gửi bài giới thiệu bản thân ạ.', -24, 8.5,
          'Bài viết mạch lạc. Chú ý chia động từ ở thì quá khứ đơn.');
  perform pg_temp.demo_submit(a1, s_nam, 'Bài làm của em.', -48, 9.5, 'Rất tốt, từ vựng phong phú!');
  perform pg_temp.demo_submit(a1, s_ha, 'Em xin lỗi nộp muộn ạ.', 50, 6, 'Nộp muộn 2 ngày, nội dung còn sơ sài.');
  perform pg_temp.demo_submit(a1, s_huy, 'Bài của em ạ.', -5, 7, 'Khá, cần thêm từ nối.');
  perform pg_temp.demo_submit(a1, s_anh, 'Gửi cô bài 1.', -30, 8, 'Tốt.');
  -- Tùng: không nộp bài 1

  -- Bài 2 (vừa hết hạn 3 ngày): đã nộp, CHỜ CHẤM → giảng viên vào chấm để demo
  perform pg_temp.demo_submit(a2, s_thao, 'Bài Writing Task 1 của em.', -20);
  perform pg_temp.demo_submit(a2, s_nam, 'Em nộp bài ạ.', 30);         -- nộp muộn
  perform pg_temp.demo_submit(a2, s_anh, 'Bài làm Task 1.', -2);

  -- Bài 3 (còn 5 ngày): chỉ Nam nộp sớm → Thảo tự nộp để demo
  perform pg_temp.demo_submit(a3, s_nam, 'Dàn ý: Kyoto - đền chùa, ẩm thực, mùa lá đỏ.', -100);

  -- Bài 4 (quá hạn 2 ngày): KHÔNG ai nộp → Thảo thấy "Quá hạn" và không nộp được nữa

  -- Lớp thầy Khoa: 1 bài đã chấm
  a5 := pg_temp.demo_assignment(c_khoa, t_khoa, 'Bài 1: Hội thoại chào hỏi',
        'Viết đoạn hội thoại 8-10 câu giữa hai người lần đầu gặp nhau.', -7);
  perform pg_temp.demo_submit(a5, s_tung, 'Hội thoại của em.', -10, 9, 'Tự nhiên, đúng ngữ cảnh.');
  perform pg_temp.demo_submit(a5, s_nam, 'Bài làm.', -30, 10, 'Xuất sắc!');
  perform pg_temp.demo_submit(a5, s_ha, 'Bài làm của em.', 20);

  raise notice 'Đã tạo dữ liệu mẫu. Mật khẩu tài khoản demo mới: Demo@1234';
end $$;

commit;
