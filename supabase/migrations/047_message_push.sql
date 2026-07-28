-- 047 — a cook finds out an order arrived
--
-- Everything built so far assumes someone is looking at the app. A buyer orders
-- and the cook learns about it the next time they happen to open Messages,
-- which for a product about *right now* is the difference between working and
-- not. Nothing in this app has ever asked for notification permission.
--
-- Distinct from the Live Activity (034–036, 045). That is one card, on one
-- buyer's Lock Screen, updated by a per-activity token. This is an ordinary
-- alert to whichever devices a person happens to be carrying, and it needs a
-- different token type, a different APNs topic and a different push-type
-- header. They share the Edge Function and nothing else.
--
-- ## What the notification is allowed to say
--
-- **Never the address.** The 'address' alert says "shared their address" and
-- carries no location, exactly as the in-thread marker does (043). A push
-- notification renders on a locked screen that anybody standing nearby can
-- read, which makes it the single worst place in the system to print someone's
-- home address — and it would bypass `thread_address`, the audit row and the
-- daily cap in one step.
--
-- Message bodies *are* included. That is what a messaging notification is for,
-- and iOS already lets a person hide previews system-wide. An address is not
-- theirs to hide.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Device tokens. Plural per user, deliberately: phone and iPad, or a replaced
-- handset whose old token has not yet been rejected by APNs.
-- ---------------------------------------------------------------------------
create table if not exists device_tokens (
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null,
  environment text not null default 'development'
    check (environment in ('development', 'production')),
  updated_at  timestamptz not null default now(),
  primary key (user_id, token)
);

create index if not exists device_tokens_user on device_tokens (user_id);

alter table device_tokens enable row level security;

-- No policy and no grant, same posture as `live_activity_tokens` (034) and
-- `kitchen_locations`: a push token is write-only from the client's side and
-- reaches the table through the definer function below. A readable table would
-- let one person enumerate another's devices.
revoke all on device_tokens from anon, authenticated;

create or replace function register_device_token(p_token text, p_environment text default 'development')
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  if p_environment not in ('development', 'production') then
    raise exception 'unknown APNs environment %', p_environment;
  end if;

  insert into device_tokens (user_id, token, environment)
  values (v_me, trim(p_token), p_environment)
  on conflict (user_id, token) do update
    set environment = excluded.environment, updated_at = now();
end $$;

revoke all on function register_device_token(text, text) from public, anon;
grant execute on function register_device_token(text, text) to authenticated;

-- Signing out should stop that handset ringing for an account that is no
-- longer on it.
create or replace function forget_device_token(p_token text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from device_tokens where user_id = auth.uid() and token = trim(p_token);
end $$;

revoke all on function forget_device_token(text) from public, anon;
grant execute on function forget_device_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- What the alert says.
-- ---------------------------------------------------------------------------
create or replace function message_alert_payload(p_message uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_msg       record;
  v_thread    record;
  v_recipient uuid;
  v_sender    text;
  v_tokens    jsonb;
  v_body      text;
  v_unread    int;
begin
  select * into v_msg from messages where id = p_message;
  if not found then return null; end if;

  select * into v_thread from conversations where id = v_msg.conversation_id;
  if not found then return null; end if;

  -- The other party, never the sender. A person does not need telling about
  -- something they just did.
  v_recipient := case when v_msg.sender_id = v_thread.cook_id
                      then v_thread.buyer_id else v_thread.cook_id end;

  select jsonb_agg(jsonb_build_object('token', d.token, 'environment', d.environment))
    into v_tokens
    from device_tokens d where d.user_id = v_recipient;
  if v_tokens is null then return null; end if;   -- no devices registered

  -- Whose name is on it depends on which way the message is going.
  if v_msg.sender_id = v_thread.cook_id then
    select display_name into v_sender from cooks where id = v_thread.cook_id;
  else
    select coalesce(p.display_name, 'Someone nearby') into v_sender
      from profiles p where p.id = v_thread.buyer_id;
    v_sender := coalesce(v_sender, 'Someone nearby');
  end if;

  v_body := case v_msg.kind
    when 'order'   then v_msg.body
    -- Deliberately no address. See the header.
    when 'address' then 'Shared their address'
    when 'pickup'  then 'Marked as picked up'
    else left(v_msg.body, 140)
  end;

  select count(*)::int into v_unread
    from messages m
    join conversations c on c.id = m.conversation_id
   where (c.buyer_id = v_recipient or c.cook_id = v_recipient)
     and m.sender_id <> v_recipient and m.read_at is null;

  return jsonb_build_object(
    'kind',      'alert',
    'tokens',    v_tokens,
    'title',     v_sender,
    'body',      v_body,
    'thread_id', v_msg.conversation_id,
    'badge',     v_unread
  );
end $$;

revoke all on function message_alert_payload(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The trigger.
-- ---------------------------------------------------------------------------
create or replace function push_message_alert() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url     text;
  v_secret  text;
  v_payload jsonb;
begin
  begin
    select value into v_url    from app_secrets where key = 'push_fn_url';
    select value into v_secret from app_secrets where key = 'push_fn_secret';
    if v_url is null or v_secret is null then return new; end if;

    v_payload := message_alert_payload(new.id);
    if v_payload is null then return new; end if;

    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-lk-secret', v_secret
      ),
      body    := v_payload
    );
  exception when others then
    -- Same rule as 035 and 045: a failed push costs a notification, never the
    -- message. The whole assembly is inside the handler because building the
    -- payload reads five tables.
    raise warning 'message push failed for %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

revoke all on function push_message_alert() from public, anon, authenticated;

-- Both names, and the second one is the one that matters — 045 made exactly
-- this mistake (dropping `messages_drop_activity_token`, creating
-- `messages_zz_…`), I wrote a comment there saying a drop must name what the
-- create makes, and then repeated it here one migration later. Re-running
-- raises 42710 on a file that claims to be re-runnable.
drop trigger if exists messages_push_alert on messages;
drop trigger if exists messages_a_push_alert on messages;
-- `_a_` so it runs before the Live Activity triggers. Ordering is by name
-- within the same timing, and the token-dropping trigger from 045 sorts last
-- on purpose — an alert should not be skipped because a later trigger threw.
create trigger messages_a_push_alert after insert on messages
  for each row execute function push_message_alert();

comment on table device_tokens is
  'APNs device tokens for ordinary alerts. Write-only from the client: no '
  'policy and no grant, so it is reachable solely through '
  'register_device_token().';
