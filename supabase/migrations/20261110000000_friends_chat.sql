-- 我的健身 · 好友、聊天、隐私设置（3.1.0）
-- 内容：
--   * friendships       好友关系与好友申请（pending = 申请中，accepted = 已是好友；拒绝/取消/删除好友 = 删掉这一行）
--   * messages          好友之间的聊天消息，只保留 90 天（每天自动清理一次，超过 90 天的也读不到）
--   * privacy_settings  每个人自己的隐私设置：好友能看到我的哪些运动数据
--   * friend_codes      「扫一扫加好友」用的随机码，10 分钟有效
--   * 一组函数（RPC）：搜索用户、发申请、通过申请、删除好友、好友总览、标记已读、
--     生成/使用二维码、按隐私设置读取好友的运动记录
-- 约定：
--   * 这次只新增表和函数，不改动任何已有的表、数据和权限规则。
--   * 别人的资料和运动数据不开放直接读表，统一走函数，函数里先确认「是好友」再按对方的隐私设置给数据。
--   * 好友关系的增删改也只能走函数，客户端不能直接写表。

-- ---------------------------------------------------------------------------
-- 内部工具（不对外暴露的 schema）
-- ---------------------------------------------------------------------------
create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- 好友关系
-- ---------------------------------------------------------------------------
create table public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references auth.users (id) on delete cascade,   -- 发起申请的人
  addressee_id  uuid not null references auth.users (id) on delete cascade,   -- 收到申请的人
  status        text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  constraint friendships_not_self check (requester_id <> addressee_id)
);
-- 两个人之间最多一行（不分谁先加的谁）
create unique index friendships_pair_key
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;
-- 只能看到和自己有关的行；增删改一律走下面的函数
create policy friendships_select_mine on public.friendships
  for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));
revoke all on public.friendships from anon, authenticated;
grant select on public.friendships to authenticated;

-- 两个人是不是好友（已通过）
create or replace function private.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b) or (f.requester_id = b and f.addressee_id = a))
  );
$$;
revoke all on function private.are_friends(uuid, uuid) from public, anon;
grant execute on function private.are_friends(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 聊天消息
-- ---------------------------------------------------------------------------
create table public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references auth.users (id) on delete cascade,
  receiver_id  uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now(),
  read_at      timestamptz,
  constraint messages_not_self check (sender_id <> receiver_id)
);
create index messages_pair_idx
  on public.messages (least(sender_id, receiver_id), greatest(sender_id, receiver_id), created_at desc);
create index messages_unread_idx on public.messages (receiver_id, sender_id) where read_at is null;
create index messages_created_idx on public.messages (created_at);

alter table public.messages enable row level security;
-- 只能读自己发的或发给自己的，而且只读得到 90 天内的
create policy messages_select_mine on public.messages
  for select to authenticated
  using (
    (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()))
    and created_at > now() - interval '90 days'
  );
-- 只能以自己的名义发，而且对方必须是好友
create policy messages_insert_to_friend on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select private.are_friends(sender_id, receiver_id))
  );
-- 客户端只能填这四列；发送时间、已读时间由数据库决定
revoke all on public.messages from anon, authenticated;
grant select on public.messages to authenticated;
grant insert (id, sender_id, receiver_id, body) on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- 隐私设置（没有这一行 = 全部用默认值）
-- ---------------------------------------------------------------------------
create table public.privacy_settings (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  -- 好友能看到最近多少天的记录；0 = 不限
  history_days     integer not null default 30 check (history_days in (0, 7, 30, 90)),
  show_workouts    boolean not null default true,    -- 训练记录：哪天练了、练的什么
  show_duration    boolean not null default true,    -- 训练时长
  show_exercises   boolean not null default true,    -- 训练动作：每次练了哪些动作
  show_volume      boolean not null default true,    -- 具体运动量：组数、每组重量和次数、总容量
  show_body_weight boolean not null default false,   -- 体重记录
  updated_at       timestamptz not null default now()
);

create trigger privacy_settings_set_updated_at
  before update on public.privacy_settings
  for each row execute function public.set_updated_at();

alter table public.privacy_settings enable row level security;
create policy privacy_settings_own on public.privacy_settings
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.privacy_settings from anon;

-- ---------------------------------------------------------------------------
-- 扫码加好友用的随机码：只通过函数读写
-- ---------------------------------------------------------------------------
create table public.friend_codes (
  code        text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index friend_codes_user_idx on public.friend_codes (user_id);

alter table public.friend_codes enable row level security;   -- 不建任何策略 = 客户端完全读写不到
revoke all on public.friend_codes from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 函数：搜索用户（按用户名或昵称，模糊匹配，最多 20 个，不含自己）
-- relation：none 陌生人 / friend 已是好友 / outgoing 我已发申请 / incoming 对方已向我发申请
-- ---------------------------------------------------------------------------
create or replace function public.search_users(p_query text)
returns table (
  id uuid, username text, display_name text, avatar_kind text, avatar_ref text, relation text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  q  text := btrim(coalesce(p_query, ''));
  pat text;
begin
  if me is null or q = '' then
    return;
  end if;
  q := left(q, 40);
  if left(q, 1) = '@' then
    q := substr(q, 2);
  end if;
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    select p.id, p.username, p.display_name, p.avatar_kind, p.avatar_ref,
           case
             when f.id is null then 'none'
             when f.status = 'accepted' then 'friend'
             when f.requester_id = me then 'outgoing'
             else 'incoming'
           end
    from public.profiles p
    left join public.friendships f
      on (f.requester_id = me and f.addressee_id = p.id) or (f.requester_id = p.id and f.addressee_id = me)
    where p.id <> me
      and (p.username ilike pat or p.display_name ilike pat)
    order by (lower(p.username) = lower(q) or lower(p.display_name) = lower(q)) desc, p.username
    limit 20;
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：发送好友申请。返回 friend（对方早就向我发过申请，直接成为好友）或 outgoing（已发出）
-- ---------------------------------------------------------------------------
create or replace function public.send_friend_request(p_target uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  f  public.friendships;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if p_target is null or p_target = me then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.profiles where id = p_target) then
    raise exception 'user_not_found';
  end if;

  select * into f from public.friendships
  where (requester_id = me and addressee_id = p_target) or (requester_id = p_target and addressee_id = me);

  if found then
    if f.status = 'accepted' then return 'friend'; end if;
    if f.requester_id = me then return 'outgoing'; end if;
    update public.friendships set status = 'accepted', responded_at = now() where id = f.id;
    return 'friend';
  end if;

  insert into public.friendships (requester_id, addressee_id) values (me, p_target);
  return 'outgoing';
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：通过别人发给我的好友申请
-- ---------------------------------------------------------------------------
create or replace function public.accept_friend_request(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.friendships
  set status = 'accepted', responded_at = now()
  where id = p_request and addressee_id = auth.uid() and status = 'pending';
  if not found then raise exception 'request_not_found'; end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：断开和某人的关系。拒绝申请、撤回申请、删除好友都用它。
-- 删除好友时两人之间的聊天记录一并清掉。
-- ---------------------------------------------------------------------------
create or replace function public.remove_friend(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in'; end if;
  delete from public.friendships
  where (requester_id = me and addressee_id = p_other) or (requester_id = p_other and addressee_id = me);
  delete from public.messages
  where (sender_id = me and receiver_id = p_other) or (sender_id = p_other and receiver_id = me);
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：好友总览。一次拿到所有好友和申请，带对方资料、最后一条消息、未读数。
-- ---------------------------------------------------------------------------
create or replace function public.friends_overview()
returns table (
  friendship_id uuid, user_id uuid, username text, display_name text, avatar_kind text, avatar_ref text,
  relation text, since timestamptz, last_body text, last_at timestamptz, last_from_me boolean, unread integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    f.id, p.id, p.username, p.display_name, p.avatar_kind, p.avatar_ref,
    case
      when f.status = 'accepted' then 'friend'
      when f.requester_id = auth.uid() then 'outgoing'
      else 'incoming'
    end,
    coalesce(f.responded_at, f.created_at),
    lm.body, lm.created_at, lm.sender_id = auth.uid(),
    coalesce(u.n, 0)::integer
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  left join lateral (
    select m.body, m.created_at, m.sender_id
    from public.messages m
    where f.status = 'accepted'
      and least(m.sender_id, m.receiver_id) = least(f.requester_id, f.addressee_id)
      and greatest(m.sender_id, m.receiver_id) = greatest(f.requester_id, f.addressee_id)
      and m.created_at > now() - interval '90 days'
    order by m.created_at desc
    limit 1
  ) lm on true
  left join lateral (
    select count(*) as n
    from public.messages m
    where f.status = 'accepted'
      and m.receiver_id = auth.uid() and m.sender_id = p.id and m.read_at is null
      and m.created_at > now() - interval '90 days'
  ) u on true
  where f.requester_id = auth.uid() or f.addressee_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 函数：把某个好友发给我的消息全部标为已读
-- ---------------------------------------------------------------------------
create or replace function public.mark_chat_read(p_friend uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.messages
  set read_at = now()
  where receiver_id = auth.uid() and sender_id = p_friend and read_at is null;
$$;

-- ---------------------------------------------------------------------------
-- 函数：生成我的加好友二维码（随机码，10 分钟有效；重新生成会作废上一个）
-- ---------------------------------------------------------------------------
create or replace function public.create_friend_code()
returns table (code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_code text := replace(gen_random_uuid()::text, '-', '');
  v_exp  timestamptz := now() + interval '10 minutes';
begin
  if me is null then raise exception 'not_signed_in'; end if;
  -- 换新码时让我之前还没过期的码立刻失效（过期的行由每天的清理任务删掉）
  update public.friend_codes c set expires_at = now() where c.user_id = me and c.expires_at > now();
  insert into public.friend_codes (code, user_id, expires_at) values (v_code, me, v_exp);
  return query select v_code, v_exp;
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：扫到二维码后，先看看是谁（过期或无效会报错 code_expired）
-- ---------------------------------------------------------------------------
create or replace function public.lookup_friend_code(p_code text)
returns table (
  id uuid, username text, display_name text, avatar_kind text, avatar_ref text, relation text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me    uuid := auth.uid();
  owner uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  select c.user_id into owner from public.friend_codes c
  where c.code = p_code and c.expires_at > now();
  if owner is null then raise exception 'code_expired'; end if;
  return query
    select p.id, p.username, p.display_name, p.avatar_kind, p.avatar_ref,
           case
             when p.id = me then 'self'
             when f.id is null then 'none'
             when f.status = 'accepted' then 'friend'
             when f.requester_id = me then 'outgoing'
             else 'incoming'
           end
    from public.profiles p
    left join public.friendships f
      on (f.requester_id = me and f.addressee_id = p.id) or (f.requester_id = p.id and f.addressee_id = me)
    where p.id = owner;
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：用二维码加好友。对方当面出示了二维码就算同意，所以直接成为好友，不用再等对方通过。
-- 返回对方的用户 id。
-- ---------------------------------------------------------------------------
create or replace function public.add_friend_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me    uuid := auth.uid();
  owner uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  select c.user_id into owner from public.friend_codes c
  where c.code = p_code and c.expires_at > now();
  if owner is null then raise exception 'code_expired'; end if;
  if owner = me then raise exception 'invalid_target'; end if;

  update public.friendships
  set status = 'accepted', responded_at = now()
  where ((requester_id = me and addressee_id = owner) or (requester_id = owner and addressee_id = me))
    and status = 'pending';
  if not found then
    insert into public.friendships (requester_id, addressee_id, status, responded_at)
    values (me, owner, 'accepted', now())
    on conflict do nothing;
  end if;
  return owner;
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数：查看好友最近的运动记录。先确认是好友，再按对方的隐私设置给数据；
-- 对方设为「仅自己可见」的部分，这里根本不会返回。
-- ---------------------------------------------------------------------------
create or replace function public.get_friend_activity(p_friend uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me       uuid := auth.uid();
  s        public.privacy_settings;
  v_from   date;
  v_today  date := (now() at time zone 'Asia/Shanghai')::date;
  v_workouts jsonb := null;
  v_weights  jsonb := null;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if not private.are_friends(me, p_friend) then raise exception 'not_friends'; end if;

  select * into s from public.privacy_settings where user_id = p_friend;
  if not found then
    s.history_days := 30;
    s.show_workouts := true;
    s.show_duration := true;
    s.show_exercises := true;
    s.show_volume := true;
    s.show_body_weight := false;
  end if;
  v_from := case when s.history_days = 0 then date '1970-01-01' else v_today - (s.history_days - 1) end;

  if s.show_workouts then
    select coalesce(jsonb_agg(x.j order by x.started_at desc), '[]'::jsonb) into v_workouts
    from (
      select w.started_at,
        jsonb_strip_nulls(jsonb_build_object(
          'id', w.id,
          'name', w.name,
          'local_date', w.local_date,
          'started_at', w.started_at,
          'duration_min', case when s.show_duration
            then greatest(0, round(extract(epoch from (w.ended_at - w.started_at)) / 60))::integer end,
          'set_count', case when s.show_volume then (
            select count(*) from public.workout_exercises we
            join public.workout_sets ws on ws.workout_exercise_id = we.id
            where we.workout_id = w.id and we.deleted_at is null
              and ws.deleted_at is null and ws.completed and ws.kind <> 'warmup') end,
          'volume_kg', case when s.show_volume then (
            select coalesce(sum(coalesce(ws.weight_kg, 0) * coalesce(ws.reps, 0)), 0) from public.workout_exercises we
            join public.workout_sets ws on ws.workout_exercise_id = we.id
            where we.workout_id = w.id and we.deleted_at is null
              and ws.deleted_at is null and ws.completed and ws.kind <> 'warmup') end,
          'exercises', case when s.show_exercises then (
            select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
              'name', e.name_zh,
              'body_part', e.body_part,
              'tracking_type', e.tracking_type,
              'sets', case when s.show_volume then (
                select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                  'kind', ws.kind,
                  'weight_kg', ws.weight_kg,
                  'reps', ws.reps,
                  'duration_sec', ws.duration_sec,
                  'distance_m', ws.distance_m
                )) order by ws.set_index), '[]'::jsonb)
                from public.workout_sets ws
                where ws.workout_exercise_id = we.id and ws.deleted_at is null and ws.completed) end
            )) order by we.position), '[]'::jsonb)
            from public.workout_exercises we
            join public.exercises e on e.id = we.exercise_id
            where we.workout_id = w.id and we.deleted_at is null) end
        )) as j
      from public.workouts w
      where w.user_id = p_friend and w.deleted_at is null and w.ended_at is not null
        and w.local_date >= v_from
      order by w.started_at desc
      limit 60
    ) x;
  end if;

  if s.show_body_weight then
    select coalesce(jsonb_agg(jsonb_build_object('date', b.date, 'weight_kg', b.weight_kg) order by b.date desc), '[]'::jsonb)
    into v_weights
    from (
      select bm.date, bm.weight_kg from public.body_metrics bm
      where bm.user_id = p_friend and bm.deleted_at is null and bm.weight_kg is not null
        and bm.date >= v_from
      order by bm.date desc
      limit 30
    ) b;
  end if;

  return jsonb_build_object(
    'history_days', s.history_days,
    'show_workouts', s.show_workouts,
    'show_duration', s.show_duration,
    'show_exercises', s.show_exercises,
    'show_volume', s.show_volume,
    'show_body_weight', s.show_body_weight,
    'workouts', v_workouts,
    'body_weight', v_weights
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 函数权限：只给已登录用户
-- ---------------------------------------------------------------------------
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.search_users(text)',
    'public.send_friend_request(uuid)',
    'public.accept_friend_request(uuid)',
    'public.remove_friend(uuid)',
    'public.friends_overview()',
    'public.mark_chat_read(uuid)',
    'public.create_friend_code()',
    'public.lookup_friend_code(text)',
    'public.add_friend_by_code(text)',
    'public.get_friend_activity(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 实时推送：新消息、好友申请一到，App 立刻收到（仍受上面的权限规则约束）
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.messages, public.friendships;

-- ---------------------------------------------------------------------------
-- 每天自动清理：超过 90 天的聊天记录、过期的二维码
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'purge-old-chat',
  '20 19 * * *',   -- 每天 19:20 UTC = 北京时间凌晨 3:20
  $$
    delete from public.messages where created_at < now() - interval '90 days';
    delete from public.friend_codes where expires_at < now();
  $$
);
