-- ============================================================
--  首頁版面設定：指定哪些節目出現在首頁，以及顯示順序
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

alter table public.program_art add column if not exists featured   boolean default false;  -- 是否上首頁
alter table public.program_art add column if not exists sort_order int default 0;          -- 首頁排序（小的在前）

create index if not exists program_art_featured_idx
  on public.program_art (featured, sort_order);

comment on column public.program_art.featured   is '打勾後此節目會出現在前台首頁「沉浸節目」區';
comment on column public.program_art.sort_order is '首頁顯示順序，數字小的排前面';

-- 首頁區塊數量設定（存在 settings，可由後台調整）
insert into public.settings (key, value)
values ('home_layout', '{"v":{"programs":3,"tickets":6,"lives":6,"creators":6,"products":8,"plans":2}}'::jsonb)
on conflict (key) do nothing;

select name,
       featured as 上首頁,
       sort_order as 順序,
       case when coalesce(img,'')<>'' then '✓' else '' end as 主視覺
from public.program_art
order by featured desc, sort_order, name;
