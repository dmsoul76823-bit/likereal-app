-- ============================================================
--  新增排序欄位：讓後台「新增的項目排在最上面」
--  在 SQL Editor 貼上執行
-- ============================================================

alter table public.events   add column if not exists created_at timestamptz default now();
alter table public.venues   add column if not exists created_at timestamptz default now();
alter table public.creators add column if not exists created_at timestamptz default now();
alter table public.products add column if not exists created_at timestamptz default now();

-- 既有資料依 id 給一個遞增的建立時間，維持原本的排列順序
update public.events   set created_at = now() - (id % 100000) * interval '1 second' where created_at is null;
update public.venues   set created_at = now() - (id % 100000) * interval '1 second' where created_at is null;
update public.creators set created_at = now() - (id % 100000) * interval '1 second' where created_at is null;
update public.products set created_at = now() - (id % 100000) * interval '1 second' where created_at is null;

create index if not exists events_created_idx   on public.events   (created_at desc);
create index if not exists creators_created_idx on public.creators (created_at desc);
create index if not exists products_created_idx on public.products (created_at desc);

select '排序欄位建立完成 ✓' as result;
