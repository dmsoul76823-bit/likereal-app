-- ============================================================
--  LiReal 沉浸式場域 — Supabase 資料庫
--  在 Supabase → SQL Editor 全部貼上後按 Run
--  ⚠ 這會刪除舊 likereal 售票系統的資料表
-- ============================================================

-- ---------- 1. 清除舊專案資料表 ----------
drop function if exists public.buy_seats(bigint, jsonb, text, int, text, text, text) cascade;
drop function if exists public.is_staff() cascade;
drop function if exists public.has_perm(text) cascade;

drop table if exists public.ticket_types  cascade;
drop table if exists public.tickets       cascade;
drop table if exists public.announcements cascade;
drop table if exists public.banners       cascade;
drop table if exists public.site_settings cascade;
drop table if exists public.settings      cascade;
drop table if exists public.orders        cascade;
drop table if exists public.events        cascade;
drop table if exists public.venues        cascade;
drop table if exists public.creators      cascade;
drop table if exists public.products      cascade;
drop table if exists public.members       cascade;
drop table if exists public.staff         cascade;

drop sequence if exists public.order_seq;


-- ---------- 2. 資料表 ----------

-- 場地（座位圖範本）
create table public.venues (
  id         bigint primary key,
  name       text   not null,
  n_rows     int    not null default 12,
  n_cols     int    not null default 20,
  stage      jsonb  not null default '{}'::jsonb,   -- {x,y,w,h,shape,label}
  off_seats  jsonb  not null default '[]'::jsonb,   -- ["0-3", ...] 走道/無座位
  boxes      jsonb  not null default '[]'::jsonb,   -- [{name,seats:[...]}]
  updated_at timestamptz default now()
);

-- 節目 / 場次
create table public.events (
  id         bigint primary key,
  name       text not null,
  venue      text,
  venue_id   bigint references public.venues(id) on delete set null,
  show_date  text,
  show_time  text,
  cat        text,
  status     text default '未開賣',
  sale       text,
  sold       int  default 0,
  cap        int  default 0,
  tickets    jsonb not null default '[]'::jsonb,
  sold_seats jsonb not null default '[]'::jsonb,
  intro      text,
  yt         text,
  img        text,
  updated_at timestamptz default now()
);
create index on public.events (show_date);

-- 創作者 / AI 女友
create table public.creators (
  id      bigint primary key,
  name    text not null,
  slug    text unique not null,
  ctype   text,
  tier    text,
  online  boolean default true,
  fans    text,
  hot     text,
  descr   text
);

-- 商品
create table public.products (
  id        bigint primary key,
  img_key   text,
  name      text not null,
  price     int default 0,
  old_price int default 0,
  stock     int default 0,
  badge     text,
  on_sale   boolean default true
);

-- 訂單
create table public.orders (
  id         text primary key,
  name       text,
  phone      text,
  email      text,
  item       text,
  amt        int default 0,
  status     text default '待付款',
  pay        text,
  order_date text,
  used       boolean default false,
  created_at timestamptz default now()
);
create index on public.orders (created_at desc);

-- 會員
create table public.members (
  id           bigint primary key,
  name         text,
  email        text,
  phone        text,
  vip          text,
  wallet       int default 0,
  orders_count int default 0,
  join_date    text
);

-- 後台人員（id 對應 Supabase Auth 的使用者）
create table public.staff (
  id    uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  name  text,
  role  text default 'staff',
  perms jsonb not null default '[]'::jsonb
);

-- 站台設定（key-value）：marquee / seo / announcements / banners / images
create table public.settings (
  key   text primary key,
  value jsonb not null default '{}'::jsonb
);

create sequence public.order_seq start 1001;


-- ---------- 3. 權限判斷函式 ----------
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where id = auth.uid());
$$;

create or replace function public.has_perm(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.staff
    where id = auth.uid() and (role = 'admin' or perms ? p)
  );
$$;


-- ---------- 4. RLS（資料列安全性）----------
alter table public.venues   enable row level security;
alter table public.events   enable row level security;
alter table public.creators enable row level security;
alter table public.products enable row level security;
alter table public.orders   enable row level security;
alter table public.members  enable row level security;
alter table public.staff    enable row level security;
alter table public.settings enable row level security;

-- 公開可讀：前台需要的內容
create policy pub_read_venues   on public.venues   for select using (true);
create policy pub_read_events   on public.events   for select using (true);
create policy pub_read_creators on public.creators for select using (true);
create policy pub_read_products on public.products for select using (true);
create policy pub_read_settings on public.settings for select using (true);

-- 後台可寫（依權限）
create policy staff_w_venues   on public.venues   for all using (has_perm('venues'))   with check (has_perm('venues'));
create policy staff_w_events   on public.events   for all using (has_perm('events'))   with check (has_perm('events'));
create policy staff_w_creators on public.creators for all using (has_perm('creators')) with check (has_perm('creators'));
create policy staff_w_products on public.products for all using (has_perm('products')) with check (has_perm('products'));
create policy staff_w_settings on public.settings for all using (has_perm('settings')) with check (has_perm('settings'));

-- 訂單：後台可讀寫；前台一律透過 buy_seats() 建立
create policy staff_r_orders on public.orders for select using (has_perm('orders'));
create policy staff_w_orders on public.orders for update using (has_perm('orders')) with check (has_perm('orders'));
create policy staff_d_orders on public.orders for delete using (has_perm('orders'));

-- 會員：後台可讀寫
create policy staff_all_members on public.members for all using (has_perm('members')) with check (has_perm('members'));

-- 人員
create policy self_read_staff  on public.staff for select using (id = auth.uid() or has_perm('staff'));
create policy admin_all_staff  on public.staff for all    using (has_perm('staff')) with check (has_perm('staff'));


-- ---------- 5. 購票（防超賣，原子操作）----------
create or replace function public.buy_seats(
  p_event_id bigint,
  p_seats    jsonb,
  p_item     text,
  p_amt      int,
  p_name     text,
  p_phone    text,
  p_email    text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_sold jsonb;
  v_cap  int;
  v_dup  text;
  v_new  jsonb;
  v_id   text;
begin
  if p_seats is null or jsonb_array_length(p_seats) = 0 then
    raise exception '沒有選擇座位';
  end if;

  select sold_seats, cap into v_sold, v_cap
    from public.events where id = p_event_id for update;
  if not found then raise exception '找不到此場次'; end if;

  select t.value into v_dup
    from jsonb_array_elements_text(p_seats) as t(value)
   where v_sold ? t.value
   limit 1;
  if v_dup is not null then
    raise exception '座位 % 已售出，請重新選位', v_dup;
  end if;

  v_new := v_sold || p_seats;

  update public.events
     set sold_seats = v_new,
         sold       = jsonb_array_length(v_new),
         status     = case
                        when jsonb_array_length(v_new) >= cap then '已售罄'
                        when cap - jsonb_array_length(v_new) <= greatest(5, round(cap * 0.05)) then '即將售罄'
                        else status end,
         updated_at = now()
   where id = p_event_id;

  v_id := 'LR-' || to_char(now(), 'YYYY') || '-' ||
          lpad(nextval('public.order_seq')::text, 4, '0');

  insert into public.orders (id, name, phone, email, item, amt, status, pay, order_date, used)
  values (v_id, coalesce(p_name,'前台訪客'), p_phone, p_email, p_item,
          coalesce(p_amt,0), '已付款', '線上', to_char(now(),'YYYY-MM-DD'), false);

  return v_id;
end $$;

grant execute on function public.buy_seats(bigint, jsonb, text, int, text, text, text) to anon, authenticated;


-- ---------- 6. 完成 ----------
select 'LiReal schema 建立完成 ✓' as result;
