-- ============================================================
-- Project UNKNOWN ARG — Supabase Schema
-- Supabase ダッシュボード > SQL Editor に貼り付けて実行
-- ============================================================

-- 投稿テーブル
create table if not exists posts (
  id          bigint generated always as identity primary key,
  actor_idx   int not null default -1,         -- -1 = 一般ユーザー投稿
  user_id     uuid references auth.users(id),  -- ユーザー投稿の場合
  user_name   text,
  user_handle text,
  user_avatar text,
  body        text not null,
  cipher      boolean not null default false,
  solved      boolean not null default false,
  likes       int not null default 0,
  rp          int not null default 0,
  reacts      text[] not null default '{}',
  is_alert    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- リプライテーブル
create table if not exists replies (
  id         bigint generated always as identity primary key,
  post_id    bigint not null references posts(id) on delete cascade,
  actor_idx  int not null default -1,
  user_id    uuid references auth.users(id),
  user_name  text,
  user_handle text,
  body       text not null,
  cipher     boolean not null default false,
  is_bot     boolean not null default false,
  created_at timestamptz not null default now()
);

-- Botトリガーテーブル
create table if not exists triggers (
  id         bigint generated always as identity primary key,
  word       text not null,
  reply      text not null,
  actor_idx  int not null default 0,
  created_at timestamptz not null default now()
);

-- チャンネルテーブル
create table if not exists channels (
  id         text primary key,
  name       text not null,
  description text not null default '',
  pinned     boolean not null default false,
  created_at timestamptz not null default now()
);

-- チャンネルメッセージ
create table if not exists channel_messages (
  id          bigint generated always as identity primary key,
  channel_id  text not null references channels(id) on delete cascade,
  user_id     uuid references auth.users(id),
  user_name   text not null,
  user_handle text not null,
  user_avatar text,
  body        text not null,
  created_at  timestamptz not null default now()
);

-- クリップ（ユーザーごと）
create table if not exists clips (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  post_id    bigint not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, post_id)
);

-- ドライブファイル（ユーザーごと）
create table if not exists drive_files (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  content     text not null,
  size        int not null default 0,
  created_at  timestamptz not null default now()
);

-- 通知
create table if not exists notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null, -- 'reply' | 'like' | 'follow' | 'system'
  actor_idx   int,
  actor_name  text,
  body        text not null,
  sub         text not null default '',
  is_read     boolean not null default false,
  post_id     bigint references posts(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- いいね（重複防止）
create table if not exists likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id bigint not null references posts(id) on delete cascade,
  primary key (user_id, post_id)
);

-- ============================================================
-- Row Level Security
-- ============================================================

alter table posts            enable row level security;
alter table replies          enable row level security;
alter table triggers         enable row level security;
alter table channels         enable row level security;
alter table channel_messages enable row level security;
alter table clips            enable row level security;
alter table drive_files      enable row level security;
alter table notifications    enable row level security;
alter table likes            enable row level security;

-- posts: 誰でも読める、ログイン済みは書ける
create policy "posts_read"   on posts for select using (true);
create policy "posts_insert" on posts for insert with check (auth.uid() is not null);
create policy "posts_update" on posts for update using (auth.uid() is not null);

-- replies: 誰でも読める、ログイン済みは書ける
create policy "replies_read"   on replies for select using (true);
create policy "replies_insert" on replies for insert with check (auth.uid() is not null);

-- triggers: 誰でも読める（管理者のみ書けるが簡易実装で全員可）
create policy "triggers_read"   on triggers for select using (true);
create policy "triggers_insert" on triggers for insert with check (auth.uid() is not null);
create policy "triggers_delete" on triggers for delete using (auth.uid() is not null);

-- channels: 誰でも読める
create policy "channels_read" on channels for select using (true);

-- channel_messages: 誰でも読める、ログイン済みは書ける
create policy "ch_msg_read"   on channel_messages for select using (true);
create policy "ch_msg_insert" on channel_messages for insert with check (auth.uid() is not null);

-- clips: 自分のだけ
create policy "clips_read"   on clips for select  using (auth.uid() = user_id);
create policy "clips_insert" on clips for insert  with check (auth.uid() = user_id);
create policy "clips_delete" on clips for delete  using (auth.uid() = user_id);

-- drive: 自分のだけ
create policy "drive_read"   on drive_files for select  using (auth.uid() = user_id);
create policy "drive_insert" on drive_files for insert  with check (auth.uid() = user_id);
create policy "drive_delete" on drive_files for delete  using (auth.uid() = user_id);

-- notifications: 自分のだけ
create policy "notif_read"   on notifications for select using (auth.uid() = user_id);
create policy "notif_update" on notifications for update using (auth.uid() = user_id);
create policy "notif_insert" on notifications for insert with check (true); -- bot/system用

-- likes: 自分のだけ
create policy "likes_read"   on likes for select  using (true);
create policy "likes_insert" on likes for insert  with check (auth.uid() = user_id);
create policy "likes_delete" on likes for delete  using (auth.uid() = user_id);

-- ============================================================
-- Realtime 有効化
-- ============================================================
alter publication supabase_realtime add table posts;
alter publication supabase_realtime add table replies;
alter publication supabase_realtime add table channel_messages;
alter publication supabase_realtime add table notifications;

-- ============================================================
-- シードデータ（ARGキャラクターの初期投稿）
-- ============================================================
insert into channels (id, name, description, pinned) values
  ('general',  'general',  'なんでも話せる場所',         false),
  ('cipher',   'cipher',   '暗号解読専用チャンネル',      true),
  ('coords',   '座標調査',  'フィールド調査報告',          false),
  ('theories', '考察',      'ARG全体の考察・ネタバレ注意', false)
on conflict (id) do nothing;

insert into triggers (word, reply, actor_idx) values
  ('暗号',        '...お前も気づいたか。ROT3を試せ。',          0),
  ('layer2',      '正しい。次の扉はshadow.layerにある。',        2),
  ('LAYER2',      '正しい。次の扉はshadow.layerにある。',        2),
  ('hello world', '鍵を手に入れた。次のレイヤーへ進め。',        0),
  ('shadow',      '...見つけたか。だがそこに入るには、もう一つの鍵が必要だ。', 0)
on conflict do nothing;

insert into posts (actor_idx, body, cipher, reacts) values
  (0, E'KHOOR ZRUOG\n\n最初の鍵を見つけよ。',                                        true,  array['🔍 調査', '🔗 連鎖']),
  (1, E'北緯35.6762、東経139.6503\nこの場所に何かある。',                             false, array['📍 確認', '🔎 調査']),
  (2, E'⚠ システム警告\n01001100 01000001 01011001 01000101 01010010 00110010',       true,  array['💻 解析']),
  (3, E'【緊急】第二フェーズが開始されました。\n次のメッセージを待て。時間は限られている。', false, array['⚡ 確認', '🚨 警戒'])
on conflict do nothing;
