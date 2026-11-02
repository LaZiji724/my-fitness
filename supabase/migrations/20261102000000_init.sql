-- 我的健身 · 初始数据库结构
-- 内容：表、更新时间触发器、注册自动建档、RLS 行级安全、存储桶与存储策略
-- 约定：
--   * 所有用户数据表都带 user_id（子表也带），RLS 一行规则即可。
--   * 所有可同步的表都有 created_at / updated_at / deleted_at（软删除）。
--   * id 由客户端生成 UUID（default 仅作兜底），重量统一以 kg 存储。

-- ---------------------------------------------------------------------------
-- 通用：自动维护 updated_at
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles：一人一行，id 即 auth.users.id
-- ---------------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  username        text not null,
  display_name    text not null,
  avatar_kind     text not null default 'preset' check (avatar_kind in ('preset', 'custom')),
  -- preset：预设头像编号，如 avatar_01；custom：Storage 路径 {user_id}/avatar.webp
  avatar_ref      text not null default 'avatar_01',
  weight_unit     text not null default 'kg' check (weight_unit in ('kg', 'lb')),
  default_rest_sec integer not null default 90 check (default_rest_sec between 0 and 3600),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$')
);
create unique index profiles_username_key on public.profiles (username);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- 注册成功后自动建档。客户端 signUp 时把 username / display_name / avatar_ref 放进 user metadata。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));
begin
  insert into public.profiles (id, username, display_name, avatar_kind, avatar_ref)
  values (
    new.id,
    v_username,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), v_username),
    'preset',
    coalesce(nullif(new.raw_user_meta_data ->> 'avatar_ref', ''), 'avatar_01')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- exercises：owner_id 为空 = 内置动作（所有人只读）；非空 = 用户自定义动作
-- ---------------------------------------------------------------------------
create table public.exercises (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid references auth.users (id) on delete cascade,
  slug              text,
  name_zh           text not null,
  name_en           text,
  body_part         text not null check (body_part in
                      ('chest', 'back', 'shoulders', 'arms', 'legs', 'glutes', 'core', 'cardio', 'other')),
  primary_muscles   text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  equipment         text,
  tracking_type     text not null default 'weight_reps' check (tracking_type in
                      ('weight_reps', 'bodyweight_reps', 'duration', 'distance_duration')),
  instructions_zh   text,
  image_paths       text[] not null default '{}',
  is_custom         boolean generated always as (owner_id is not null) stored,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
-- slug 仅内置动作使用（自定义动作为空，NULL 之间不冲突）；用普通唯一索引，方便种子脚本按 slug upsert
create unique index exercises_slug_key on public.exercises (slug);
create index exercises_owner_idx on public.exercises (owner_id, updated_at);
create index exercises_body_part_idx on public.exercises (body_part) where deleted_at is null;
create index exercises_updated_idx on public.exercises (updated_at);

create trigger exercises_set_updated_at
  before update on public.exercises
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 收藏动作
-- ---------------------------------------------------------------------------
create table public.favorite_exercises (
  user_id     uuid not null references auth.users (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  primary key (user_id, exercise_id)
);
create index favorite_exercises_sync_idx on public.favorite_exercises (user_id, updated_at);

create trigger favorite_exercises_set_updated_at
  before update on public.favorite_exercises
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 模板
-- ---------------------------------------------------------------------------
create table public.templates (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  note        text,
  folder      text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index templates_sync_idx on public.templates (user_id, updated_at);

create table public.template_exercises (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  template_id   uuid not null references public.templates (id) on delete cascade,
  exercise_id   uuid not null references public.exercises (id),
  position      integer not null,
  target_sets   integer not null default 3 check (target_sets between 1 and 50),
  reps_min      integer check (reps_min is null or reps_min >= 0),
  reps_max      integer check (reps_max is null or reps_max >= 0),
  rest_sec      integer check (rest_sec is null or rest_sec between 0 and 3600),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index template_exercises_sync_idx on public.template_exercises (user_id, updated_at);
create index template_exercises_template_idx on public.template_exercises (template_id, position);

-- ---------------------------------------------------------------------------
-- 计划：N 天一个循环，每天绑定一个模板或休息
-- ---------------------------------------------------------------------------
create table public.plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  cycle_days  integer not null check (cycle_days between 1 and 28),
  start_date  date not null default current_date,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index plans_sync_idx on public.plans (user_id, updated_at);
-- 同一时刻最多一个“当前计划”
create unique index plans_one_active_key on public.plans (user_id) where is_active and deleted_at is null;

create table public.plan_days (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  plan_id      uuid not null references public.plans (id) on delete cascade,
  day_index    integer not null check (day_index >= 0),
  template_id  uuid references public.templates (id) on delete set null,
  label        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index plan_days_sync_idx on public.plan_days (user_id, updated_at);
create unique index plan_days_day_key on public.plan_days (plan_id, day_index) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 训练记录
-- ---------------------------------------------------------------------------
create table public.workouts (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users (id) on delete cascade,
  name               text,
  started_at         timestamptz not null,
  ended_at           timestamptz,          -- 为空 = 进行中
  local_date         date not null,        -- 开始时间的本地日期，日历与统计按它归属
  note               text,
  source_template_id uuid references public.templates (id) on delete set null,
  plan_id            uuid references public.plans (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  constraint workouts_time_order check (ended_at is null or ended_at >= started_at)
);
create index workouts_sync_idx on public.workouts (user_id, updated_at);
create index workouts_date_idx on public.workouts (user_id, local_date) where deleted_at is null;

create table public.workout_exercises (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  workout_id  uuid not null references public.workouts (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  position    integer not null,
  note        text,
  rest_sec    integer check (rest_sec is null or rest_sec between 0 and 3600),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index workout_exercises_sync_idx on public.workout_exercises (user_id, updated_at);
create index workout_exercises_workout_idx on public.workout_exercises (workout_id, position);
create index workout_exercises_exercise_idx on public.workout_exercises (exercise_id);

create table public.workout_sets (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  workout_exercise_id uuid not null references public.workout_exercises (id) on delete cascade,
  set_index           integer not null,
  kind                text not null default 'normal' check (kind in ('normal', 'warmup', 'drop', 'failure')),
  weight_kg           numeric(7, 2) check (weight_kg is null or weight_kg >= 0),
  reps                integer check (reps is null or reps >= 0),
  duration_sec        integer check (duration_sec is null or duration_sec >= 0),
  distance_m          numeric(9, 2) check (distance_m is null or distance_m >= 0),
  rpe                 numeric(3, 1) check (rpe is null or rpe between 1 and 10),
  completed           boolean not null default false,
  completed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);
create index workout_sets_sync_idx on public.workout_sets (user_id, updated_at);
create index workout_sets_we_idx on public.workout_sets (workout_exercise_id, set_index);

-- ---------------------------------------------------------------------------
-- 身体数据（V1 只有体重）
-- ---------------------------------------------------------------------------
create table public.body_metrics (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  date        date not null,
  weight_kg   numeric(5, 2) check (weight_kg is null or weight_kg > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index body_metrics_sync_idx on public.body_metrics (user_id, updated_at);
create unique index body_metrics_day_key on public.body_metrics (user_id, date) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- updated_at 触发器（批量挂到所有同步表）
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'templates', 'template_exercises', 'plans', 'plan_days',
    'workouts', 'workout_exercises', 'workout_sets', 'body_metrics'
  ] loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.exercises          enable row level security;
alter table public.favorite_exercises enable row level security;
alter table public.templates          enable row level security;
alter table public.template_exercises enable row level security;
alter table public.plans              enable row level security;
alter table public.plan_days          enable row level security;
alter table public.workouts           enable row level security;
alter table public.workout_exercises  enable row level security;
alter table public.workout_sets       enable row level security;
alter table public.body_metrics       enable row level security;

-- profiles：只能看写自己的一行（建档由触发器完成）
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- exercises：内置动作所有登录用户可读；自定义动作只能读写自己的
create policy exercises_select on public.exercises
  for select to authenticated
  using (owner_id is null or owner_id = (select auth.uid()));
create policy exercises_insert_own on public.exercises
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy exercises_update_own on public.exercises
  for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy exercises_delete_own on public.exercises
  for delete to authenticated using (owner_id = (select auth.uid()));

-- 其余用户数据表：user_id = 当前用户
do $$
declare
  t text;
begin
  foreach t in array array[
    'favorite_exercises', 'templates', 'template_exercises', 'plans', 'plan_days',
    'workouts', 'workout_exercises', 'workout_sets', 'body_metrics'
  ] loop
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t || '_own', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 存储桶
--   avatars                头像，公开读，只能写自己目录 {user_id}/...
--   custom-exercise-images 自定义动作图片，同上
--   exercise-images        内置动作图片，公开读，只有 service_role（种子脚本）可写
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 2097152, array['image/webp', 'image/jpeg', 'image/png']),
  ('custom-exercise-images', 'custom-exercise-images', true, 5242880, array['image/webp', 'image/jpeg', 'image/png']),
  ('exercise-images', 'exercise-images', true, 2097152, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "avatars_write_own_folder_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_write_own_folder_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_write_own_folder_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "custom_images_write_own_folder_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'custom-exercise-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "custom_images_write_own_folder_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'custom-exercise-images' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'custom-exercise-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "custom_images_write_own_folder_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'custom-exercise-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
