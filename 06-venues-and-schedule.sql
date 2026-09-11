-- ============================================================
--  LiReal 奇境·微風廣場 9F
--  建立 A/B/C/D/E/D+E 六個場地，並自動排出 2027/03/01 ~ 2027/08/31 場次
--  在 Supabase → SQL Editor 貼上執行（約需 10～40 秒）
--  可重複執行：會先清掉本檔產生的資料再重建
-- ============================================================

-- ---------- 0. 座位產生器 ----------
create or replace function public.gen_seats(p_r0 int, p_r1 int, p_c0 int, p_c1 int)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(r::text || '-' || c::text order by r, c), '[]'::jsonb)
  from generate_series(p_r0, p_r1) r, generate_series(p_c0, p_c1) c;
$$;

-- ---------- 1. 場地 ----------
delete from public.passes where event_id between 900001 and 999999;
delete from public.events where id between 900001 and 999999;
delete from public.venues where id between 9001 and 9006;

insert into public.venues (id, name, n_rows, n_cols, stage, off_seats, boxes) values
 (9001,'A 廳', 10,15,
   '{"x":2.5,"y":-3,"w":10,"h":1.8,"shape":"round","label":"STAGE · 舞台"}'::jsonb,'[]'::jsonb,'[]'::jsonb),
 (9002,'B 廳', 10,15,
   '{"x":2.5,"y":-3,"w":10,"h":1.8,"shape":"round","label":"STAGE · 舞台"}'::jsonb,'[]'::jsonb,'[]'::jsonb),
 (9003,'C 廳', 10,15,
   '{"x":2.5,"y":-3,"w":10,"h":1.8,"shape":"round","label":"STAGE · 舞台"}'::jsonb,'[]'::jsonb,'[]'::jsonb),
 (9004,'D 廳', 10,20,
   '{"x":4,"y":-3.2,"w":12,"h":2,"shape":"arc","label":"STAGE · 舞台"}'::jsonb,'[]'::jsonb,
   '[{"name":"VIP 卡座 1","seats":["9-0","9-1","9-2","9-3"]},{"name":"VIP 卡座 2","seats":["9-16","9-17","9-18","9-19"]}]'::jsonb),
 (9005,'E 廳', 16,25,
   '{"x":5,"y":-3.5,"w":15,"h":2.2,"shape":"arc","label":"STAGE · 舞台"}'::jsonb,'[]'::jsonb,
   '[{"name":"VIP 包廂 A","seats":["15-0","15-1","15-2","15-3","15-4"]},{"name":"VIP 包廂 B","seats":["15-20","15-21","15-22","15-23","15-24"]}]'::jsonb),
 (9006,'D+E 廳（開通）', 24,25,
   '{"x":4,"y":-4,"w":17,"h":2.6,"shape":"arc","label":"MAIN STAGE · 主舞台"}'::jsonb,'[]'::jsonb,
   '[{"name":"VIP 包廂 A","seats":["23-0","23-1","23-2","23-3","23-4"]},{"name":"VIP 包廂 B","seats":["23-20","23-21","23-22","23-23","23-24"]}]'::jsonb);


-- ---------- 2. 自動排程 ----------
do $$
declare
  d          date := date '2027-03-01';
  d_end      date := date '2027-08-31';
  dow        int;
  is_weekend boolean;
  eid        bigint := 900001;
  ts         timestamptz;          -- 讓「越近的場次」排在後台越前面
  n_small    int := 0;
  n_d_day    int := 0;
  n_d_night  int := 0;
  n_e_day    int := 0;
  n_e_night  int := 0;
  n_de_day   int := 0;
  n_de_night int := 0;
  n_club     int := 0;
  sale_txt   text;

  small_names   text[] := array['小型偶像簽唱握手會','小型女團表演','沉浸式特展','4D 沉浸式體驗','裸視 3D 體驗會','運動賽事轉播（3D 沉浸）'];
  small_cats    text[] := array['見面會','見面會','特展','3D 場域','3D 場域','3D 場域'];

  d_day_names   text[] := array['沉浸景觀餐廳 × Coffee Rave','Coffee & Tea Rave DJ Show','XR 影棚拍攝節目'];
  d_night_names text[] := array['沉浸音樂餐廳 Live House','經典藝人駐唱之夜','斜槓藝人 × 舞團之夜','全息投影表演','虛擬歌手演唱會','VIP KTV 包場之夜'];

  e_day_names   text[] := array['震撼場景：星際航行','震撼場景：環球郵輪','震撼場景：極光','音樂祭：演唱會畫面','懷舊歌曲系列','運動賽事轉播','沉浸互動：小梅的奇幻冒險','沉浸互動：星球樂園'];
  e_night_names text[] := array['舞台競賽：國標舞','舞台競賽：WCS 西岸搖擺舞','達人魔幻秀','舞蹈表演：知名舞團','爵士之夜','綜藝表演：脫口秀直播','情境饗宴：古堡莊園'];

  de_day_names   text[] := array['吉米舞台劇','妖怪森林','故事工廠舞台劇','山海秘境 - 神獸學院','夢幻島','數位沙灘海島節','霓虹東京 - 賽博極樂','魔幻馬戲特技劇場','LED 光舞劇場','日漫主題秀 - 鬼滅之刃','美漫主題秀','粉絲見面會'];
  de_night_names text[] := array['K-POP 藝人演唱會','J-POP 藝人演唱會','華人藝人演唱會','歐美藝人演唱會','大型演唱會授權轉播','動漫電玩主題音樂會','電競主題秀','夜上海 1930 浮生若夢','大唐不夜城 - 龍影霓裳','東方神秘 - 神幻煙雲','大和物語 - 藝妓與忍者之夜','國際嘉年華'];
  club_names     text[] := array['D 廳 Lounge Bar × E 廳 DJ Show','高端夜店 - Neon Night','節慶主題派對'];
begin
  while d <= d_end loop
    dow := extract(dow from d);              -- 0=日 1=一 … 5=五 6=六
    is_weekend := dow in (5,6,0);            -- 週五、六、日 為假日
    sale_txt := to_char(d - 45, 'YYYY-MM-DD') || ' ~ ' || to_char(d, 'YYYY-MM-DD');
    -- 越早的場次 created_at 越新 → 後台預設排序（created_at desc）即為「近期優先」
    ts := now() - interval '1 year' + ((d_end - d) || ' minutes')::interval;

    ------------------------------------------------------------------
    -- A / B / C 廳（150 人）：每天三場，節目輪替
    ------------------------------------------------------------------
    for i in 1..3 loop
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (
        eid,
        small_names[(n_small % array_length(small_names,1)) + 1],
        (array['A 廳','B 廳','C 廳'])[i] || ' · 微風廣場 9F',
        9000 + i,
        to_char(d,'YYYY-MM-DD'),
        case when is_weekend then '14:00' else '19:00' end,
        small_cats[(n_small % array_length(small_cats,1)) + 1],
        '售票中', sale_txt, 0, 150,
        jsonb_build_array(
          jsonb_build_object('n','自由席','p',480,'unit','seat','seats', gen_seats(0,9,0,14))
        ),
        '[]'::jsonb,
        '容納約 150 人的沉浸小廳，適合近距離互動演出。', '', '', ts
      );
      eid := eid + 1; n_small := n_small + 1;
    end loop;

    if not is_weekend then
      ----------------------------------------------------------------
      -- 平日（一～四）：D 廳 200 人、E 廳 400 人，各自日間 + 晚間
      ----------------------------------------------------------------
      -- D 廳 日間 11:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, d_day_names[(n_d_day % array_length(d_day_names,1)) + 1],
        'D 廳 · 微風廣場 9F', 9004, to_char(d,'YYYY-MM-DD'), '11:00', '沉浸場域', '售票中', sale_txt, 0, 200,
        jsonb_build_array(
          jsonb_build_object('n','VIP 卡座（整席）','p',2800,'unit','box','seats',
            gen_seats(9,9,0,3) || gen_seats(9,9,16,19)),
          jsonb_build_object('n','景觀席','p',680,'unit','seat','seats',
            gen_seats(0,8,0,19) || gen_seats(9,9,4,15))
        ),
        '[]'::jsonb, '沉浸景觀餐廳結合 Coffee & Tea Rave DJ Show，適合商務與社交。', '', '', ts);
      eid := eid + 1; n_d_day := n_d_day + 1;

      -- D 廳 晚間 19:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, d_night_names[(n_d_night % array_length(d_night_names,1)) + 1],
        'D 廳 · 微風廣場 9F', 9004, to_char(d,'YYYY-MM-DD'), '19:00', '沉浸場域', '售票中', sale_txt, 0, 200,
        jsonb_build_array(
          jsonb_build_object('n','VIP 卡座（整席）','p',3800,'unit','box','seats',
            gen_seats(9,9,0,3) || gen_seats(9,9,16,19)),
          jsonb_build_object('n','搖滾區','p',980,'unit','seat','seats', gen_seats(0,3,0,19)),
          jsonb_build_object('n','一般席','p',880,'unit','seat','seats',
            gen_seats(4,8,0,19) || gen_seats(9,9,4,15))
        ),
        '[]'::jsonb, '沉浸音樂餐廳 Live House，駐唱、舞團、DJ 與全息投影演出。', '', '', ts);
      eid := eid + 1; n_d_night := n_d_night + 1;

      -- E 廳 日間 11:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, e_day_names[(n_e_day % array_length(e_day_names,1)) + 1],
        'E 廳 · 微風廣場 9F', 9005, to_char(d,'YYYY-MM-DD'), '11:00', '3D 場域', '售票中', sale_txt, 0, 400,
        jsonb_build_array(
          jsonb_build_object('n','VIP 包廂（整間）','p',6800,'unit','box','seats',
            gen_seats(15,15,0,4) || gen_seats(15,15,20,24)),
          jsonb_build_object('n','前排席','p',1080,'unit','seat','seats', gen_seats(0,3,0,24)),
          jsonb_build_object('n','一般席','p',880,'unit','seat','seats',
            gen_seats(4,14,0,24) || gen_seats(15,15,5,19))
        ),
        '[]'::jsonb, 'LED 背景屏與巨型 Dome 投影打造的沉浸主題場景。', '', '', ts);
      eid := eid + 1; n_e_day := n_e_day + 1;

      -- E 廳 晚間 19:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, e_night_names[(n_e_night % array_length(e_night_names,1)) + 1],
        'E 廳 · 微風廣場 9F', 9005, to_char(d,'YYYY-MM-DD'), '19:00', '沉浸場域', '售票中', sale_txt, 0, 400,
        jsonb_build_array(
          jsonb_build_object('n','VIP 包廂（整間）','p',9800,'unit','box','seats',
            gen_seats(15,15,0,4) || gen_seats(15,15,20,24)),
          jsonb_build_object('n','VIP 席','p',1880,'unit','seat','seats', gen_seats(0,3,0,24)),
          jsonb_build_object('n','A 區','p',1480,'unit','seat','seats', gen_seats(4,9,0,24)),
          jsonb_build_object('n','B 區','p',1280,'unit','seat','seats',
            gen_seats(10,14,0,24) || gen_seats(15,15,5,19))
        ),
        '[]'::jsonb, '舞台競賽、達人魔幻秀與爵士之夜，沉浸主題餐廳同步供餐。', '', '', ts);
      eid := eid + 1; n_e_night := n_e_night + 1;

    else
      ----------------------------------------------------------------
      -- 假日（五、六、日）：D+E 開通合併 600 人，D/E 不另外開場
      ----------------------------------------------------------------
      -- 下午場 13:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, de_day_names[(n_de_day % array_length(de_day_names,1)) + 1],
        'D+E 廳（開通）· 微風廣場 9F', 9006, to_char(d,'YYYY-MM-DD'), '13:00', '沉浸場域', '售票中', sale_txt, 0, 600,
        jsonb_build_array(
          jsonb_build_object('n','VIP 包廂（整間）','p',12800,'unit','box','seats',
            gen_seats(23,23,0,4) || gen_seats(23,23,20,24)),
          jsonb_build_object('n','VIP 席','p',2280,'unit','seat','seats', gen_seats(0,4,0,24)),
          jsonb_build_object('n','A 區','p',1880,'unit','seat','seats', gen_seats(5,14,0,24)),
          jsonb_build_object('n','B 區','p',1580,'unit','seat','seats',
            gen_seats(15,22,0,24) || gen_seats(23,23,5,19))
        ),
        '[]'::jsonb, 'D+E 廳開通的高階 XR 虛實數位表演藝術殿堂。', '', '', ts);
      eid := eid + 1; n_de_day := n_de_day + 1;

      -- 晚間場 19:00
      insert into public.events
        (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
      values (eid, de_night_names[(n_de_night % array_length(de_night_names,1)) + 1],
        'D+E 廳（開通）· 微風廣場 9F', 9006, to_char(d,'YYYY-MM-DD'), '19:00', '沉浸場域', '售票中', sale_txt, 0, 600,
        jsonb_build_array(
          jsonb_build_object('n','VIP 包廂（整間）','p',18800,'unit','box','seats',
            gen_seats(23,23,0,4) || gen_seats(23,23,20,24)),
          jsonb_build_object('n','VIP 席','p',3280,'unit','seat','seats', gen_seats(0,4,0,24)),
          jsonb_build_object('n','A 區','p',2680,'unit','seat','seats', gen_seats(5,14,0,24)),
          jsonb_build_object('n','B 區','p',2280,'unit','seat','seats',
            gen_seats(15,22,0,24) || gen_seats(23,23,5,19))
        ),
        '[]'::jsonb, '藝人演唱會、大型授權轉播、主題音樂祭與派對。', '', '', ts);
      eid := eid + 1; n_de_night := n_de_night + 1;

      -- 夜店場 22:30（僅週五、六）
      if dow in (5,6) then
        insert into public.events
          (id,name,venue,venue_id,show_date,show_time,cat,status,sale,sold,cap,tickets,sold_seats,intro,yt,img,created_at)
        values (eid, club_names[(n_club % array_length(club_names,1)) + 1],
          'D+E 廳（開通）· 微風廣場 9F', 9006, to_char(d,'YYYY-MM-DD'), '22:30', '派對', '售票中', sale_txt, 0, 600,
          jsonb_build_array(
            jsonb_build_object('n','VIP 包廂（整間）','p',9800,'unit','box','seats',
              gen_seats(23,23,0,4) || gen_seats(23,23,20,24)),
            jsonb_build_object('n','入場席','p',1200,'unit','seat','seats',
              gen_seats(0,22,0,24) || gen_seats(23,23,5,19))
          ),
          '[]'::jsonb, 'D 廳 Lounge Bar + E 廳 Live House／DJ Show，半隔開通、各有曲風互不干擾。', '', '', ts);
        eid := eid + 1; n_club := n_club + 1;
      end if;
    end if;

    d := d + 1;
  end loop;

  raise notice '已產生 % 場次', eid - 900001;
end $$;


-- ---------- 3. 校正容量 ----------
update public.events e
   set cap = (select coalesce(sum(jsonb_array_length(t->'seats')),0)
              from jsonb_array_elements(e.tickets) t)
 where e.id between 900001 and 999999;


-- ---------- 4. 檢視結果 ----------
select
  count(*)                                                as 總場次,
  count(*) filter (where venue_id between 9001 and 9003)  as "ABC 小廳",
  count(*) filter (where venue_id = 9004)                 as "D 廳",
  count(*) filter (where venue_id = 9005)                 as "E 廳",
  count(*) filter (where venue_id = 9006)                 as "D+E 開通",
  min(show_date) as 起, max(show_date) as 迄
from public.events where id between 900001 and 999999;

-- 各廳容量檢查（應為 150 / 200 / 400 / 600）
select v.name as 場地, min(e.cap) as 最小容量, max(e.cap) as 最大容量, count(*) as 場次
from public.events e join public.venues v on v.id = e.venue_id
where e.id between 900001 and 999999
group by v.name order by v.name;
