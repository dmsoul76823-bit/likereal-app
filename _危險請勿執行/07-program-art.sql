-- ============================================================
--  節目主視覺（同名場次共用一張圖）
--  一檔節目會開很多場次，圖片綁在「節目名稱」而不是每個場次
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

create table if not exists public.program_art (
  name       text primary key,          -- 節目名稱，對應 events.name
  img        text,                      -- 主視覺（網址或 base64）
  intro      text,                      -- 節目介紹（選填，覆蓋場次的 intro）
  updated_at timestamptz default now()
);

alter table public.program_art enable row level security;

drop policy if exists pub_read_program_art on public.program_art;
drop policy if exists staff_w_program_art  on public.program_art;

create policy pub_read_program_art on public.program_art for select using (true);
create policy staff_w_program_art  on public.program_art for all
  using (has_perm('events')) with check (has_perm('events'));

-- 把目前所有節目名稱先建好空白項目，之後在後台逐一上傳圖片
insert into public.program_art (name)
select distinct name from public.events
on conflict (name) do nothing;

-- 檢視：有幾種節目、各有幾場
select p.name as 節目,
       (select count(*) from public.events e where e.name = p.name) as 場次數,
       case when p.img is null or p.img = '' then '尚未設定' else '已設定' end as 主視覺
from public.program_art p
order by 場次數 desc, p.name;
