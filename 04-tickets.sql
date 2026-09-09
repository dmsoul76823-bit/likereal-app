-- ============================================================
--  電子票券 + 購票表單 + 驗票
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

-- ---------- 1. 訂單加上發票欄位 ----------
alter table public.orders add column if not exists invoice jsonb default '{}'::jsonb;

-- ---------- 2. 票券表（一個座位一張票）----------
drop table if exists public.passes cascade;

create table public.passes (
  code        text primary key,            -- 例：LR-2026-0007-1-A3F9
  order_id    text not null references public.orders(id) on delete cascade,
  event_id    bigint references public.events(id) on delete set null,
  event_name  text,
  seat        text,                        -- "0-3"
  seat_label  text,                        -- "A4"
  ticket_name text,                        -- "VIP 沉浸席"
  price       int default 0,
  used        boolean default false,
  used_at     timestamptz,
  used_by     text,
  created_at  timestamptz default now()
);
create index on public.passes (order_id);
create index on public.passes (event_id);

alter table public.passes enable row level security;

-- 後台可讀；驗票由 check_in() 處理
create policy staff_r_passes on public.passes for select
  using (has_perm('checkin') or has_perm('orders'));
create policy staff_u_passes on public.passes for update
  using (has_perm('checkin')) with check (has_perm('checkin'));


-- ---------- 3. 購票（含購票人資料、發票、產生票券）----------
drop function if exists public.buy_seats(bigint, jsonb, text, int, text, text, text) cascade;

create or replace function public.buy_seats(
  p_event_id bigint,
  p_seats    jsonb,      -- [{"seat":"0-3","label":"A4","ticket":"VIP 沉浸席","price":2880}, ...]
  p_name     text,
  p_phone    text,
  p_email    text,
  p_invoice  jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sold   jsonb;
  v_cap    int;
  v_name   text;
  v_dup    text;
  v_ids    jsonb;
  v_new    jsonb;
  v_order  text;
  v_amt    int;
  v_item   text;
  v_code   text;
  v_i      int := 0;
  r        record;
  v_passes jsonb := '[]'::jsonb;
begin
  if p_seats is null or jsonb_array_length(p_seats) = 0 then
    raise exception '沒有選擇座位';
  end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_phone),'') = '' or coalesce(trim(p_email),'') = '' then
    raise exception '請填寫姓名、電話與 Email';
  end if;

  -- 鎖定場次
  select sold_seats, cap, name into v_sold, v_cap, v_name
    from public.events where id = p_event_id for update;
  if not found then raise exception '找不到此場次'; end if;

  -- 取出座位代碼陣列
  select coalesce(jsonb_agg(x->>'seat'), '[]'::jsonb) into v_ids
    from jsonb_array_elements(p_seats) as x;

  -- 檢查是否已售
  select t.value into v_dup
    from jsonb_array_elements_text(v_ids) as t(value)
   where v_sold ? t.value
   limit 1;
  if v_dup is not null then
    raise exception '座位已被其他人購買，請重新選位';
  end if;

  v_new := v_sold || v_ids;

  select coalesce(sum((x->>'price')::int), 0),
         string_agg(coalesce(x->>'ticket','') || ' ' || coalesce(x->>'label',''), '、')
    into v_amt, v_item
    from jsonb_array_elements(p_seats) as x;

  update public.events
     set sold_seats = v_new,
         sold       = jsonb_array_length(v_new),
         status     = case
                        when jsonb_array_length(v_new) >= cap then '已售罄'
                        when cap - jsonb_array_length(v_new) <= greatest(5, round(cap * 0.05)) then '即將售罄'
                        else status end,
         updated_at = now()
   where id = p_event_id;

  v_order := 'LR-' || to_char(now(),'YYYY') || '-' ||
             lpad(nextval('public.order_seq')::text, 4, '0');

  insert into public.orders (id, name, phone, email, item, amt, status, pay, order_date, used, invoice)
  values (v_order, trim(p_name), trim(p_phone), trim(p_email),
          v_name || ' · ' || coalesce(v_item,''), v_amt,
          '已付款', '線上', to_char(now(),'YYYY-MM-DD'), false, coalesce(p_invoice,'{}'::jsonb));

  -- 每個座位產生一張票
  for r in select value from jsonb_array_elements(p_seats) loop
    v_i := v_i + 1;
    v_code := v_order || '-' || v_i || '-' ||
              upper(substring(md5(random()::text || clock_timestamp()::text), 1, 4));
    insert into public.passes (code, order_id, event_id, event_name, seat, seat_label, ticket_name, price)
    values (v_code, v_order, p_event_id, v_name,
            r.value->>'seat', r.value->>'label', r.value->>'ticket',
            coalesce((r.value->>'price')::int, 0));
    v_passes := v_passes || jsonb_build_object(
      'code', v_code, 'seat_label', r.value->>'label',
      'ticket', r.value->>'ticket', 'price', (r.value->>'price')::int);
  end loop;

  return jsonb_build_object(
    'order_id', v_order, 'amount', v_amt,
    'event', v_name, 'passes', v_passes);
end $$;

grant execute on function public.buy_seats(bigint, jsonb, text, text, text, jsonb) to anon, authenticated;


-- ---------- 4. 驗票 ----------
create or replace function public.check_in(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.passes%rowtype;
  o public.orders%rowtype;
begin
  if not (select has_perm('checkin')) then
    raise exception '沒有驗票權限';
  end if;

  select * into p from public.passes where upper(code) = upper(trim(p_code)) for update;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'notfound', 'msg', '查無此票券');
  end if;

  select * into o from public.orders where id = p.order_id;

  if o.status <> '已付款' then
    return jsonb_build_object('ok', false, 'state', 'unpaid', 'msg', '訂單狀態為「' || o.status || '」，不可入場',
      'pass', to_jsonb(p), 'buyer', o.name);
  end if;

  if p.used then
    return jsonb_build_object('ok', false, 'state', 'used', 'msg', '此票券已於 ' ||
      to_char(p.used_at at time zone 'Asia/Taipei', 'MM/DD HH24:MI') || ' 入場',
      'pass', to_jsonb(p), 'buyer', o.name);
  end if;

  update public.passes
     set used = true, used_at = now(),
         used_by = (select email from public.staff where id = auth.uid())
   where code = p.code
   returning * into p;

  -- 整張訂單都入場了就標記
  update public.orders set used = true
   where id = p.order_id
     and not exists (select 1 from public.passes where order_id = p.order_id and used = false);

  return jsonb_build_object('ok', true, 'state', 'ok', 'msg', '驗票成功',
    'pass', to_jsonb(p), 'buyer', o.name);
end $$;

grant execute on function public.check_in(text) to authenticated;

select '票券系統建立完成 ✓' as result;
