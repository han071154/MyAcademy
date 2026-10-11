-- Chạy toàn bộ file này trong Supabase → SQL Editor

create table users (
  id            bigserial primary key,
  email         text unique not null,
  password_hash text not null,
  full_name     text not null,
  role          text not null check (role in ('ADMIN','TEACHER','STUDENT')),
  phone         text,
  dob           date,
  address       text,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table courses (
  id             bigserial primary key,
  name           text not null,
  level          text,
  duration_weeks int,
  fee            numeric(12,0) not null default 0 check (fee >= 0),
  description    text
);

create table classes (
  id           bigserial primary key,
  course_id    bigint not null references courses(id),
  teacher_id   bigint references users(id),
  name         text not null,
  start_date   date,
  end_date     date,
  schedule     text,                       -- VD: "T2-T4 18:00-19:30"
  room         text,
  max_students int not null default 20,
  status       text not null default 'OPEN' check (status in ('OPEN','ONGOING','CLOSED'))
);

create table enrollments (
  id          bigserial primary key,
  student_id  bigint not null references users(id),
  class_id    bigint not null references classes(id) on delete cascade,
  enrolled_at timestamptz not null default now(),
  unique (student_id, class_id)
);

create table attendances (
  id            bigserial primary key,
  enrollment_id bigint not null references enrollments(id) on delete cascade,
  session_date  date not null,
  status        text not null check (status in ('PRESENT','ABSENT','LATE')),
  note          text,
  unique (enrollment_id, session_date)
);

create table payments (
  id            bigserial primary key,
  enrollment_id bigint not null references enrollments(id) on delete cascade,
  amount        numeric(12,0) not null check (amount > 0),
  paid_at       timestamptz not null default now(),
  method        text not null default 'CASH',
  note          text
);

create index on classes(teacher_id);
create index on enrollments(class_id);
create index on attendances(session_date);
create index on payments(enrollment_id);

-- Supabase tự mở các bảng ra Data API (khóa anon). Bật RLS không kèm policy để
-- chặn truy cập đó; Java API kết nối bằng user postgres nên vẫn đọc/ghi bình thường.
alter table users        enable row level security;
alter table courses      enable row level security;
alter table classes      enable row level security;
alter table enrollments  enable row level security;
alter table attendances  enable row level security;
alter table payments     enable row level security;

-- Dữ liệu mẫu
insert into courses(name, level, duration_weeks, fee, description) values
 ('IELTS Foundation', 'Cơ bản',    12, 3500000, 'Nền tảng IELTS 4.5+'),
 ('IELTS Intensive',  'Nâng cao',  16, 6000000, 'Luyện thi IELTS 6.5+'),
 ('TOEIC 600+',       'Trung cấp', 10, 3000000, 'Luyện thi TOEIC'),
 ('Giao tiếp cơ bản', 'Cơ bản',     8, 2000000, 'Tiếng Anh giao tiếp hằng ngày');
-- Tài khoản admin được tạo tự động khi chạy backend lần đầu (xem application.yml)
