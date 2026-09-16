-- ============================================================
--  商品說明頁：副標、詳細說明、規格、YouTube 影片
--  以及全站共用的「到貨／退貨／金流」須知
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

alter table public.products add column if not exists sub   text;   -- 一句話副標
alter table public.products add column if not exists intro text;   -- 商品詳細說明（可多段，換行分段）
alter table public.products add column if not exists spec  text;   -- 規格（可多段）
alter table public.products add column if not exists yt_id text;   -- YouTube 影片 ID

comment on column public.products.sub   is '商品卡與說明頁的一句話副標';
comment on column public.products.intro is '商品詳細說明，換行會自動分段';
comment on column public.products.spec  is '規格說明，換行會自動分段';
comment on column public.products.yt_id is 'YouTube 影片 ID，例如 LXb3EKWsInQ';

-- 購買須知（全站共用，後台「網站設定」可改）
insert into public.settings (key, value)
values ('shop_policy', '{"v":{"ship":"","ret":"","pay":"","note":""}}'::jsonb)
on conflict (key) do nothing;

select name,
       case when coalesce(intro,'')<>'' then '✓' else '' end as 說明,
       case when coalesce(spec,'')<>''  then '✓' else '' end as 規格,
       case when coalesce(yt_id,'')<>'' then '✓' else '' end as 影片,
       stock as 庫存
from public.products
order by name;
