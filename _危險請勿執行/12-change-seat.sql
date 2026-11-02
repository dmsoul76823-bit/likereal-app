-- ============================================================
--  票券換位／升級票種（每張票僅限一次）
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

-- ---------- 1. 票券加上換位紀錄欄位 ----------
alter table public.passes add column if not exists changed_count   int default 0;
alter table public.passes add column if not exists changed_at      timestamptz;
alter table public.passes add column if not exists orig_seat       text;
alter table public.passes add column if not exists orig_seat_label text;
alter table public.passes add column if not exists orig_ticket     text;
alter table public.passes add column if not exists orig_price      int;

comment on column public.passes.changed_count is '已換位次數；每張票僅限 1 次';
comment on column public.passes.orig_seat     is '換位前的原始座位（保留紀錄）';


-- ---------- 2. 消費者查詢自己的票券 ----------
--  需要「票券編號」，或「Email + 手機」兩者都對，才查得到
drop function if exists public.find_passes(text, text, text);

create or replace function public.find_passes(
  p_code  text default null,
  p_email text default null,
  p_phone text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_rows jsonb;
begin
  if coalesce(trim(p_code),'') = ''
     and (coalesce(trim(p_email),'') = '' or coalesce(trim(p_phone),'') = '') then
    raise exception '請輸入票券編號，或 Email 與手機號碼';
  end if;

  select coalesce(jsonb_agg(x order by x->>'show_date', x->>'seat_label'), '[]'::jsonb)
    into v_rows
  from (
    select jsonb_build_object(
             'code',        p.code,
             'order_id',    p.order_id,
             'event_id',    p.event_id,
             'event_name',  p.event_name,
             'seat',        p.seat,
             'seat_label',  p.seat_label,
             'ticket_name', p.ticket_name,
             'price',       p.price,
             'used',        p.used,
             'changed',     coalesce(p.changed_count,0) > 0,
             'orig_seat_label', p.orig_seat_label,
             'orig_ticket', p.orig_ticket,
             'buyer',       o.name,
             'status',      o.status,
             'show_date',   e.show_date::text,
             'show_time',   e.show_time::text,
             'venue',       e.venue,
             'can_change',
               (p.used = false
                and coalesce(p.changed_count,0) = 0
                and o.status = '已付款'
                and e.show_date >= current_date),
             'reason',
               case
                 when p.used then '已入場，無法換位'
                 when coalesce(p.changed_count,0) > 0 then '已使用過一次換位機會'
                 when o.status <> '已付款' then '訂單狀態為「' || o.status || '」'
                 when e.show_date < current_date then '演出已結束'
                 else ''
               end
           ) as x
    from public.passes p
    join public.orders o on o.id = p.order_id
    left join public.events e on e.id = p.event_id
    where (coalesce(trim(p_code),'') <> '' and upper(p.code) = upper(trim(p_code)))
       or (coalesce(trim(p_code),'') = ''
           and lower(o.email) = lower(trim(p_email))
           and regexp_replace(o.phone,'[^0-9]','','g') = regexp_replace(trim(p_phone),'[^0-9]','','g'))
  ) s;

  return v_rows;
end $$;

grant execute on function public.find_passes(text, text, text) to anon, authenticated;


-- ---------- 3. 換位／升級票種（每張票僅限一次）----------
drop function if exists public.change_seat(text, text, text, text, int);

create or replace function public.change_seat(
  p_code   text,     -- 票券編號
  p_seat   text,     -- 新座位 "3-12"
  p_label  text,     -- 新座位代號 "D13"
  p_ticket text,     -- 新票種名稱
  p_price  int       -- 新票種單價
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p      public.passes%rowtype;
  o      public.orders%rowtype;
  e      public.events%rowtype;
  v_sold jsonb;
  v_diff int;
  v_ord  text;
begin
  select * into p from public.passes where upper(code) = upper(trim(p_code)) for update;
  if not found then raise exception '查無此票券'; end if;

  select * into o from public.orders where id = p.order_id;
  if o.status <> '已付款' then raise exception '訂單狀態為「%」，無法換位', o.status; end if;
  if p.used then raise exception '此票券已入場，無法換位'; end if;
  if coalesce(p.changed_count,0) > 0 then
    raise exception '每張票券僅限換位一次，此票券已於 % 換過',
      to_char(p.changed_at at time zone 'Asia/Taipei','YYYY/MM/DD HH24:MI');
  end if;

  -- 鎖定場次，避免與其他人同時搶同一個位子
  select * into e from public.events where id = p.event_id for update;
  if not found then raise exception '找不到此場次'; end if;
  if e.show_date < current_date then raise exception '演出已結束，無法換位'; end if;

  if p_seat = p.seat then raise exception '新座位與原座位相同'; end if;

  v_sold := coalesce(e.sold_seats, '[]'::jsonb);
  if v_sold ? p_seat then raise exception '這個座位已被購買，請重新選位'; end if;

  -- 只能換同價或更高價的票種（差額補款，不退差額）
  v_diff := coalesce(p_price,0) - coalesce(p.price,0);
  if v_diff < 0 then
    raise exception '僅提供同級或升級換位，不受理降級退差額';
  end if;

  -- 釋放舊位、佔用新位
  update public.events
     set sold_seats = (
           select coalesce(jsonb_agg(t.value), '[]'::jsonb) || to_jsonb(array[p_seat])
             from jsonb_array_elements_text(v_sold) as t(value)
            where t.value <> p.seat),
         updated_at = now()
   where id = e.id;

  update public.events
     set sold   = jsonb_array_length(coalesce(sold_seats,'[]'::jsonb)),
         status = case
                    when jsonb_array_length(coalesce(sold_seats,'[]'::jsonb)) >= cap then '已售罄'
                    when cap - jsonb_array_length(coalesce(sold_seats,'[]'::jsonb))
                         <= greatest(5, round(cap * 0.05)) then '即將售罄'
                    else '售票中' end
   where id = e.id;

  -- 保留原始資料後更新票券
  update public.passes
     set orig_seat       = coalesce(orig_seat, seat),
         orig_seat_label = coalesce(orig_seat_label, seat_label),
         orig_ticket     = coalesce(orig_ticket, ticket_name),
         orig_price      = coalesce(orig_price, price),
         seat            = p_seat,
         seat_label      = p_label,
         ticket_name     = p_ticket,
         price           = coalesce(p_price, price),
         changed_count   = 1,
         changed_at      = now()
   where code = p.code
   returning * into p;

  -- 有差額就開一張補款訂單（方便對帳；金流串接後可改為線上補款）
  if v_diff > 0 then
    v_ord := 'LR-' || to_char(now(),'YYYY') || '-' ||
             lpad(nextval('public.order_seq')::text, 4, '0');
    insert into public.orders (id, name, phone, email, item, amt, status, pay, order_date, used, invoice)
    values (v_ord, o.name, o.phone, o.email,
            e.name || ' · 換位補差額（' || coalesce(p.orig_seat_label,'') || ' → ' || p_label || '）',
            v_diff, '待付款', '補差額', to_char(now(),'YYYY-MM-DD'), false, coalesce(o.invoice,'{}'::jsonb));
  end if;

  return jsonb_build_object(
    'ok', true,
    'pass', to_jsonb(p),
    'diff', v_diff,
    'diff_order', v_ord,
    'msg', case when v_diff > 0
                then '換位成功，需補差額 NT$' || v_diff
                else '換位成功' end);
end $$;

grant execute on function public.change_seat(text, text, text, text, int) to anon, authenticated;

select '換位功能建立完成 ✓' as result;
