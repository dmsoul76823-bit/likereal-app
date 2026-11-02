-- ============================================================
--  節目影音：影片檔、YouTube 崁入、直播連結、直播中狀態
--  在 Supabase → SQL Editor 貼上執行
-- ============================================================

alter table public.program_art add column if not exists video_url  text;   -- 影片檔網址（mp4/webm）
alter table public.program_art add column if not exists yt_id      text;   -- YouTube 影片 ID
alter table public.program_art add column if not exists live_url   text;   -- 直播連結（YouTube 直播 ID 或完整網址）
alter table public.program_art add column if not exists is_live    boolean default false;  -- 是否直播中
alter table public.program_art add column if not exists live_title text;   -- 直播標題（選填）

comment on column public.program_art.video_url  is '影片檔網址，例如 https://.../teaser.mp4';
comment on column public.program_art.yt_id      is 'YouTube 影片 ID，例如 LXb3EKWsInQ';
comment on column public.program_art.live_url   is '直播來源：YouTube 直播 ID 或完整網址';
comment on column public.program_art.is_live    is '打開後前台會顯示 LIVE 標記並優先播放直播';

select name,
       case when coalesce(video_url,'')<>'' then '✓' else '' end as 影片檔,
       case when coalesce(yt_id,'')<>''     then '✓' else '' end as YouTube,
       case when coalesce(live_url,'')<>''  then '✓' else '' end as 直播,
       is_live as 直播中
from public.program_art
order by name;
