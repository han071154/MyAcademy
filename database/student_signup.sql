-- =====================================================================
-- MyAcademy - Học viên tự đăng ký tài khoản + tự cập nhật hồ sơ cá nhân
--
-- Chạy SAU database/supabase_setup.sql (mỗi lần chạy lại supabase_setup.sql
-- thì chạy lại file này, vì file kia thu hồi quyền gọi hàm của khách).
-- Chạy lại nhiều lần vẫn an toàn.
--
-- Vẫn để TẮT "Allow new users to sign up" trong Supabase: học viên đăng ký
-- qua hàm register_student bên dưới, hàm này chỉ cho tạo vai trò STUDENT.
-- =====================================================================

begin;

-- Bản cũ (số điện thoại không bắt buộc, chưa có ngày sinh / địa chỉ).
drop function if exists register_student(text, text, text, text);

create or replace function register_student(
  p_email text, p_password text, p_full_name text, p_phone text, p_dob date, p_address text
) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_name text := trim(coalesce(p_full_name, ''));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[\s.-]', '', 'g');
  v_address text := trim(coalesce(p_address, ''));
  v_uid uuid;
  v_new users%rowtype;
begin
  if v_name = '' or length(v_name) > 100 then
    raise exception 'Vui lòng nhập họ tên (tối đa 100 ký tự)';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 254 then
    raise exception 'Email không hợp lệ';
  end if;
  if v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception 'Số điện thoại không hợp lệ (10 số, bắt đầu bằng 0)';
  end if;
  if p_dob is null or p_dob > current_date - interval '5 years' or p_dob < date '1900-01-01' then
    raise exception 'Ngày sinh không hợp lệ';
  end if;
  if v_address = '' or length(v_address) > 255 then
    raise exception 'Vui lòng nhập địa chỉ';
  end if;
  if p_password is null or length(p_password) < 8 or length(p_password) > 72 then
    raise exception 'Mật khẩu từ 8 đến 72 ký tự';
  end if;

  -- Chống tạo tài khoản rác hàng loạt: tối đa 30 tài khoản học viên mới mỗi giờ.
  if (select count(*) from users where role = 'STUDENT' and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Hệ thống đang nhận quá nhiều đăng ký, vui lòng thử lại sau';
  end if;

  if exists (select 1 from users where lower(email) = v_email)
     or exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Email đã được sử dụng';
  end if;
  if exists (select 1 from users where regexp_replace(coalesce(phone, ''), '[\s.-]', '', 'g') = v_phone) then
    raise exception 'Số điện thoại đã được sử dụng';
  end if;

  v_uid := _create_auth_user(v_email, p_password);
  insert into users (email, full_name, role, phone, dob, address, auth_id, must_change_password)
  values (v_email, v_name, 'STUDENT', v_phone, p_dob, v_address, v_uid, false)
  returning * into v_new;

  return json_build_object('id', v_new.id, 'email', v_new.email, 'full_name', v_new.full_name);
end;
$$;

revoke execute on function register_student(text, text, text, text, date, text) from public;
grant execute on function register_student(text, text, text, text, date, text) to anon, authenticated;

-- =====================================================================
-- Tự cập nhật hồ sơ cá nhân (mọi vai trò). Không đổi được email, vai trò hay trạng thái khóa.
-- =====================================================================
create or replace function update_my_profile(
  p_full_name text, p_phone text, p_dob date, p_address text
) returns json
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id bigint := app_uid();
  v_name text := trim(coalesce(p_full_name, ''));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[\s.-]', '', 'g');
  v_address text := trim(coalesce(p_address, ''));
  v_u users%rowtype;
begin
  if v_id is null then raise exception 'Bạn cần đăng nhập lại'; end if;
  if v_name = '' or length(v_name) > 100 then
    raise exception 'Vui lòng nhập họ tên (tối đa 100 ký tự)';
  end if;
  if v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception 'Số điện thoại không hợp lệ (10 số, bắt đầu bằng 0)';
  end if;
  if p_dob is null or p_dob > current_date - interval '5 years' or p_dob < date '1900-01-01' then
    raise exception 'Ngày sinh không hợp lệ';
  end if;
  if v_address = '' or length(v_address) > 255 then
    raise exception 'Vui lòng nhập địa chỉ';
  end if;
  if exists (select 1 from users
             where id <> v_id and regexp_replace(coalesce(phone, ''), '[\s.-]', '', 'g') = v_phone) then
    raise exception 'Số điện thoại đã được sử dụng';
  end if;

  update users set full_name = v_name, phone = v_phone, dob = p_dob, address = v_address
  where id = v_id
  returning * into v_u;

  return json_build_object('id', v_u.id, 'email', v_u.email, 'full_name', v_u.full_name, 'role', v_u.role,
    'phone', v_u.phone, 'dob', v_u.dob, 'address', v_u.address);
end;
$$;

revoke execute on function update_my_profile(text, text, date, text) from public, anon;
grant execute on function update_my_profile(text, text, date, text) to authenticated;

commit;
