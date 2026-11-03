-- =====================================================================
-- MyAcademy - Thiết lập Supabase kết nối trực tiếp (Direct Supabase)
-- Chạy toàn bộ file này trong Supabase -> SQL Editor -> Run
-- =====================================================================

-- 1. Bật extension pgcrypto để mã hóa và kiểm tra mật khẩu
create extension if not exists pgcrypto;

-- 2. Tắt RLS để client Flutter (dùng publishableKey/anonKey) truy cập trực tiếp
alter table users disable row level security;
alter table courses disable row level security;
alter table classes disable row level security;
alter table enrollments disable row level security;
alter table attendances disable row level security;
alter table payments disable row level security;

-- 3. Tạo tài khoản Admin mặc định (mật khẩu: 123456)
insert into users (email, password_hash, full_name, role)
values ('admin@center.com', crypt('123456', gen_salt('bf')), 'Quản trị viên', 'ADMIN')
on conflict (email) do nothing;

-- 4. Thêm các khóa học mẫu nếu bảng courses còn trống
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

-- 5. Views cho danh sách lớp học
create or replace view v_classes as
select cl.id, cl.course_id, co.name as course_name, co.fee,
       cl.teacher_id, t.full_name as teacher_name,
       cl.name, cl.start_date, cl.end_date, cl.schedule, cl.room, cl.max_students, cl.status,
       (select count(*) from enrollments e where e.class_id = cl.id)::int as enrolled
from classes cl
join courses co on co.id = cl.course_id
left join users t on t.id = cl.teacher_id;

-- 6. View cho danh sách học viên trong lớp
create or replace view v_enrollments as
select e.id as enrollment_id, e.class_id, e.student_id, u.full_name, u.phone, u.email
from enrollments e
join users u on u.id = e.student_id;

-- 7. View cho lịch sử thanh toán học phí
create or replace view v_payments as
select p.id, p.enrollment_id, p.amount, p.paid_at, p.method, p.note,
       u.full_name as student_name, cl.name as class_name
from payments p
join enrollments e on e.id = p.enrollment_id
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id;

-- 8. View cho công nợ học phí
create or replace view v_debts as
select e.id as enrollment_id, u.full_name as student_name, cl.name as class_name, co.fee,
       coalesce(sum(p.amount), 0) as paid,
       co.fee - coalesce(sum(p.amount), 0) as debt
from enrollments e
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id
join courses co on co.id = cl.course_id
left join payments p on p.enrollment_id = e.id
group by e.id, u.full_name, cl.name, co.fee;

-- 9. Hàm Đăng nhập
create or replace function login(p_email text, p_password text)
returns json as $$
declare
  u users%rowtype;
begin
  select * into u from users where lower(email) = lower(trim(p_email));
  if not found or not u.active or u.password_hash != crypt(p_password, u.password_hash) then
    raise exception 'Sai email hoặc mật khẩu';
  end if;
  return json_build_object(
    'token', 'supabase-token-' || u.id,
    'user', json_build_object(
      'id', u.id,
      'email', u.email,
      'full_name', u.full_name,
      'role', u.role
    )
  );
end;
$$ language plpgsql security definer;

-- 10. Hàm Đổi mật khẩu
create or replace function change_password(p_user_id bigint, p_old_password text, p_new_password text)
returns json as $$
declare
  u users%rowtype;
begin
  select * into u from users where id = p_user_id;
  if not found or u.password_hash != crypt(p_old_password, u.password_hash) then
    raise exception 'Mật khẩu cũ không đúng';
  end if;
  if length(p_new_password) < 6 then
    raise exception 'Mật khẩu mới tối thiểu 6 ký tự';
  end if;
  update users set password_hash = crypt(p_new_password, gen_salt('bf')) where id = p_user_id;
  return json_build_object('ok', true);
end;
$$ language plpgsql security definer;

-- 11. Hàm Thêm người dùng (học viên / giáo viên)
create or replace function create_user(
  p_email text,
  p_full_name text,
  p_role text,
  p_password text default null,
  p_phone text default null,
  p_dob date default null,
  p_address text default null
) returns json as $$
declare
  v_pass text := coalesce(nullif(trim(p_password), ''), '123456');
  v_new users%rowtype;
begin
  insert into users(email, password_hash, full_name, role, phone, dob, address)
  values(trim(p_email), crypt(v_pass, gen_salt('bf')), trim(p_full_name), p_role, p_phone, p_dob, p_address)
  returning * into v_new;

  return json_build_object(
    'id', v_new.id,
    'email', v_new.email,
    'full_name', v_new.full_name,
    'role', v_new.role,
    'phone', v_new.phone,
    'dob', v_new.dob,
    'address', v_new.address,
    'active', v_new.active
  );
end;
$$ language plpgsql security definer;

-- 12. Hàm Sửa người dùng
create or replace function update_user(
  p_id bigint,
  p_email text,
  p_full_name text,
  p_phone text default null,
  p_dob date default null,
  p_address text default null,
  p_active boolean default true,
  p_password text default null
) returns json as $$
declare
  v_u users%rowtype;
begin
  update users set
    email = trim(p_email),
    full_name = trim(p_full_name),
    phone = p_phone,
    dob = p_dob,
    address = p_address,
    active = coalesce(p_active, true),
    password_hash = case when p_password is not null and length(trim(p_password)) > 0
                         then crypt(trim(p_password), gen_salt('bf'))
                         else password_hash end
  where id = p_id
  returning * into v_u;

  return json_build_object(
    'id', v_u.id,
    'email', v_u.email,
    'full_name', v_u.full_name,
    'role', v_u.role,
    'phone', v_u.phone,
    'dob', v_u.dob,
    'address', v_u.address,
    'active', v_u.active
  );
end;
$$ language plpgsql security definer;

-- 13. Hàm Lấy lớp của tôi (Giáo viên / Học viên / Admin)
create or replace function get_my_classes(p_user_id bigint, p_role text)
returns json as $$
declare
  r json;
begin
  if p_role = 'TEACHER' then
    select json_agg(x) into r from (
      select * from v_classes where teacher_id = p_user_id order by start_date desc nulls last
    ) x;
  elsif p_role = 'STUDENT' then
    select json_agg(x) into r from (
      select cl.*,
             (select coalesce(sum(p.amount), 0)
              from payments p join enrollments e on e.id = p.enrollment_id
              where e.class_id = cl.id and e.student_id = p_user_id) as paid
      from v_classes cl
      where cl.id in (select class_id from enrollments where student_id = p_user_id)
      order by cl.start_date desc nulls last
    ) x;
  else
    select json_agg(x) into r from (
      select * from v_classes order by id desc
    ) x;
  end if;

  return coalesce(r, '[]'::json);
end;
$$ language plpgsql security definer;

-- 14. Hàm Ghi danh học viên vào lớp
create or replace function enroll_student(p_class_id bigint, p_student_id bigint, p_role text default 'STUDENT')
returns json as $$
declare
  v_class classes%rowtype;
  v_dup int;
  v_count int;
  v_new enrollments%rowtype;
begin
  select * into v_class from classes where id = p_class_id for update;
  if not found then
    raise exception 'Không tìm thấy lớp học';
  end if;
  if p_role = 'STUDENT' and v_class.status != 'OPEN' then
    raise exception 'Lớp không còn nhận đăng ký';
  end if;
  select count(*) into v_dup from enrollments where class_id = p_class_id and student_id = p_student_id;
  if v_dup > 0 then
    if p_role = 'STUDENT' then
      raise exception 'Bạn đã đăng ký lớp này';
    else
      raise exception 'Học viên đã có trong lớp này';
    end if;
  end if;
  select count(*) into v_count from enrollments where class_id = p_class_id;
  if v_count >= v_class.max_students then
    raise exception 'Lớp đã đủ học viên';
  end if;

  insert into enrollments (student_id, class_id) values (p_student_id, p_class_id)
  returning * into v_new;

  return json_build_object('id', v_new.id, 'student_id', v_new.student_id, 'class_id', v_new.class_id);
end;
$$ language plpgsql security definer;

-- 15. Hàm Học viên tự hủy đăng ký
create or replace function cancel_my_enrollment(p_class_id bigint, p_student_id bigint)
returns json as $$
declare
  v_eid bigint;
  v_status text;
  v_paid boolean;
  v_attended boolean;
begin
  select e.id, cl.status,
         exists(select 1 from payments p where p.enrollment_id = e.id),
         exists(select 1 from attendances a where a.enrollment_id = e.id)
  into v_eid, v_status, v_paid, v_attended
  from enrollments e join classes cl on cl.id = e.class_id
  where e.class_id = p_class_id and e.student_id = p_student_id;

  if v_eid is null then
    raise exception 'Bạn chưa đăng ký lớp này';
  end if;
  if v_status != 'OPEN' then
    raise exception 'Lớp đã bắt đầu, vui lòng liên hệ trung tâm để hủy';
  end if;
  if v_paid or v_attended then
    raise exception 'Bạn đã đóng học phí hoặc đã đi học, vui lòng liên hệ trung tâm để hủy';
  end if;

  delete from enrollments where id = v_eid;
  return json_build_object('ok', true);
end;
$$ language plpgsql security definer;

-- 16. Hàm Lấy điểm danh theo ngày
create or replace function get_attendance(p_class_id bigint, p_date date)
returns json as $$
declare
  r json;
begin
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
$$ language plpgsql security definer;

-- 17. Hàm Lưu điểm danh
create or replace function save_attendance(p_class_id bigint, p_date date, p_records json)
returns json as $$
declare
  r json;
begin
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
$$ language plpgsql security definer;

-- 18. Hàm Tạo phiếu thu học phí
create or replace function create_payment(p_enrollment_id bigint, p_amount numeric, p_method text default 'CASH', p_note text default null)
returns json as $$
declare
  v_debt numeric;
  v_new payments%rowtype;
begin
  if p_amount <= 0 then
    raise exception 'Số tiền phải lớn hơn 0';
  end if;
  select co.fee - coalesce((select sum(amount) from payments where enrollment_id = e.id), 0)
  into v_debt
  from enrollments e
  join classes cl on cl.id = e.class_id
  join courses co on co.id = cl.course_id
  where e.id = p_enrollment_id;

  if v_debt is null then
    raise exception 'Không tìm thấy thông tin ghi danh';
  end if;
  if p_amount > v_debt then
    raise exception 'Số tiền vượt quá công nợ còn lại';
  end if;

  insert into payments (enrollment_id, amount, method, note)
  values (p_enrollment_id, p_amount, coalesce(p_method, 'CASH'), p_note)
  returning * into v_new;

  return json_build_object('id', v_new.id, 'amount', v_new.amount);
end;
$$ language plpgsql security definer;

-- 19. Hàm Tổng quan / Báo cáo doanh thu
create or replace function reports_summary()
returns json as $$
declare
  r json;
  m json;
begin
  select json_build_object(
    'students', (select count(*) from users where role = 'STUDENT' and active),
    'teachers', (select count(*) from users where role = 'TEACHER' and active),
    'courses', (select count(*) from courses),
    'active_classes', (select count(*) from classes where status in ('OPEN', 'ONGOING')),
    'total_revenue', (select coalesce(sum(amount), 0) from payments),
    'month_revenue', (select coalesce(sum(amount), 0) from payments where date_trunc('month', paid_at) = date_trunc('month', now())),
    'total_debt', (select coalesce(sum(co.fee), 0) from enrollments e join classes cl on cl.id = e.class_id join courses co on co.id = cl.course_id) - (select coalesce(sum(amount), 0) from payments)
  ) into r;

  select json_agg(x) into m from (
    select to_char(s.m, 'MM/YYYY') as month, coalesce(sum(p.amount), 0) as total
    from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') as s(m)
    left join payments p on date_trunc('month', p.paid_at) = s.m
    group by s.m
    order by s.m desc
  ) x;

  return json_build_object(
    'students', (r->>'students')::int,
    'teachers', (r->>'teachers')::int,
    'courses', (r->>'courses')::int,
    'active_classes', (r->>'active_classes')::int,
    'total_revenue', (r->>'total_revenue')::numeric,
    'month_revenue', (r->>'month_revenue')::numeric,
    'total_debt', (r->>'total_debt')::numeric,
    'monthly', coalesce(m, '[]'::json)
  );
end;
$$ language plpgsql security definer;



-- =====================================================================
-- 20. Bảng Bài tập (Assignments)
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

-- =====================================================================
-- 21. Bảng Bài nộp của học viên (Submissions)
-- =====================================================================
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

alter table assignments disable row level security;
alter table submissions disable row level security;

-- =====================================================================
-- 22. View danh sách bài tập kèm số lượng học viên đã nộp
-- =====================================================================
create or replace view v_assignments as
select a.id, a.class_id, a.teacher_id, a.title, a.description, a.due_date, a.attachment_url, a.attachment_name, a.created_at,
       cl.name as class_name,
       (select count(*) from submissions s where s.assignment_id = a.id)::int as submission_count,
       (select count(*) from enrollments e where e.class_id = a.class_id)::int as total_students
from assignments a
join classes cl on cl.id = a.class_id;

-- =====================================================================
-- 23. View bài nộp kèm thông tin học viên
-- =====================================================================
create or replace view v_submissions as
select s.id, s.assignment_id, s.student_id, s.file_url, s.file_name, s.notes, s.submitted_at,
       s.score, s.feedback, s.graded_at,
       u.full_name as student_name, u.email as student_email
from submissions s
join users u on u.id = s.student_id;

-- =====================================================================
-- 24. Hàm lấy lịch sử điểm danh của học viên trong lớp
-- =====================================================================
create or replace function get_student_attendance(p_class_id bigint, p_student_id bigint)
returns json as $$
declare
  r json;
begin
  select json_agg(x) into r from (
    select a.id, a.session_date, a.status, a.note
    from attendances a
    join enrollments e on e.id = a.enrollment_id
    where e.class_id = p_class_id and e.student_id = p_student_id
    order by a.session_date desc
  ) x;
  return coalesce(r, '[]'::json);
end;
$$ language plpgsql security definer;

-- =====================================================================
-- 25. Cấu hình Storage bucket cho tệp đính kèm và bài nộp
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('submissions', 'submissions', true)
on conflict (id) do nothing;
