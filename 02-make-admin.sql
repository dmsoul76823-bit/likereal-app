-- ============================================================
--  把你的帳號設為後台管理者
--  ⚠ 先在 Authentication → Users 建立帳號，再執行這段
-- ============================================================

insert into public.staff (id, email, name, role, perms)
select
  u.id,
  u.email,
  'Aden',
  'admin',
  '["dash","events","venues","creators","products","orders","members","checkin","settings","seo","staff"]'::jsonb
from auth.users u
where u.email = 'dmsoul76823@gmail.com'      -- ← 換成你建立帳號時用的 Email
on conflict (id) do update
  set role  = excluded.role,
      perms = excluded.perms,
      name  = excluded.name;

-- 確認結果：應該看到你的帳號、role = admin
select email, name, role, jsonb_array_length(perms) as perm_count from public.staff;
