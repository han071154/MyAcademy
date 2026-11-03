-- =====================================================================
-- BỔ SUNG TÍNH NĂNG BÀI TẬP, NỘP BÀI VÀ XEM ĐIỂM DANH
-- Copy toàn bộ file này -> Mở Supabase -> SQL Editor -> Dán và bấm Run
-- =====================================================================

-- 1. Tạo bảng Bài tập (Assignments)
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

-- 2. Tạo bảng Bài nộp của học viên (Submissions)
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

-- Mở quyền truy cập cho app
alter table assignments disable row level security;
alter table submissions disable row level security;

-- 3. View danh sách bài tập kèm số lượng học viên đã nộp
create or replace view v_assignments as
select a.id, a.class_id, a.teacher_id, a.title, a.description, a.due_date, a.attachment_url, a.attachment_name, a.created_at,
       cl.name as class_name,
       (select count(*) from submissions s where s.assignment_id = a.id)::int as submission_count,
       (select count(*) from enrollments e where e.class_id = a.class_id)::int as total_students
from assignments a
join classes cl on cl.id = a.class_id;

-- 4. View bài nộp kèm thông tin học viên
create or replace view v_submissions as
select s.id, s.assignment_id, s.student_id, s.file_url, s.file_name, s.notes, s.submitted_at,
       s.score, s.feedback, s.graded_at,
       u.full_name as student_name, u.email as student_email
from submissions s
join users u on u.id = s.student_id;

-- 5. Hàm lấy lịch sử điểm danh của học viên trong lớp
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

-- 6. Tạo bucket lưu trữ tệp đính kèm và bài nộp
insert into storage.buckets (id, name, public)
values ('submissions', 'submissions', true)
on conflict (id) do nothing;

