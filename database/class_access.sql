-- =====================================================================
-- MyAcademy - HỌC VIÊN CHỈ VÀO LỚP KHI ĐÃ ĐÓNG HỌC PHÍ (ít nhất 1 đợt)
--
-- Quy tắc: học viên đã ghi danh nhưng CHƯA có khoản thu nào được ghi nhận
-- (chưa đóng tiền mặt, hoặc chuyển khoản chưa được admin xác nhận) thì:
--   - không xem được bài tập (kể cả tệp đề bài) của lớp,
--   - không nộp / nộp lại bài,
--   - không xem được điểm danh của mình trong lớp.
-- Chỉ cần 1 khoản thu (đóng 1 phần) là vào được, vẫn cho đóng nhiều đợt.
-- Lớp có học phí 0 đ thì không cần đóng.
--
-- Chạy SAU: supabase_setup.sql, student_rules.sql, payment_requests.sql.
-- Mỗi lần chạy lại supabase_setup.sql thì chạy lại file này. Chạy nhiều lần vẫn an toàn.
-- =====================================================================

begin;

-- Người đang đăng nhập được vào lớp này với tư cách học viên chưa?
create or replace function can_enter_class(p_class_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from enrollments e
    where e.class_id = p_class_id
      and e.student_id = app_uid()
      and (e.fee <= 0 or exists (select 1 from payments p where p.enrollment_id = e.id))
  )
$$;

-- Bài tập: học viên phải đã đóng tiền mới thấy (tệp đề bài trong Storage cũng theo quy tắc này).
drop policy if exists assignments_select on assignments;
create policy assignments_select on assignments for select to authenticated
  using (is_admin() or is_teacher_of(class_id) or can_enter_class(class_id));

-- Nộp bài / nộp lại: học viên phải đã đóng tiền.
drop policy if exists submissions_insert on submissions;
create policy submissions_insert on submissions for insert to authenticated with check (
  student_id = app_uid()
  and exists (select 1 from assignments a where a.id = submissions.assignment_id and can_enter_class(a.class_id))
);

drop policy if exists submissions_update on submissions;
create policy submissions_update on submissions for update to authenticated using (
  is_admin()
  or exists (select 1 from assignments a where a.id = submissions.assignment_id and is_teacher_of(a.class_id))
  or (student_id = app_uid()
      and exists (select 1 from assignments a where a.id = submissions.assignment_id and can_enter_class(a.class_id)))
);

-- Điểm danh của học viên: chặn khi chưa đóng tiền.
create or replace function get_student_attendance(p_class_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  r json;
begin
  if not can_enter_class(p_class_id) then
    raise exception 'Lớp chưa mở: bạn cần đóng ít nhất một đợt học phí và được trung tâm xác nhận';
  end if;
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

revoke all on function can_enter_class(bigint) from public, anon;
grant execute on function can_enter_class(bigint) to authenticated;
revoke all on function get_student_attendance(bigint) from public, anon;
grant execute on function get_student_attendance(bigint) to authenticated;

commit;

-- Kiểm tra: học viên đang ghi danh mà chưa có khoản thu nào (sẽ bị khóa lớp)
select u.full_name as hoc_vien, u.email, cl.name as lop, e.fee as hoc_phi, e.hold_until as giu_cho_den
from enrollments e
join users u    on u.id = e.student_id
join classes cl on cl.id = e.class_id
where e.fee > 0
  and not exists (select 1 from payments p where p.enrollment_id = e.id)
  and cl.status <> 'CLOSED'
order by cl.name, u.full_name;
