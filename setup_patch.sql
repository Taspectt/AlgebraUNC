-- VANISH CHAT - FINAL PATCH
-- Run this ONCE in Supabase SQL Editor after the initial schema script.

-- 1) Physically delete messages as soon as they are older than 60 minutes.
--    The app/RLS already hides expired messages immediately; this cron job
--    removes the expired rows from the database every minute.
create extension if not exists pg_cron;

select cron.schedule(
  'vanish-delete-expired-messages',
  '* * * * *',
  $$ select public.delete_expired_messages(); $$
);

-- The cleanup function does not need to be callable from the browser.
revoke execute on function public.delete_expired_messages() from public;
revoke execute on function public.delete_expired_messages() from anon;
revoke execute on function public.delete_expired_messages() from authenticated;

-- 2) Make usernames case-insensitively unique.
--    Prevents "Sam" and "sam" from being separate accounts.
create unique index if not exists profiles_username_ci_unique
on public.profiles (lower(username));

-- 3) Allow either side of a friendship to unfriend later.
drop policy if exists "Users can remove own friendships" on public.friendships;

create policy "Users can remove own friendships"
on public.friendships
for delete
to authenticated
using (
  user_a = auth.uid()
  or user_b = auth.uid()
);

-- 4) Helpful indexes for the friend/chat UI.
create index if not exists friend_requests_receiver_status_idx
on public.friend_requests(receiver_id, status);

create index if not exists friend_requests_sender_status_idx
on public.friend_requests(sender_id, status);

create index if not exists friendships_user_a_idx
on public.friendships(user_a);

create index if not exists friendships_user_b_idx
on public.friendships(user_b);

-- Done.
