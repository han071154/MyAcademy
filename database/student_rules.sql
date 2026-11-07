-- =====================================================================
-- MyAcademy - Sửa quy tắc phía học viên
--   1. Bài đã chấm điểm thì không nộp lại được.
--   2. Giờ nộp / giờ chấm do server ghi (không tin giờ trên điện thoại).
--      Đã qua hạn nộp thì học viên KHÔNG nộp / nộp lại được nữa.
--      (Cột is_late vẫn giữ để nhận ra các bài nộp muộn trong dữ liệu cũ.)
--   3. Mỗi khóa học chỉ đăng ký 1 lớp đang mở / đang học.
--   4. Trạng thái lớp tự đổi theo ngày: tới ngày khai giảng → Đang học,
--      qua ngày kết thúc → Đã kết thúc. Lớp đã khai giảng thì không đăng ký / tự hủy được.
--
-- Chạy SAU database/supabase_setup.sql (chạy lại file kia thì chạy lại file này).
-- Chạy lại nhiều lần vẫn an toàn.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 4. Tự cập nhật trạng thái lớp theo ngày khai giảng / kết thúc.
--    Chỉ chuyển "tiến lên" (Mở → Đang học → Kết thúc), không mở lại lớp admin đã đóng.
--    Được gọi khi app tải danh sách lớp, khi đăng ký / hủy lớp, và chạy tự động mỗi đêm (nếu có pg_cron).
-- ---------------------------------------------------------------------
create or replace function sync_class_status() returns int
language plpgsql security definer set search_path = public as $$
declare
  n1 int;
  n2 int;
begin
  update classes set status = 'CLOSED'
  where status in ('OPEN', 'ONGOING') and end_date is not null and end_date < current_date;
  get diagnostics n1 = row_count;
  update classes set status = 'ONGOING'
  where status = 'OPEN' and start_date is not null and start_date <= current_date;
  get diagnostics n2 = row_count;
  return n1 + n2;
end;
$$;
revoke execute on function sync_class_status() from public, anon;
grant execute on function sync_class_status() to authenticated;

-- Học viên tự hủy đăng ký: chỉ khi lớp chưa khai giảng, chưa đóng tiền, chưa đi học.
create or replace function cancel_my_enrollment(p_class_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_eid bigint;
  v_status text;
  v_start date;
  v_paid boolean;
  v_attended boolean;
begin
  perform sync_class_status();
  select e.id, cl.status, cl.start_date,
         exists (select 1 from payments p where p.enrollment_id = e.id),
         exists (select 1 from attendances a where a.enrollment_id = e.id)
  into v_eid, v_status, v_start, v_paid, v_attended
  from enrollments e join classes cl on cl.id = e.class_id
  where e.class_id = p_class_id and e.student_id = app_uid();

  if v_eid is null then raise exception 'Bạn chưa đăng ký lớp này'; end if;
  if v_status != 'OPEN' or (v_start is not null and v_start <= current_date) then
    raise exception 'Lớp đã bắt đầu, vui lòng liên hệ trung tâm để hủy';
  end if;
  if v_paid or v_attended then
    raise exception 'Bạn đã đóng học phí hoặc đã đi học, vui lòng liên hệ trung tâm để hủy';
  end if;
  -- Bảng payment_requests có thể chưa tạo (chưa chạy payment_requests.sql) nên kiểm tra động.
  if to_regclass('public.payment_requests') is not null then
    execute 'select exists (select 1 from payment_requests where enrollment_id = $1 and status = ''PENDING'')'
      into v_paid using v_eid;
    if v_paid then
      raise exception 'Bạn có khoản chuyển khoản đang chờ xác nhận, vui lòng liên hệ trung tâm để hủy';
    end if;
  end if;
  delete from enrollments where id = v_eid;
  return json_build_object('ok', true);
end;
$$;
revoke execute on function cancel_my_enrollment(bigint) from public, anon;
grant execute on function cancel_my_enrollment(bigint) to authenticated;

-- Chạy tự động lúc 00:05 mỗi ngày nếu project đã bật extension pg_cron (không có thì bỏ qua).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'myacademy_sync_class_status';
    perform cron.schedule('myacademy_sync_class_status', '5 0 * * *', 'select public.sync_class_status()');
  end if;
exception when others then
  raise notice 'Không đặt được lịch pg_cron (%), app vẫn tự cập nhật khi mở danh sách lớp', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- 1 + 2. Bảo vệ bài nộp
-- ---------------------------------------------------------------------
create or replace function submissions_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_class bigint;
  v_due timestamptz;
begin
  if auth.uid() is null then return new; end if;  -- chạy tay trong SQL Editor
  select class_id, due_date into v_class, v_due from assignments where id = new.assignment_id;

  -- Học viên: đã qua hạn nộp thì không nộp / nộp lại được nữa (giờ tính theo server).
  if not (is_admin() or is_teacher_of(v_class)) and v_due is not null and now() > v_due then
    raise exception 'Đã hết hạn nộp bài (hạn: %), không thể nộp hoặc nộp lại',
      to_char(v_due at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY');
  end if;

  if is_admin() or is_teacher_of(v_class) then
    -- Giảng viên / admin: chỉ được chấm điểm, không sửa bài làm của học viên.
    if tg_op = 'UPDATE' then
      new.assignment_id := old.assignment_id;
      new.student_id    := old.student_id;
      new.file_url      := old.file_url;
      new.file_name     := old.file_name;
      new.notes         := old.notes;
      new.submitted_at  := old.submitted_at;
      if new.score is distinct from old.score or new.feedback is distinct from old.feedback then
        new.graded_at := now();
      else
        new.graded_at := old.graded_at;
      end if;
    end if;
    if new.score is not null and (new.score < 0 or new.score > 10) then
      raise exception 'Điểm phải từ 0 đến 10';
    end if;

  elsif tg_op = 'INSERT' then
    -- Học viên nộp lần đầu.
    new.score := null; new.feedback := null; new.graded_at := null;
    new.submitted_at := now();

  else
    -- Học viên nộp lại.
    if old.score is not null then
      raise exception 'Bài đã được chấm điểm, không thể nộp lại';
    end if;
    new.assignment_id := old.assignment_id;
    new.student_id    := old.student_id;
    new.score         := old.score;
    new.feedback      := old.feedback;
    new.graded_at     := old.graded_at;
    new.submitted_at  := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_submissions_guard on submissions;
create trigger trg_submissions_guard before insert or update on submissions
  for each row execute function submissions_guard();

-- Thêm cột is_late (nộp sau hạn) vào view bài nộp cho giảng viên.
drop view if exists v_submissions;
create view v_submissions with (security_invoker = true) as
select s.id, s.assignment_id, s.student_id, s.file_url, s.file_name, s.notes, s.submitted_at,
       s.score, s.feedback, s.graded_at,
       u.full_name as student_name, u.email as student_email,
       (a.due_date is not null and s.submitted_at > a.due_date) as is_late
from submissions s
join users u on u.id = s.student_id
join assignments a on a.id = s.assignment_id;

revoke all on v_submissions from anon;
grant select on v_submissions to authenticated;

-- ---------------------------------------------------------------------
-- 3. Ghi danh: chặn đăng ký 2 lớp (chưa kết thúc) của cùng 1 khóa học
-- ---------------------------------------------------------------------
create or replace function enroll_student(p_class_id bigint, p_student_id bigint default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_role text := app_role();
  v_sid bigint;
  v_class classes%rowtype;
  v_other text;
  v_new enrollments%rowtype;
begin
  if v_role = 'STUDENT' then
    v_sid := app_uid();
  elsif v_role = 'ADMIN' then
    v_sid := p_student_id;
    if not exists (select 1 from users where id = v_sid and role = 'STUDENT') then
      raise exception 'Học viên không hợp lệ';
    end if;
  else
    raise exception 'Bạn không có quyền thực hiện thao tác này';
  end if;

  perform sync_class_status();
  select * into v_class from classes where id = p_class_id for update;
  if not found then raise exception 'Không tìm thấy lớp học'; end if;
  if v_role = 'STUDENT' and v_class.status != 'OPEN' then
    raise exception 'Lớp không còn nhận đăng ký';
  end if;
  if v_role = 'STUDENT' and v_class.start_date is not null and v_class.start_date <= current_date then
    raise exception 'Lớp đã khai giảng nên không nhận đăng ký thêm, vui lòng liên hệ trung tâm';
  end if;
  if exists (select 1 from enrollments where class_id = p_class_id and student_id = v_sid) then
    if v_role = 'STUDENT' then raise exception 'Bạn đã đăng ký lớp này';
    else raise exception 'Học viên đã có trong lớp này'; end if;
  end if;

  -- Đã có lớp khác (đang mở / đang học) của cùng khóa → không cho đăng ký thêm.
  -- Lớp cũ đã kết thúc (CLOSED) thì vẫn được học lại.
  select cl.name into v_other
  from enrollments e join classes cl on cl.id = e.class_id
  where e.student_id = v_sid and cl.course_id = v_class.course_id and cl.status != 'CLOSED'
  limit 1;
  if v_other is not null then
    if v_role = 'STUDENT' then
      raise exception 'Bạn đã đăng ký lớp "%" của khóa học này. Muốn đổi lớp, hãy hủy lớp cũ trước', v_other;
    else
      raise exception 'Học viên đã có lớp "%" của khóa học này', v_other;
    end if;
  end if;

  if class_student_count(p_class_id) >= v_class.max_students then
    raise exception 'Lớp đã đủ học viên';
  end if;

  insert into enrollments (student_id, class_id) values (v_sid, p_class_id) returning * into v_new;
  return json_build_object('id', v_new.id, 'student_id', v_new.student_id, 'class_id', v_new.class_id);
end;
$$;

revoke execute on function enroll_student(bigint, bigint) from public, anon;
grant execute on function enroll_student(bigint, bigint) to authenticated;
revoke execute on function submissions_guard() from public, anon, authenticated;

commit;
