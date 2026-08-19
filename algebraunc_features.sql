-- ============================================================
-- AlgebraUNC Rooms Upgrade
-- Run ONCE in Supabase SQL Editor.
--
-- Adds:
--   * Main public room
--   * exactly one DM per pair of users
--   * get/create DM by username
--   * safe group-chat creation
--   * realtime membership updates
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. Store the canonical pair on direct-message conversations.
-- ------------------------------------------------------------

alter table public.conversations
  add column if not exists dm_user_a uuid references public.profiles(id) on delete cascade;

alter table public.conversations
  add column if not exists dm_user_b uuid references public.profiles(id) on delete cascade;

-- Backfill any existing 2-person non-group conversations.
with pairs as (
  select
    c.id,
    (array_agg(cm.user_id order by cm.user_id))[1] as user_a,
    (array_agg(cm.user_id order by cm.user_id))[2] as user_b
  from public.conversations c
  join public.conversation_members cm
    on cm.conversation_id = c.id
  where c.is_group = false
  group by c.id
  having count(*) = 2
)
update public.conversations c
set
  dm_user_a = p.user_a,
  dm_user_b = p.user_b
from pairs p
where c.id = p.id
  and (c.dm_user_a is null or c.dm_user_b is null);

-- If testing created duplicate DMs already, keep one and remove the rest.
-- Cascading FKs also remove the duplicate conversation's temporary messages.
with ranked as (
  select
    id,
    row_number() over (
      partition by dm_user_a, dm_user_b
      order by created_at asc, id asc
    ) as rn
  from public.conversations
  where is_group = false
    and dm_user_a is not null
    and dm_user_b is not null
)
delete from public.conversations
where id in (
  select id from ranked where rn > 1
);

create unique index if not exists conversations_one_dm_per_pair
on public.conversations(dm_user_a, dm_user_b)
where is_group = false
  and dm_user_a is not null
  and dm_user_b is not null;

-- ------------------------------------------------------------
-- 2. Main room. Every browser joins this room when AlgebraUNC opens.
-- ------------------------------------------------------------

create or replace function public.ensure_main_conversation()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  main_id constant uuid := '00000000-0000-0000-0000-000000000001'::uuid;
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1 from public.profiles where id = me
  ) then
    raise exception 'Create a username first';
  end if;

  insert into public.conversations (
    id,
    name,
    is_group,
    created_by,
    dm_user_a,
    dm_user_b
  )
  values (
    main_id,
    'Main',
    true,
    me,
    null,
    null
  )
  on conflict (id) do update
    set name = 'Main',
        is_group = true,
        dm_user_a = null,
        dm_user_b = null;

  insert into public.conversation_members(conversation_id, user_id)
  values (main_id, me)
  on conflict do nothing;

  return main_id;
end;
$$;

revoke all on function public.ensure_main_conversation() from public;
grant execute on function public.ensure_main_conversation() to authenticated;

-- ------------------------------------------------------------
-- 3. One and only one DM per user pair.
-- ------------------------------------------------------------

create or replace function public.get_or_create_dm(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  a uuid;
  b uuid;
  conv_id uuid;
begin
  if me is null then
    raise exception 'Not authenticated';
  end if;

  if other_user_id is null then
    raise exception 'User not found';
  end if;

  if other_user_id = me then
    raise exception 'You cannot DM yourself';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = other_user_id
  ) then
    raise exception 'User not found';
  end if;

  a := least(me, other_user_id);
  b := greatest(me, other_user_id);

  select c.id
  into conv_id
  from public.conversations c
  where c.is_group = false
    and c.dm_user_a = a
    and c.dm_user_b = b
  limit 1;

  if conv_id is null then
    begin
      insert into public.conversations (
        id,
        name,
        is_group,
        created_by,
        dm_user_a,
        dm_user_b
      )
      values (
        gen_random_uuid(),
        null,
        false,
        me,
        a,
        b
      )
      returning id into conv_id;
    exception
      when unique_violation then
        select c.id
        into conv_id
        from public.conversations c
        where c.is_group = false
          and c.dm_user_a = a
          and c.dm_user_b = b
        limit 1;
    end;
  end if;

  insert into public.conversation_members(conversation_id, user_id)
  values
    (conv_id, me),
    (conv_id, other_user_id)
  on conflict do nothing;

  return conv_id;
end;
$$;

revoke all on function public.get_or_create_dm(uuid) from public;
grant execute on function public.get_or_create_dm(uuid) to authenticated;

-- ------------------------------------------------------------
-- 4. Username shortcut to the same singleton DM.
-- ------------------------------------------------------------

create or replace function public.get_or_create_dm_by_username(target_username text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select p.id
  into target_id
  from public.profiles p
  where lower(p.username) = lower(trim(target_username))
  limit 1;

  if target_id is null then
    raise exception 'Username not found';
  end if;

  return public.get_or_create_dm(target_id);
end;
$$;

revoke all on function public.get_or_create_dm_by_username(text) from public;
grant execute on function public.get_or_create_dm_by_username(text) to authenticated;

-- ------------------------------------------------------------
-- 5. Group chats can include online or offline users.
-- ------------------------------------------------------------

create or replace function public.create_group_chat(
  group_name text,
  member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  conv_id uuid := gen_random_uuid();
  clean_name text := trim(group_name);
  other_count integer;
begin
  if me is null then
    raise exception 'Not authenticated';
  end if;

  if clean_name is null or char_length(clean_name) < 1 then
    raise exception 'Group name is required';
  end if;

  if char_length(clean_name) > 40 then
    raise exception 'Group name is too long';
  end if;

  select count(distinct p.id)
  into other_count
  from public.profiles p
  where p.id = any(coalesce(member_ids, array[]::uuid[]))
    and p.id <> me;

  if other_count < 1 then
    raise exception 'Add at least one other person';
  end if;

  insert into public.conversations (
    id,
    name,
    is_group,
    created_by,
    dm_user_a,
    dm_user_b
  )
  values (
    conv_id,
    clean_name,
    true,
    me,
    null,
    null
  );

  insert into public.conversation_members(conversation_id, user_id)
  values (conv_id, me)
  on conflict do nothing;

  insert into public.conversation_members(conversation_id, user_id)
  select conv_id, p.id
  from public.profiles p
  where p.id = any(coalesce(member_ids, array[]::uuid[]))
    and p.id <> me
  on conflict do nothing;

  return conv_id;
end;
$$;

revoke all on function public.create_group_chat(text, uuid[]) from public;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;

-- ------------------------------------------------------------
-- 6. Stop browser code from creating arbitrary conversations/members.
--    All creation now goes through the RPCs above.
-- ------------------------------------------------------------

drop policy if exists "Conversation creator can add members"
on public.conversation_members;

drop policy if exists "authenticated can add conversation members"
on public.conversation_members;

drop policy if exists "conversation_members_insert"
on public.conversation_members;

drop policy if exists "members can insert"
on public.conversation_members;

drop policy if exists "authenticated can add conversation members"
on public.conversation_members;

revoke insert on public.conversations from authenticated;
revoke insert on public.conversation_members from authenticated;

-- Keep browser read access. RLS still decides which rows are visible.
grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;

-- ------------------------------------------------------------
-- 7. Realtime: notify a user immediately when they're added to a group.
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_members'
  ) then
    alter publication supabase_realtime
      add table public.conversation_members;
  end if;
end
$$;

-- Done.
