-- 我的健身 · 激活 / 拉伸动作 + 次数/时间双计量 + 热身/放松分区
-- 内容：
--   1) exercises 新增：类型 kind、区域 region、是否左右各做 per_side、默认组数/次数/秒数
--   2) 模板动作 / 训练动作 / 计划库动作链 新增分区 section（热身 / 正式 / 放松）
--   3) 计划库分类新增「激活热身」
--   4) 用户对每个动作的「按次数 / 按时间」偏好表 exercise_prefs（随账号同步）
-- 先执行本文件，再执行 supabase/seed/program_library.sql，最后安装新版 App。
-- 注意：必须先执行本迁移再安装新版 App，否则新版 App 同步时会因缺列 / 缺表而失败。

-- ---------------------------------------------------------------------------
-- 1) exercises
-- ---------------------------------------------------------------------------
alter table public.exercises
  add column if not exists kind text not null default 'strength'
    check (kind in ('strength', 'cardio', 'activation', 'dynamic', 'stretch', 'foam')),
  add column if not exists region text
    check (region is null or region in ('neck_shoulder', 'chest_arm', 'back_core', 'hip_glute', 'leg', 'full')),
  add column if not exists per_side boolean not null default false,
  add column if not exists default_sets integer check (default_sets is null or default_sets between 1 and 50),
  add column if not exists default_reps integer check (default_reps is null or default_reps >= 0),
  add column if not exists default_seconds integer check (default_seconds is null or default_seconds >= 0);
create index if not exists exercises_kind_idx on public.exercises (kind) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 2) 分区：warmup 热身 / main 正式训练 / cooldown 放松
-- ---------------------------------------------------------------------------
alter table public.template_exercises
  add column if not exists section text not null default 'main' check (section in ('warmup', 'main', 'cooldown'));
alter table public.workout_exercises
  add column if not exists section text not null default 'main' check (section in ('warmup', 'main', 'cooldown'));
alter table public.program_session_items
  add column if not exists section text not null default 'main' check (section in ('warmup', 'main', 'cooldown'));

-- ---------------------------------------------------------------------------
-- 3) 计划库分类新增「激活热身」
-- ---------------------------------------------------------------------------
alter table public.programs drop constraint if exists programs_category_check;
alter table public.programs add constraint programs_category_check check (category in
  ('有氧跟练', '团课计划', '瘦身减脂', '塑形美体', '增肌增重', '健康改善', '激活热身', '拉伸放松', '丰满翘臀'));

-- ---------------------------------------------------------------------------
-- 4) 每个动作的计量偏好：同一个动作可以选「按次数」或「按时间」（每人各自一份）
-- ---------------------------------------------------------------------------
create table if not exists public.exercise_prefs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  exercise_id   uuid not null,                       -- 不加外键：内置动作种子重建后偏好仍然有效
  tracking_type text not null check (tracking_type in ('weight_reps', 'bodyweight_reps', 'duration', 'distance_duration')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index if not exists exercise_prefs_sync_idx on public.exercise_prefs (user_id, updated_at);
create unique index if not exists exercise_prefs_one_key
  on public.exercise_prefs (user_id, exercise_id) where deleted_at is null;

drop trigger if exists exercise_prefs_set_updated_at on public.exercise_prefs;
create trigger exercise_prefs_set_updated_at
  before update on public.exercise_prefs
  for each row execute function public.set_updated_at();

alter table public.exercise_prefs enable row level security;
drop policy if exists exercise_prefs_own on public.exercise_prefs;
create policy exercise_prefs_own on public.exercise_prefs
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
