-- ============================================================
--  新增後台人員的輔助函式
--  讓管理者可以在後台用 Email 新增人員（自動對應到 Auth 帳號）
--  在 SQL Editor 貼上執行一次即可
-- ============================================================

create or replace function public.add_staff(
  p_email text,
  p_name  text,
  p_role  text,
  p_perms jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid;
begin
  -- 只有管理者可以新增人員
  if not exists (select 1 from public.staff where id = auth.uid() and role = 'admin') then
    raise exception '只有管理者可以新增後台人員';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then
    raise exception '找不到 Email % 的登入帳號，請先到 Authentication → Users 建立', p_email;
  end if;

  insert into public.staff (id, email, name, role, perms)
  values (v_uid, lower(p_email), p_name, coalesce(p_role,'staff'), coalesce(p_perms,'[]'::jsonb))
  on conflict (id) do update
    set name = excluded.name, role = excluded.role, perms = excluded.perms;

  return v_uid;
end $$;

grant execute on function public.add_staff(text, text, text, jsonb) to authenticated;

select 'add_staff 函式建立完成 ✓' as result;
