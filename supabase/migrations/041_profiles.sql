-- 041 — buyer profiles
--
-- Consequence of 040. Once messaging requires an account, `my_conversations()`
-- returning the literal string **'Someone nearby'** is no longer a privacy
-- decision, it is a missing feature: a registered person is writing to a cook
-- and the cook is shown a blank. 020 said it plainly — "buyers are frequently
-- anonymous identities, so there is often no name to show even if we wanted
-- to." For anyone who has passed the gate, that is now false.
--
-- ## One identity, not two
--
-- `cooks.id` *is* the user id, so a cook buying from another cook must not end
-- up maintaining two names. `profiles` is the account holder's identity;
-- `cooks` stays the kitchen's listing. Existing cooks are backfilled below, so
-- nobody is asked for a name they have already given.
--
-- ## Not a directory
--
-- A profile is visible to yourself and to a cook you have actually contacted —
-- a conversation or a claim. There is deliberately no way to enumerate buyers.
-- This follows 020's own rule ("a cook has no business knowing a buyer's
-- history with anyone else") rather than quietly widening it: the cook learns
-- who is at their door, not who else that person buys from.
--
-- For the same reason there is **no global completed-pickup count** here, which
-- was the obvious thing to add and would have contradicted 020 two lines after
-- citing it. `prior_claims` stays scoped to the one cook, and `member_since`
-- carries the "brand new account" signal without naming anyone else.

set search_path = public, extensions;

create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 50),
  -- A storage *path*, not a URL: the avatars bucket is private (below), so the
  -- client mints a signed URL. `cooks.avatar_url` is a URL because that bucket
  -- is public — the difference is intentional, not an inconsistency.
  avatar_path  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table profiles enable row level security;

-- Backfill: every cook already told us who they are.
insert into profiles (id, display_name)
select c.id, left(trim(c.display_name), 50) from cooks c
 where length(trim(coalesce(c.display_name, ''))) > 0
on conflict (id) do nothing;

-- And keep it true going forward. A trigger rather than an edit to
-- `register_cook` (023), because the invariant is "every cook has a profile",
-- not "one particular function remembers to make one" — and without it a cook
-- who registered *after* this migration would be told to "add your name"
-- before messaging another cook, having just typed their name into onboarding.
create or replace function cook_ensures_profile() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
begin
  -- Never abort cook registration over the profile. `cooks.display_name` has
  -- no length cap and `profiles.display_name` does, so an unguarded insert
  -- would turn a 51-character kitchen name into a failed sign-up.
  if length(trim(coalesce(new.display_name, ''))) = 0 then return new; end if;

  insert into profiles (id, display_name)
  values (new.id, left(trim(new.display_name), 50))
  -- do nothing, not do update: someone who was a buyer first already chose a
  -- personal name, and opening a kitchen should not silently rename them.
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists cooks_ensure_profile on cooks;
create trigger cooks_ensure_profile after insert on cooks
  for each row execute function cook_ensures_profile();

-- ---------------------------------------------------------------------------
-- Visibility: yourself, or someone who has contacted you.
-- ---------------------------------------------------------------------------
drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for select
  using (
    id = auth.uid()
    or exists (select 1 from conversations c
                where c.buyer_id = profiles.id and c.cook_id = auth.uid())
    or exists (select 1 from claims cl
                where cl.buyer_id = profiles.id and cl.cook_id = auth.uid())
  );

drop policy if exists profiles_write_own on profiles;
create policy profiles_write_own on profiles for insert
  with check (id = auth.uid());

drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, update (display_name, avatar_path, updated_at) on profiles
  to authenticated;

-- ---------------------------------------------------------------------------
-- Avatars: a private bucket, unlike kitchen-photos.
--
-- 024 made kitchen photos public-read because they are advertising, shown to
-- anonymous browsers who have no session to check. A buyer's face is the
-- opposite: shown to one cook, after contact. A public bucket would leave the
-- profile "not enumerable" while the picture in it was fetchable by anyone
-- holding the URL, and an unguessable URL is not access control.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2 * 1024 * 1024,
        array['image/jpeg', 'image/png', 'image/heic', 'image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars are written by their owner" on storage.objects;
drop policy if exists "avatars update by owner"            on storage.objects;
drop policy if exists "avatars delete by owner"            on storage.objects;
drop policy if exists "avatars readable by contacts"       on storage.objects;

create policy "avatars are written by their owner"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars update by owner"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars delete by owner"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- Same reachability rule as the profile row itself. Signing a URL requires
-- select on the object, so this is what gates it.
create policy "avatars readable by contacts"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from conversations c
                  where c.cook_id = auth.uid()
                    and c.buyer_id::text = (storage.foldername(name))[1])
      or exists (select 1 from claims cl
                  where cl.cook_id = auth.uid()
                    and cl.buyer_id::text = (storage.foldername(name))[1])
    )
  );

-- ---------------------------------------------------------------------------
-- Editing your own profile.
-- ---------------------------------------------------------------------------
create or replace function upsert_my_profile(p_name text, p_avatar text default null)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_name text := trim(coalesce(p_name, ''));
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if v_name = '' then raise exception 'a name is required'; end if;
  if length(v_name) > 50 then raise exception 'name too long'; end if;

  insert into profiles (id, display_name, avatar_path)
  values (v_me, v_name, nullif(trim(coalesce(p_avatar, '')), ''))
  on conflict (id) do update
    set display_name = excluded.display_name,
        -- Passing null leaves the existing photo alone; clearing it is a
        -- separate deliberate act, not a side effect of a rename.
        avatar_path  = coalesce(excluded.avatar_path, profiles.avatar_path),
        updated_at   = now();
end $$;

revoke all on function upsert_my_profile(text, text) from public, anon;
grant execute on function upsert_my_profile(text, text) to authenticated;

-- Seeding from Sign in with Apple, which is *not* the same operation as the
-- user editing their name.
--
-- Apple returns `fullName` only on the first authorization for an Apple ID and
-- never again. That makes it worth capturing, but it must not win against a
-- name the person actually typed: an anonymous buyer can set a name before
-- upgrading, and `upsert_my_profile`'s `do update` would overwrite it during
-- the link. Hence `do nothing` and a separate entry point — the difference
-- between "this is my name" and "this is the best guess we have".
create or replace function seed_my_profile_name(p_name text)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_name text := trim(coalesce(p_name, ''));
begin
  if v_me is null or v_name = '' then return false; end if;

  insert into profiles (id, display_name) values (v_me, left(v_name, 50))
  on conflict (id) do nothing;

  return found;
end $$;

revoke all on function seed_my_profile_name(text) from public, anon;
grant execute on function seed_my_profile_name(text) to authenticated;

create or replace function my_profile()
returns table (display_name text, avatar_path text, created_at timestamptz)
language sql stable security definer
set search_path = public, extensions as $$
  select p.display_name, p.avatar_path, p.created_at
    from profiles p where p.id = auth.uid();
$$;

revoke all on function my_profile() from public, anon;
grant execute on function my_profile() to authenticated;

revoke all on function cook_ensures_profile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Messaging now needs a name, not just an account.
--
-- An account with no profile still reaches the cook as 'Someone nearby', which
-- is the thing 040 set out to fix. The app collects the name in the same sheet
-- as the sign-in, so this is one step for the buyer, not two.
-- ---------------------------------------------------------------------------
create or replace function sender_can_message()
returns text language plpgsql stable security definer
set search_path = public, extensions, auth as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then return 'anonymous'; end if;
  if coalesce((select u.is_anonymous from auth.users u where u.id = v_me), true)
    then return 'anonymous'; end if;
  if not exists (select 1 from profiles p where p.id = v_me)
    then return 'no_profile'; end if;
  return 'ok';
end $$;

revoke all on function sender_can_message() from public, anon;
grant execute on function sender_can_message() to authenticated;

create or replace function send_message(
  p_cook  uuid,
  p_body  text,
  p_claim uuid default null
)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me      uuid := auth.uid();
  v_gate    text;
  v_thread  uuid;
  v_recent  integer;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- Distinct errcodes so the app can open the right sheet. Neither of these is
  -- a failure to report — they are prompts.
  v_gate := sender_can_message();
  if v_gate = 'anonymous'  then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to send a message' using errcode = 'P0003';
  end if;

  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;
  if v_me = p_cook then
    raise exception 'a cook cannot open a conversation with themselves';
  end if;
  if not exists (select 1 from cooks where id = p_cook) then
    raise exception 'no such cook';
  end if;
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  select count(*) into v_recent
    from messages m
   where m.sender_id = v_me and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  insert into conversations (cook_id, buyer_id, opening_claim)
  values (p_cook, v_me, p_claim)
  on conflict (cook_id, buyer_id) do update set last_message_at = now()
  returning id into v_thread;

  insert into messages (conversation_id, sender_id, body)
  values (v_thread, v_me, trim(p_body))
  returning id into v_message;

  return v_message;
end $$;

revoke all on function send_message(uuid, text, uuid) from public, anon;
grant execute on function send_message(uuid, text, uuid) to authenticated;

create or replace function reply_in_conversation(p_thread uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_gate text; v_ok boolean;
        v_message uuid; v_recent integer;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  v_gate := sender_can_message();
  if v_gate = 'anonymous' then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to send a message' using errcode = 'P0003';
  end if;

  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;

  select (c.buyer_id = v_me or c.cook_id = v_me) into v_ok
    from conversations c where c.id = p_thread;
  if not coalesce(v_ok, false) then raise exception 'not authorized'; end if;

  select count(*) into v_recent
    from messages m where m.sender_id = v_me and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  insert into messages (conversation_id, sender_id, body)
  values (p_thread, v_me, trim(p_body))
  returning id into v_message;

  update conversations set last_message_at = now() where id = p_thread;
  return v_message;
end $$;

revoke all on function reply_in_conversation(uuid, text) from public, anon;
grant execute on function reply_in_conversation(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The inbox, with a real name on the buyer side.
-- ---------------------------------------------------------------------------
create or replace function my_conversations()
returns table (
  id            uuid,
  cook_id       uuid,
  buyer_id      uuid,
  other_name    text,
  other_avatar  text,
  last_body     text,
  last_at       timestamptz,
  unread        integer,
  i_am_the_cook boolean
)
language sql stable security definer
set search_path = public, extensions as $$
  select c.id, c.cook_id, c.buyer_id,
         case when c.cook_id = auth.uid()
              -- The fallback survives for threads opened before 040 shipped.
              then coalesce(bp.display_name, 'Someone nearby')
              else co.display_name end,
         case when c.cook_id = auth.uid() then bp.avatar_path else co.avatar_url end,
         (select m.body from messages m
           where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*)::int from messages m
           where m.conversation_id = c.id
             and m.sender_id <> auth.uid() and m.read_at is null),
         c.cook_id = auth.uid()
    from conversations c
    join cooks co        on co.id = c.cook_id
    left join profiles bp on bp.id = c.buyer_id
   where c.buyer_id = auth.uid() or c.cook_id = auth.uid()
   order by c.last_message_at desc;
$$;

grant execute on function my_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- And on the claim, so the same person isn't 'Ana' in one place and 'Someone
-- nearby' in the other. Nullable throughout: claiming stays anonymous, so a
-- mixed inbox is the expected steady state, not a migration artefact.
-- ---------------------------------------------------------------------------
drop function if exists claim_inbox();

-- Guarded, because `alter type … add attribute` is the one statement in this
-- file that is not re-runnable: a second pass raises "column already exists"
-- and takes the rest of the migration with it. That matters when a migration
-- is applied by hand — a half-completed paste should be retryable, not a dead
-- end that needs the attributes dropped before it can be tried again.
do $$
begin
  if not exists (
    select 1 from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_type t on t.typrelid = c.oid
     where t.typname = 'inbox_claim' and a.attname = 'buyer_name'
       and a.attnum > 0 and not a.attisdropped
  ) then
    execute 'alter type inbox_claim add attribute buyer_name   text cascade';
    execute 'alter type inbox_claim add attribute buyer_avatar text cascade';
    execute 'alter type inbox_claim add attribute member_since timestamptz cascade';
  end if;
end $$;

create or replace function claim_inbox()
returns setof inbox_claim
language sql stable
set search_path = public, extensions as $$
  select
    c.id, c.buyer_id, c.status, c.note, c.created_at,
    (select string_agg(ci.quantity || '× ' || coalesce(mi.name_es, mi.name_en), ', '
                       order by mi.sort_order)
       from claim_items ci
       join menu_items mi on mi.id = ci.menu_item_id
      where ci.claim_id = c.id),
    (select sum(ci.quantity * mi.amount_cents)::int
       from claim_items ci
       join menu_items mi on mi.id = ci.menu_item_id
      where ci.claim_id = c.id),
    (select count(*)::int from claims p
      where p.cook_id = c.cook_id and p.buyer_id = c.buyer_id
        and p.created_at < c.created_at),
    bp.display_name,
    bp.avatar_path,
    bp.created_at
  from claims c
  left join profiles bp on bp.id = c.buyer_id
  where c.cook_id = auth.uid()
  order by
    case c.status when 'pending' then 0 else 1 end,
    c.created_at desc;
$$;

grant execute on function claim_inbox() to authenticated;

comment on table profiles is
  'Account-holder identity. Visible only to yourself and to a cook you have '
  'contacted; deliberately not enumerable.';
