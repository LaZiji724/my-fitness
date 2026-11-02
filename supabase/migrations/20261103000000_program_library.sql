-- 我的健身 · 内置计划库
-- 内容：计划库三张只读表（所有登录用户可读）、计划收藏、模板动作新增「热身组 / 时长目标」、
--       计划与训练记录新增「来源计划库」标记。
-- 先执行本文件，再执行 supabase/seed/program_library.sql（动作与计划内容）。
-- 注意：必须先执行本迁移再安装新版 App，否则新版 App 同步模板/计划/训练时会因缺列而失败。

-- ---------------------------------------------------------------------------
-- 模板动作：热身组数 + 时长目标（有氧、拉伸、平板支撑等按时间的动作）
-- ---------------------------------------------------------------------------
alter table public.template_exercises
  add column if not exists warmup_sets integer not null default 0 check (warmup_sets between 0 and 10),
  add column if not exists target_duration_sec integer check (target_duration_sec is null or target_duration_sec >= 0);

-- 用户计划 / 训练记录：记录它们来自计划库里的哪个计划（不加外键：内置计划可能被更新重建）
alter table public.plans    add column if not exists source_program_id uuid;
alter table public.workouts add column if not exists source_program_id uuid;

-- ---------------------------------------------------------------------------
-- 计划库（内置内容，只读）
-- ---------------------------------------------------------------------------
create table if not exists public.programs (
  id            uuid primary key,
  slug          text not null unique,
  name          text not null,
  subtitle      text not null,
  description   text not null,
  progression   text not null,
  -- 目标分类；「新手入门 / 进阶计划」由 level 推导，「近期上新」由 is_new 推导
  category      text not null check (category in
                  ('有氧跟练', '团课计划', '瘦身减脂', '塑形美体', '增肌增重', '健康改善', '拉伸放松', '丰满翘臀')),
  level         smallint not null check (level between 1 and 3),       -- 1 初阶 2 中阶 3 高阶
  weeks         smallint not null check (weeks between 1 and 52),
  days_per_week smallint not null check (days_per_week between 1 and 7),
  minutes       smallint not null check (minutes > 0),                   -- 平均每节约多少分钟
  schedule      text not null check (char_length(schedule) = 7),        -- 周一到周日：课次 key 或 '.'（休息）
  scenes        text[] not null default '{}',
  audiences     text[] not null default '{}',
  equipment     text[] not null default '{}',
  is_new        boolean not null default false,
  featured      boolean not null default false,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists programs_category_idx on public.programs (category, sort_order);

create table if not exists public.program_sessions (
  id          uuid primary key,
  program_id  uuid not null references public.programs (id) on delete cascade,
  key         text not null,
  name        text not null,
  focus       text not null,
  minutes     smallint not null,
  position    smallint not null,
  unique (program_id, key)
);
create index if not exists program_sessions_program_idx on public.program_sessions (program_id, position);

create table if not exists public.program_session_items (
  id            uuid primary key,
  session_id    uuid not null references public.program_sessions (id) on delete cascade,
  exercise_id   uuid not null references public.exercises (id),
  position      smallint not null,
  warmup_sets   smallint not null default 0 check (warmup_sets between 0 and 10),
  sets          smallint not null check (sets between 1 and 50),
  reps_min      integer check (reps_min is null or reps_min >= 0),
  reps_max      integer check (reps_max is null or reps_max >= 0),
  duration_sec  integer check (duration_sec is null or duration_sec >= 0),
  distance_m    integer check (distance_m is null or distance_m >= 0),
  rest_sec      integer not null default 60 check (rest_sec between 0 and 3600),
  note          text
);
create index if not exists program_session_items_session_idx on public.program_session_items (session_id, position);

alter table public.programs              enable row level security;
alter table public.program_sessions      enable row level security;
alter table public.program_session_items enable row level security;

-- 只开放读取；写入只有 SQL Editor / service_role 能做（种子脚本）
drop policy if exists programs_read on public.programs;
create policy programs_read on public.programs for select to authenticated using (true);
drop policy if exists program_sessions_read on public.program_sessions;
create policy program_sessions_read on public.program_sessions for select to authenticated using (true);
drop policy if exists program_session_items_read on public.program_session_items;
create policy program_session_items_read on public.program_session_items for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- 计划收藏（随账号同步）
-- ---------------------------------------------------------------------------
create table if not exists public.favorite_programs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  program_id  uuid not null,                       -- 不加外键：内置计划重建后收藏仍然有效
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index if not exists favorite_programs_sync_idx on public.favorite_programs (user_id, updated_at);
create unique index if not exists favorite_programs_one_key
  on public.favorite_programs (user_id, program_id) where deleted_at is null;

drop trigger if exists favorite_programs_set_updated_at on public.favorite_programs;
create trigger favorite_programs_set_updated_at
  before update on public.favorite_programs
  for each row execute function public.set_updated_at();

alter table public.favorite_programs enable row level security;
drop policy if exists favorite_programs_own on public.favorite_programs;
create policy favorite_programs_own on public.favorite_programs
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
