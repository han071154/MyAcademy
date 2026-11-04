-- =====================================================================
-- MyAcademy - Thiết lập Supabase (bản bảo mật: Supabase Auth + RLS)
--
-- Cài mới:      chạy database/schema.sql trước, rồi chạy file này.
-- Đã có dữ liệu: chỉ cần chạy file này. Tài khoản cũ được chuyển sang
--                Supabase Auth và GIỮ NGUYÊN mật khẩu (ai đang dùng 123456
--                sẽ bị bắt đổi mật khẩu ở lần đăng nhập tới).
-- Chạy lại nhiều lần vẫn an toàn.
-- =====================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- 1. Bảng bài tập / bài nộp
-- =====================================================================
create table if not exists assignments (
  id bigserial primary key,
  class_id bigint not null references classes(id) on delete cascade,
  teacher_id bigint references users(id),
  title text not null,
  description text,
  due_date timestamptz,
  attachment_url text,
  attachment_name text,
  created_at timestamptz not null default now()
);

create table if not exists submissions (
  id bigserial primary key,
  assignment_id bigint not null references assignments(id) on delete cascade,
  student_id bigint not null references users(id) on delete cascade,
  file_url text,
  file_name text,
  notes text,
  submitted_at timestamptz not null default now(),
  score numeric(5,2),
  feedback text,
  graded_at timestamptz,
  unique (assignment_id, student_id)
);

-- =====================================================================
-- 2. Liên kết users <-> auth.users (Supabase Auth)
-- =====================================================================
alter table users add column if not exists auth_id uuid unique references auth.users(id) on delete set null;
alter table users add column if not exists must_change_password boolean not null default false;

-- Tạo 1 tài khoản đăng nhập trong auth.users. Chỉ gọi được từ các hàm khác (không cấp cho app).
create or replace function _create_auth_user(p_email text, p_password text, p_hash text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          coalesce(p_hash, crypt(p_password, gen_salt('bf', 10))), now(),
          '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());
  return v_id;
end;
$$;

-- Chuyển tài khoản cũ (cột password_hash) sang Supabase Auth, sau đó xóa cột mật khẩu khỏi bảng users.
do $$
declare
  r record;
  v_uid uuid;
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'users' and column_name = 'password_hash') then
    for r in execute 'select id, email, password_hash from public.users where auth_id is null' loop
      select id into v_uid from auth.users where lower(email) = lower(trim(r.email));
      if v_uid is null then
        v_uid := _create_auth_user(r.email, null, r.password_hash);
      end if;
      update users
         set auth_id = v_uid,
             must_change_password = (r.password_hash = crypt('123456', r.password_hash))
       where id = r.id;
    end loop;
    alter table users drop column password_hash;
  end if;
end $$;

-- Tạo Admin mặc định nếu chưa có (bắt buộc đổi mật khẩu ở lần đăng nhập đầu).
do $$
declare
  v_uid uuid;
begin
  if not exists (select 1 from users where role = 'ADMIN') then
    select id into v_uid from auth.users where email = 'admin@center.com';
    if v_uid is null then
      v_uid := _create_auth_user('admin@center.com', '123456');
    end if;
    insert into users (email, full_name, role, auth_id, must_change_password)
    values ('admin@center.com', 'Quản trị viên', 'ADMIN', v_uid, true);
  end if;
end $$;

-- =====================================================================
-- 3. Hàm xác định người đang đăng nhập (dùng trong RLS)
-- =====================================================================
create or replace function app_uid() returns bigint
language sql stable security definer set search_path = public as $$
  select id from users where auth_id = auth.uid() and active
$$;

create or replace function app_role() returns text
language sql stable security definer set search_path = public as $$
  select role from users where auth_id = auth.uid() and active
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(app_role() = 'ADMIN', false)
$$;

create or replace function is_teacher_of(p_class_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from classes where id = p_class_id and teacher_id = app_uid())
$$;

create or replace function is_student_in(p_class_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from enrollments where class_id = p_class_id and student_id = app_uid())
$$;

create or replace function class_student_count(p_class_id bigint) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from enrollments where class_id = p_class_id
$$;

create or replace function assignment_submission_count(p_assignment_id bigint) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from submissions where assignment_id = p_assignment_id
$$;

-- =====================================================================
-- 4. Bật RLS + phân quyền theo vai trò
-- =====================================================================
alter table users        enable row level security;
alter table courses      enable row level security;
alter table classes      enable row level security;
alter table enrollments  enable row level security;
alter table attendances  enable row level security;
alter table payments     enable row level security;
alter table assignments  enable row level security;
alter table submissions  enable row level security;

-- Khách chưa đăng nhập (anon) không được đụng vào bất kỳ bảng nào.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- users: xem chính mình, admin xem tất cả, ai cũng thấy giảng viên,
-- giảng viên thấy học viên trong lớp mình. Ghi chỉ qua RPC.
drop policy if exists users_select on users;
create policy users_select on users for select to authenticated using (
  auth_id = auth.uid()
  or is_admin()
  or role = 'TEACHER'
  or exists (select 1 from enrollments e join classes c on c.id = e.class_id
             where e.student_id = users.id and c.teacher_id = app_uid())
);

-- courses / classes: ai đăng nhập cũng xem được, chỉ admin sửa.
drop policy if exists courses_select on courses;
drop policy if exists courses_admin on courses;
create policy courses_select on courses for select to authenticated using (true);
create policy courses_admin on courses for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists classes_select on classes;
drop policy if exists classes_admin on classes;
create policy classes_select on classes for select to authenticated using (true);
create policy classes_admin on classes for all to authenticated using (is_admin()) with check (is_admin());

-- enrollments: học viên thấy của mình, GV thấy lớp mình, admin tất cả. Ghi danh qua RPC.
drop policy if exists enrollments_select on enrollments;
drop policy if exists enrollments_admin_delete on enrollments;
create policy enrollments_select on enrollments for select to authenticated
  using (is_admin() or student_id = app_uid() or is_teacher_of(class_id));
create policy enrollments_admin_delete on enrollments for delete to authenticated using (is_admin());

-- attendances: xem theo lớp/của mình. Ghi qua RPC save_attendance.
drop policy if exists attendances_select on attendances;
create policy attendances_select on attendances for select to authenticated using (
  is_admin() or exists (select 1 from enrollments e
                        where e.id = attendances.enrollment_id
                          and (e.student_id = app_uid() or is_teacher_of(e.class_id)))
);

-- payments: học viên xem của mình, admin tất cả. Thu tiền qua RPC, chỉ admin xóa.
drop policy if exists payments_select on payments;
drop policy if exists payments_admin_delete on payments;
create policy payments_select on payments for select to authenticated using (
  is_admin() or exists (select 1 from enrollments e where e.id = payments.enrollment_id and e.student_id = app_uid())
);
create policy payments_admin_delete on payments for delete to authenticated using (is_admin());

-- assignments: thành viên lớp xem; GV của lớp / admin giao, sửa, xóa.
drop policy if exists assignments_select on assignments;
drop policy if exists assignments_write on assignments;
create policy assignments_select on assignments for select to authenticated
  using (is_admin() or is_teacher_of(class_id) or is_student_in(class_id));
create policy assignments_write on assignments for all to authenticated
  using (is_admin() or is_teacher_of(class_id))
  with check (is_admin() or (is_teacher_of(class_id) and teacher_id = app_uid()));

-- submissions: học viên nộp/sửa bài của mình; GV lớp và admin xem + chấm.
drop policy if exists submissions_select on submissions;
drop policy if exists submissions_insert on submissions;
drop policy if exists submissions_update on submissions;
create policy submissions_select on submissions for select to authenticated using (
  is_admin() or student_id = app_uid()
  or exists (select 1 from assignments a where a.id = submissions.assignment_id and is_teacher_of(a.class_id))
);
create policy submissions_insert on submissions for insert to authenticated with check (
  student_id = app_uid()
  and exists (select 1 from assignments a where a.id = submissions.assignment_id and is_student_in(a.class_id))
);
create policy submissions_update on submissions for update to authenticated using (
  is_admin() or student_id = app_uid()
  or exists (select 1 from assignments a where a.id = submissions.assignment_id and is_teacher_of(a.class_id))
);

-- Học viên không tự cho điểm được; GV không sửa được bài làm của học viên.
create or replace function submissions_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_class bigint;
begin
  if auth.uid() is null then return new; end if;  -- chạy tay trong SQL Editor
  select class_id into v_class from assignments where id = new.assignment_id;
  if is_admin() or is_teacher_of(v_class) then
    if tg_op = 'UPDATE' then
      new.assignment_id := old.assignment_id;
      new.student_id    := old.student_id;
      new.file_url      := old.file_url;
      new.file_name     := old.file_name;
      new.notes         := old.notes;
      new.submitted_at  := old.submitted_at;
    end if;
    if new.score is not null and (new.score < 0 or new.score > 10) then
      raise exception 'Điểm phải từ 0 đến 10';
    end if;
  elsif tg_op = 'INSERT' then
    new.score := null; new.feedback := null; new.graded_at := null;
  else
    new.assignment_id := old.assignment_id;
    new.student_id    := old.student_id;
    new.score         := old.score;
    new.feedback      := old.feedback;
    new.graded_at     := old.graded_at;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_submissions_guard on submissions;
create trigger trg_submissions_guard before insert or update on submissions
  for each row execute function submissions_guard();

-- =====================================================================
-- 5. Views (security_invoker = chạy theo quyền người xem, tôn trọng RLS)
-- =====================================================================
drop view if exists v_classes, v_enrollments, v_payments, v_debts, v_assignments, v_submissions;

create view v_classes with (security_invoker = true) as
select cl.id, cl.course_id, co.name as course_name, co.fee,
       cl.teacher_id, t.full_name as teacher_name,
       cl.name, cl.start_date, cl.end_date, cl.schedule, cl.room, cl.max_students, cl.status,
       class_student_count(cl.id) as enrolled
from classes cl
join courses co on co.id = cl.course_id
left join users t on t.id = cl.teacher_id;

create view v_enrollments with (security_invoker = true) as
select e.id as enrollment_id, e.class_id, e.student_id, u.full_name, u.phone, u.email
from enrollments e
join users u on u.id = e.student_id;

create view v_payments with (security_invoker = true) as
select p.id, p.enrollment_id, p.amount, p.paid_at, p.method, p.note,
       u.full_name as student_name, cl.name as class_name
from payments p
join enrollments e on e.id = p.enrollment_id
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id;

create view v_debts with (security_invoker = true) as
select e.id as enrollment_id, u.full_name as student_name, cl.name as class_name, co.fee,
       coalesce(sum(p.amount), 0) as paid,
       co.fee - coalesce(sum(p.amount), 0) as debt
from enrollments e
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
join courses co on co.id = cl.course_id
left join payments p on p.enrollment_id = e.id
group by e.id, u.full_name, cl.name, co.fee;

create view v_assignments with (security_invoker = true) as
select a.id, a.class_id, a.teacher_id, a.title, a.description, a.due_date, a.attachment_url, a.attachment_name, a.created_at,
       cl.name as class_name,
       assignment_submission_count(a.id) as submission_count,
       class_student_count(a.class_id) as total_students
from assignments a
join classes cl on cl.id = a.class_id;

create view v_submissions with (security_invoker = true) as
select s.id, s.assignment_id, s.student_id, s.file_url, s.file_name, s.notes, s.submitted_at,
       s.score, s.feedback, s.graded_at,
       u.full_name as student_name, u.email as student_email
from submissions s
join users u on u.id = s.student_id;

revoke all on v_classes, v_enrollments, v_payments, v_debts, v_assignments, v_submissions from anon;
grant select on v_classes, v_enrollments, v_payments, v_debts, v_assignments, v_submissions to authenticated;

-- =====================================================================
-- 6. Hàm RPC (đều tự kiểm tra quyền, không tin tham số role/user_id từ app)
-- =====================================================================
-- Bỏ các hàm cũ nhận user_id/role/mật khẩu từ client.
drop function if exists login(text, text);
drop function if exists change_password(bigint, text, text);
drop function if exists get_my_classes(bigint, text);
drop function if exists enroll_student(bigint, bigint, text);
drop function if exists cancel_my_enrollment(bigint, bigint);
drop function if exists get_student_attendance(bigint, bigint);
drop function if exists create_user(text, text, text, text, text, date, text);
drop function if exists update_user(bigint, text, text, text, date, text, boolean, text);

create or replace function _require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Bạn không có quyền thực hiện thao tác này'; end if;
end;
$$;

-- Đánh dấu đã đổi mật khẩu (gọi sau khi app đổi mật khẩu qua Supabase Auth).
create or replace function password_changed() returns json
language sql security definer set search_path = public as $$
  update users set must_change_password = false where auth_id = auth.uid();
  select json_build_object('ok', true);
$$;

-- Admin tạo tài khoản: bắt buộc nhập mật khẩu khởi tạo, người dùng phải đổi khi đăng nhập lần đầu.
create or replace function create_user(
  p_email text, p_full_name text, p_role text, p_password text,
  p_phone text default null, p_dob date default null, p_address text default null
) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid;
  v_new users%rowtype;
begin
  perform _require_admin();
  if p_role not in ('TEACHER', 'STUDENT') then raise exception 'Vai trò không hợp lệ'; end if;
  if coalesce(trim(p_email), '') = '' or coalesce(trim(p_full_name), '') = '' then
    raise exception 'Vui lòng nhập email và họ tên';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Mật khẩu khởi tạo tối thiểu 8 ký tự';
  end if;
  if exists (select 1 from users where lower(email) = lower(trim(p_email)))
     or exists (select 1 from auth.users where lower(email) = lower(trim(p_email))) then
    raise exception 'Email đã được sử dụng';
  end if;

  v_uid := _create_auth_user(p_email, p_password);
  insert into users (email, full_name, role, phone, dob, address, auth_id, must_change_password)
  values (lower(trim(p_email)), trim(p_full_name), p_role, p_phone, p_dob, p_address, v_uid, true)
  returning * into v_new;

  return json_build_object('id', v_new.id, 'email', v_new.email, 'full_name', v_new.full_name,
    'role', v_new.role, 'phone', v_new.phone, 'dob', v_new.dob, 'address', v_new.address, 'active', v_new.active);
end;
$$;

-- Admin sửa tài khoản / khóa tài khoản / đặt lại mật khẩu.
create or replace function update_user(
  p_id bigint, p_email text, p_full_name text,
  p_phone text default null, p_dob date default null, p_address text default null,
  p_active boolean default true, p_password text default null
) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_u users%rowtype;
  v_email text := lower(trim(p_email));
  v_reset boolean := p_password is not null and length(trim(p_password)) > 0;
begin
  perform _require_admin();
  select * into v_u from users where id = p_id;
  if not found then raise exception 'Không tìm thấy người dùng'; end if;
  if p_id = app_uid() and not coalesce(p_active, true) then
    raise exception 'Không thể tự khóa tài khoản của mình';
  end if;
  if v_reset and length(trim(p_password)) < 8 then
    raise exception 'Mật khẩu mới tối thiểu 8 ký tự';
  end if;
  if exists (select 1 from users where lower(email) = v_email and id <> p_id)
     or exists (select 1 from auth.users where lower(email) = v_email and id is distinct from v_u.auth_id) then
    raise exception 'Email đã được sử dụng';
  end if;

  update users set
    email = v_email,
    full_name = trim(p_full_name),
    phone = p_phone, dob = p_dob, address = p_address,
    active = coalesce(p_active, true),
    must_change_password = must_change_password or v_reset
  where id = p_id
  returning * into v_u;

  if v_u.auth_id is not null then
    update auth.users set
      email = v_email,
      encrypted_password = case when v_reset then crypt(trim(p_password), gen_salt('bf', 10)) else encrypted_password end,
      banned_until = case when v_u.active then null else 'infinity'::timestamptz end,
      updated_at = now()
    where id = v_u.auth_id;
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', v_email)
    where user_id = v_u.auth_id and provider = 'email';
  end if;

  return json_build_object('id', v_u.id, 'email', v_u.email, 'full_name', v_u.full_name,
    'role', v_u.role, 'phone', v_u.phone, 'dob', v_u.dob, 'address', v_u.address, 'active', v_u.active);
end;
$$;

-- Admin xóa tài khoản (xóa luôn tài khoản đăng nhập).
create or replace function delete_user(p_id bigint) returns json
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_auth uuid;
begin
  perform _require_admin();
  if p_id = app_uid() then raise exception 'Không thể xóa chính mình'; end if;
  delete from users where id = p_id returning auth_id into v_auth;
  if v_auth is not null then delete from auth.users where id = v_auth; end if;
  return json_build_object('ok', true);
exception when foreign_key_violation then
  raise exception 'Người dùng đã có lớp học / học phí, hãy khóa tài khoản thay vì xóa';
end;
$$;

-- Lớp của tôi (theo người đang đăng nhập).
create or replace function get_my_classes() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  r json;
  v_uid bigint := app_uid();
  v_role text := app_role();
begin
  if v_role = 'TEACHER' then
    select json_agg(x) into r from (
      select * from v_classes where teacher_id = v_uid order by start_date desc nulls last
    ) x;
  elsif v_role = 'STUDENT' then
    select json_agg(x) into r from (
      select cl.*,
             (select coalesce(sum(p.amount), 0)
              from payments p join enrollments e on e.id = p.enrollment_id
              where e.class_id = cl.id and e.student_id = v_uid) as paid
      from v_classes cl
      where cl.id in (select class_id from enrollments where student_id = v_uid)
      order by cl.start_date desc nulls last
    ) x;
  elsif v_role = 'ADMIN' then
    select json_agg(x) into r from (select * from v_classes order by id desc) x;
  end if;
  return coalesce(r, '[]'::json);
end;
$$;

-- Ghi danh: học viên tự đăng ký cho mình, admin ghi danh hộ. Giảng viên không được.
create or replace function enroll_student(p_class_id bigint, p_student_id bigint default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_role text := app_role();
  v_sid bigint;
  v_class classes%rowtype;
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

  select * into v_class from classes where id = p_class_id for update;
  if not found then raise exception 'Không tìm thấy lớp học'; end if;
  if v_role = 'STUDENT' and v_class.status != 'OPEN' then
    raise exception 'Lớp không còn nhận đăng ký';
  end if;
  if exists (select 1 from enrollments where class_id = p_class_id and student_id = v_sid) then
    if v_role = 'STUDENT' then raise exception 'Bạn đã đăng ký lớp này';
    else raise exception 'Học viên đã có trong lớp này'; end if;
  end if;
  if class_student_count(p_class_id) >= v_class.max_students then
    raise exception 'Lớp đã đủ học viên';
  end if;

  insert into enrollments (student_id, class_id) values (v_sid, p_class_id) returning * into v_new;
  return json_build_object('id', v_new.id, 'student_id', v_new.student_id, 'class_id', v_new.class_id);
end;
$$;

-- Học viên tự hủy đăng ký.
create or replace function cancel_my_enrollment(p_class_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_eid bigint;
  v_status text;
  v_paid boolean;
  v_attended boolean;
begin
  select e.id, cl.status,
         exists (select 1 from payments p where p.enrollment_id = e.id),
         exists (select 1 from attendances a where a.enrollment_id = e.id)
  into v_eid, v_status, v_paid, v_attended
  from enrollments e join classes cl on cl.id = e.class_id
  where e.class_id = p_class_id and e.student_id = app_uid();

  if v_eid is null then raise exception 'Bạn chưa đăng ký lớp này'; end if;
  if v_status != 'OPEN' then raise exception 'Lớp đã bắt đầu, vui lòng liên hệ trung tâm để hủy'; end if;
  if v_paid or v_attended then
    raise exception 'Bạn đã đóng học phí hoặc đã đi học, vui lòng liên hệ trung tâm để hủy';
  end if;
  delete from enrollments where id = v_eid;
  return json_build_object('ok', true);
end;
$$;

-- Điểm danh theo ngày (GV của lớp / admin).
create or replace function get_attendance(p_class_id bigint, p_date date) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  r json;
begin
  if not (is_admin() or is_teacher_of(p_class_id)) then
    raise exception 'Bạn không có quyền xem điểm danh lớp này';
  end if;
  select json_agg(x) into r from (
    select e.id as enrollment_id, u.full_name, a.status, a.note
    from enrollments e
    join users u on u.id = e.student_id
    left join attendances a on a.enrollment_id = e.id and a.session_date = p_date
    where e.class_id = p_class_id
    order by u.full_name
  ) x;
  return coalesce(r, '[]'::json);
end;
$$;

create or replace function save_attendance(p_class_id bigint, p_date date, p_records json) returns json
language plpgsql security definer set search_path = public as $$
declare
  r json;
begin
  if not (is_admin() or is_teacher_of(p_class_id)) then
    raise exception 'Bạn không có quyền điểm danh lớp này';
  end if;
  for r in select * from json_array_elements(p_records) loop
    insert into attendances (enrollment_id, session_date, status, note)
    select e.id, p_date, (r->>'status')::text, (r->>'note')::text
    from enrollments e
    where e.id = (r->>'enrollment_id')::bigint and e.class_id = p_class_id
    on conflict (enrollment_id, session_date) do update
    set status = excluded.status, note = excluded.note;
  end loop;
  return json_build_object('saved', json_array_length(p_records));
end;
$$;

-- Lịch sử điểm danh của chính học viên đang đăng nhập.
create or replace function get_student_attendance(p_class_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  r json;
begin
  select json_agg(x) into r from (
    select a.id, a.session_date, a.status, a.note
    from attendances a
    join enrollments e on e.id = a.enrollment_id
    where e.class_id = p_class_id and e.student_id = app_uid()
    order by a.session_date desc
  ) x;
  return coalesce(r, '[]'::json);
end;
$$;

-- Thu học phí (admin).
create or replace function create_payment(p_enrollment_id bigint, p_amount numeric, p_method text default 'CASH', p_note text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_debt numeric;
  v_new payments%rowtype;
begin
  perform _require_admin();
  if p_amount <= 0 then raise exception 'Số tiền phải lớn hơn 0'; end if;
  select co.fee - coalesce((select sum(amount) from payments where enrollment_id = e.id), 0)
  into v_debt
  from enrollments e
  join classes cl on cl.id = e.class_id
  join courses co on co.id = cl.course_id
  where e.id = p_enrollment_id;

  if v_debt is null then raise exception 'Không tìm thấy thông tin ghi danh'; end if;
  if p_amount > v_debt then raise exception 'Số tiền vượt quá công nợ còn lại'; end if;

  insert into payments (enrollment_id, amount, method, note)
  values (p_enrollment_id, p_amount, coalesce(p_method, 'CASH'), p_note)
  returning * into v_new;
  return json_build_object('id', v_new.id, 'amount', v_new.amount);
end;
$$;

-- Báo cáo tổng quan (admin).
create or replace function reports_summary() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  m json;
  v_revenue numeric := (select coalesce(sum(amount), 0) from payments);
begin
  perform _require_admin();
  select json_agg(x) into m from (
    select to_char(s.m, 'MM/YYYY') as month, coalesce(sum(p.amount), 0) as total
    from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') as s(m)
    left join payments p on date_trunc('month', p.paid_at) = s.m
    group by s.m
    order by s.m desc
  ) x;

  return json_build_object(
    'students', (select count(*) from users where role = 'STUDENT' and active),
    'teachers', (select count(*) from users where role = 'TEACHER' and active),
    'courses', (select count(*) from courses),
    'active_classes', (select count(*) from classes where status in ('OPEN', 'ONGOING')),
    'total_revenue', v_revenue,
    'month_revenue', (select coalesce(sum(amount), 0) from payments
                      where date_trunc('month', paid_at) = date_trunc('month', now())),
    'total_debt', (select coalesce(sum(co.fee), 0) from enrollments e
                   join classes cl on cl.id = e.class_id join courses co on co.id = cl.course_id) - v_revenue,
    'monthly', coalesce(m, '[]'::json)
  );
end;
$$;

-- Quyền gọi hàm: chỉ người đã đăng nhập; hàm nội bộ thì không ai gọi trực tiếp được.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function _create_auth_user(text, text, text) from authenticated;
revoke execute on function submissions_guard() from authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;

-- =====================================================================
-- 7. Storage: bucket private, đọc file qua signed URL
--    Tệp lưu tại "<auth uid>/<tên file>", trong DB ghi "storage:<đường dẫn>".
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('submissions', 'submissions', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

-- Chuyển link public cũ sang dạng đường dẫn nội bộ.
update assignments set attachment_url = regexp_replace(attachment_url, '^https?://[^/]+/storage/v1/object/public/submissions/', 'storage:')
where attachment_url ~ '^https?://[^/]+/storage/v1/object/public/submissions/';
update submissions set file_url = regexp_replace(file_url, '^https?://[^/]+/storage/v1/object/public/submissions/', 'storage:')
where file_url ~ '^https?://[^/]+/storage/v1/object/public/submissions/';

drop policy if exists myacademy_upload on storage.objects;
drop policy if exists myacademy_read on storage.objects;

-- Chỉ upload vào thư mục của chính mình.
create policy myacademy_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'submissions'
  and public.app_uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Chỉ đọc được tệp của mình, hoặc tệp gắn với bài tập / bài nộp mà mình được phép xem (theo RLS ở trên).
create policy myacademy_read on storage.objects for select to authenticated using (
  bucket_id = 'submissions'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.assignments a where a.attachment_url = 'storage:' || name)
    or exists (select 1 from public.submissions s where s.file_url = 'storage:' || name)
  )
);

-- =====================================================================
-- 8. Khóa học mẫu
-- =====================================================================
insert into courses(name, level, duration_weeks, fee, description)
select 'IELTS Foundation', 'Cơ bản', 12, 3500000, 'Nền tảng IELTS 4.5+'
where not exists (select 1 from courses where name = 'IELTS Foundation');
insert into courses(name, level, duration_weeks, fee, description)
select 'IELTS Intensive', 'Nâng cao', 16, 6000000, 'Luyện thi IELTS 6.5+'
where not exists (select 1 from courses where name = 'IELTS Intensive');
insert into courses(name, level, duration_weeks, fee, description)
select 'TOEIC 600+', 'Trung cấp', 10, 3000000, 'Luyện thi TOEIC'
where not exists (select 1 from courses where name = 'TOEIC 600+');
insert into courses(name, level, duration_weeks, fee, description)
select 'Giao tiếp cơ bản', 'Cơ bản', 8, 2000000, 'Tiếng Anh giao tiếp hằng ngày'
where not exists (select 1 from courses where name = 'Giao tiếp cơ bản');

commit;
