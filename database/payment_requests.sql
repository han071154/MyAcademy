-- =====================================================================
-- MyAcademy - Học viên đóng học phí bằng chuyển khoản (mã QR)
--
-- Luồng: học viên quét mã QR của trung tâm, chuyển khoản với nội dung
-- "MYA <mã HV> <mã lớp>", rồi bấm "Tôi đã chuyển khoản" trong app
-- → tạo yêu cầu trạng thái PENDING (Chờ xác nhận).
-- Admin kiểm tra tài khoản ngân hàng → Xác nhận (tạo khoản thu thật) hoặc Từ chối.
-- Học viên KHÔNG tự ghi được khoản thu: chỉ admin xác nhận mới được tính tiền.
--
-- Chạy SAU database/supabase_setup.sql. Chạy lại nhiều lần vẫn an toàn.
-- =====================================================================

begin;

create table if not exists payment_requests (
  id            bigserial primary key,
  enrollment_id bigint not null references enrollments(id) on delete cascade,
  amount        numeric(12,0) not null check (amount > 0),
  transfer_code text not null,
  status        text not null default 'PENDING' check (status in ('PENDING','CONFIRMED','REJECTED')),
  reject_reason text,
  payment_id    bigint references payments(id) on delete set null,
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   bigint references users(id)
);
create index if not exists payment_requests_enrollment_idx on payment_requests(enrollment_id);
create index if not exists payment_requests_status_idx on payment_requests(status);

-- Chỉ đọc qua RLS; ghi chỉ qua các hàm bên dưới.
alter table payment_requests enable row level security;
revoke all on payment_requests from anon, authenticated;
grant select on payment_requests to authenticated;
drop policy if exists payment_requests_select on payment_requests;
create policy payment_requests_select on payment_requests for select to authenticated using (
  is_admin() or exists (select 1 from enrollments e
                        where e.id = payment_requests.enrollment_id and e.student_id = app_uid())
);

drop view if exists v_payment_requests;
create view v_payment_requests with (security_invoker = true) as
select r.id, r.enrollment_id, r.amount, r.transfer_code, r.status, r.reject_reason,
       r.created_at, r.reviewed_at,
       e.class_id, e.student_id, u.full_name as student_name, u.phone as student_phone,
       cl.name as class_name
from payment_requests r
join enrollments e on e.id = r.enrollment_id
join users u on u.id = e.student_id
join classes cl on cl.id = e.class_id;
revoke all on v_payment_requests from anon;
grant select on v_payment_requests to authenticated;

-- Còn nợ của 1 ghi danh (không tính yêu cầu đang chờ).
create or replace function _enrollment_debt(p_enrollment_id bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select co.fee - coalesce((select sum(amount) from payments where enrollment_id = e.id), 0)
  from enrollments e
  join classes cl on cl.id = e.class_id
  join courses co on co.id = cl.course_id
  where e.id = p_enrollment_id
$$;

-- Học viên: báo đã chuyển khoản cho 1 lớp của mình.
create or replace function create_payment_request(p_class_id bigint, p_amount numeric)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid bigint := app_uid();
  v_eid bigint;
  v_pending numeric;
  v_debt numeric;
  v_new payment_requests%rowtype;
begin
  if app_role() is distinct from 'STUDENT' then
    raise exception 'Chỉ học viên mới gửi được yêu cầu đóng học phí';
  end if;
  select id into v_eid from enrollments where class_id = p_class_id and student_id = v_uid;
  if v_eid is null then raise exception 'Bạn chưa đăng ký lớp này'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Số tiền phải lớn hơn 0'; end if;

  select coalesce(sum(amount), 0) into v_pending from payment_requests
  where enrollment_id = v_eid and status = 'PENDING';
  v_debt := _enrollment_debt(v_eid) - v_pending;
  if v_debt <= 0 then
    raise exception 'Lớp này đã đóng đủ học phí hoặc đang chờ trung tâm xác nhận';
  end if;
  if p_amount > v_debt then
    raise exception 'Số tiền vượt quá học phí còn phải đóng';
  end if;

  insert into payment_requests (enrollment_id, amount, transfer_code)
  values (v_eid, p_amount, 'MYA ' || v_uid || ' ' || p_class_id)
  returning * into v_new;
  return json_build_object('id', v_new.id, 'amount', v_new.amount, 'status', v_new.status);
end;
$$;

-- Học viên: hủy yêu cầu còn đang chờ (bấm nhầm).
create or replace function cancel_payment_request(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
begin
  delete from payment_requests r
  using enrollments e
  where r.id = p_id and e.id = r.enrollment_id and e.student_id = app_uid() and r.status = 'PENDING';
  if not found then raise exception 'Không tìm thấy yêu cầu đang chờ'; end if;
  return json_build_object('ok', true);
end;
$$;

-- Admin: xác nhận đã nhận tiền → tạo khoản thu thật.
create or replace function confirm_payment_request(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_r payment_requests%rowtype;
  v_pay payments%rowtype;
begin
  perform _require_admin();
  select * into v_r from payment_requests where id = p_id for update;
  if not found then raise exception 'Không tìm thấy yêu cầu'; end if;
  if v_r.status != 'PENDING' then raise exception 'Yêu cầu này đã được xử lý'; end if;
  if v_r.amount > _enrollment_debt(v_r.enrollment_id) then
    raise exception 'Số tiền vượt quá công nợ còn lại, hãy từ chối và thu đúng số tiền';
  end if;

  insert into payments (enrollment_id, amount, method, note)
  values (v_r.enrollment_id, v_r.amount, 'TRANSFER', 'Chuyển khoản: ' || v_r.transfer_code)
  returning * into v_pay;

  update payment_requests
  set status = 'CONFIRMED', payment_id = v_pay.id, reviewed_at = now(), reviewed_by = app_uid()
  where id = p_id;
  return json_build_object('ok', true, 'payment_id', v_pay.id);
end;
$$;

-- Admin: từ chối (chưa nhận được tiền / sai số tiền).
create or replace function reject_payment_request(p_id bigint, p_reason text default null) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin();
  update payment_requests
  set status = 'REJECTED', reject_reason = nullif(trim(coalesce(p_reason, '')), ''),
      reviewed_at = now(), reviewed_by = app_uid()
  where id = p_id and status = 'PENDING';
  if not found then raise exception 'Yêu cầu không tồn tại hoặc đã được xử lý'; end if;
  return json_build_object('ok', true);
end;
$$;

revoke execute on function _enrollment_debt(bigint) from public, anon, authenticated;
revoke execute on function create_payment_request(bigint, numeric) from public, anon;
revoke execute on function cancel_payment_request(bigint) from public, anon;
revoke execute on function confirm_payment_request(bigint) from public, anon;
revoke execute on function reject_payment_request(bigint, text) from public, anon;
grant execute on function create_payment_request(bigint, numeric) to authenticated;
grant execute on function cancel_payment_request(bigint) to authenticated;
grant execute on function confirm_payment_request(bigint) to authenticated;
grant execute on function reject_payment_request(bigint, text) to authenticated;

commit;
