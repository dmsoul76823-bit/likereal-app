-- ============================================================
--  節目影音：自動播放開關
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

alter table public.program_art
  add column if not exists autoplay boolean default true;   -- 進入節目介紹頁時是否自動播放

comment on column public.program_art.autoplay is
  '開啟＝進入節目介紹頁自動播放（依瀏覽器規定會先靜音，使用者可點「開啟聲音」）；關閉＝顯示主視覺與播放鍵，由使用者手動播放';

select name,
       case when coalesce(yt_id,'')<>''    then '✓' else '' end as YouTube,
       case when coalesce(video_url,'')<>'' then '✓' else '' end as 影片檔,
       is_live  as 直播中,
       autoplay as 自動播放
from public.program_art
order by name;
