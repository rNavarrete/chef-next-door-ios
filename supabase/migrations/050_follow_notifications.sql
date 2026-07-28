-- 050 — "Ana just lit up"
--
-- The notification the follow relationship exists for, and the one thing in
-- this product that makes "cooking right now" mean anything. 016 built the
-- table, the per-cook `notify` toggle, and an index — `follows_cook_idx on
-- follows (cook_id) where notify` — whose only conceivable use is the query
-- below. Nothing ever ran it. A buyer following twelve kitchens learned one
-- had opened by opening the app and hoping, which is the behaviour the whole
-- thesis is trying to replace.
--
-- ## Fired on the *session*, not on `open_kitchen`
--
-- `open_kitchen` (005) is idempotent: re-opening while already open confirms
-- the existing session rather than inserting. So an insert into
-- `serving_sessions` is exactly one genuine opening, and a cook double-tapping
-- the burner cannot produce two notifications.
--
-- ## Two caps, and they solve different problems
--
--   * **Per cook, 8 hours.** Stops open → close → reopen from re-announcing.
--     A cook who genuinely serves lunch and then dinner still gets both.
--   * **Per buyer, 5 a day.** Stops a Saturday morning in Covina from becoming
--     twelve buzzes. Following more cooks should improve what you hear about,
--     not punish you for it — the plan called this a "hard daily cap" and it is
--     the difference between a useful signal and an uninstall.
--
-- Blocks are honoured in both directions: a buyer who blocked this kitchen does
-- not hear from it, and a buyer the cook blocked is not told when they open.

set search_path = public, extensions;

-- The audit the caps are computed from. Also the record of what we sent, which
-- is the only way to answer "why did I get four notifications" later.
create table if not exists follow_notifications (
  buyer_id uuid not null references auth.users(id) on delete cascade,
  cook_id  uuid not null references cooks(id) on delete cascade,
  sent_at  timestamptz not null default now()
);

create index if not exists follow_notifications_buyer
  on follow_notifications (buyer_id, sent_at desc);
create index if not exists follow_notifications_pair
  on follow_notifications (buyer_id, cook_id, sent_at desc);

alter table follow_notifications enable row level security;

-- No client grants. This is bookkeeping the server does about a person, not
-- something they read — and the cook must not be able to derive their follower
-- list from it (016 was explicit that followers are not enumerable).
revoke all on follow_notifications from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Who should hear about this opening.
-- ---------------------------------------------------------------------------
create or replace function followers_to_notify(p_cook uuid)
returns table (buyer_id uuid)
language sql stable security definer
set search_path = public, extensions as $$
  select f.buyer_id
    from follows f
   where f.cook_id = p_cook
     and f.notify
     -- Per-cook cooldown.
     and not exists (
       select 1 from follow_notifications fn
        where fn.buyer_id = f.buyer_id and fn.cook_id = f.cook_id
          and fn.sent_at > now() - interval '8 hours')
     -- Per-buyer daily cap.
     and (select count(*) from follow_notifications fn2
           where fn2.buyer_id = f.buyer_id
             and fn2.sent_at > now() - interval '24 hours') < 5
     -- A blocked kitchen is meant to disappear; a notification would undo that.
     and not exists (
       select 1 from blocked_cooks b
        where b.blocker_id = f.buyer_id and b.cook_id = f.cook_id)
     -- And a buyer the cook blocked is not invited over.
     and not exists (
       select 1 from blocked_buyers bb
        where bb.cook_id = f.cook_id and bb.buyer_id = f.buyer_id);
$$;

revoke all on function followers_to_notify(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The alert.
--
-- One call serves every eligible follower: the text is identical for all of
-- them, so the Edge Function's `tokens` array fans out in a single request.
-- ---------------------------------------------------------------------------
-- Pure: takes the recipients rather than choosing them, and writes nothing.
-- The first draft selected the followers *and* recorded the send in here, which
-- made two identical calls return different answers — a payload builder that
-- mutates is a trap for the next person to debug it, and made the tests below
-- lie. The trigger owns the side effect now.
create or replace function follow_alert_payload(p_cook uuid, p_buyers uuid[])
returns jsonb language plpgsql stable security definer
set search_path = public, extensions as $$
declare
  v_name   text;
  v_items  text;
  v_tokens jsonb;
begin
  select display_name into v_name from cooks where id = p_cook;
  if v_name is null or p_buyers is null or cardinality(p_buyers) = 0 then
    return null;
  end if;

  select jsonb_agg(jsonb_build_object('token', d.token, 'environment', d.environment))
    into v_tokens
    from device_tokens d where d.user_id = any(p_buyers);
  if v_tokens is null then return null; end if;   -- nobody has a device

  -- What they're making, which is the part that decides whether anyone walks
  -- over. Three is enough to be concrete without becoming a menu.
  select string_agg(name, ', ') into v_items
    from (
      select coalesce(mi.name_es, mi.name_en) as name
        from menu_items mi
       where mi.cook_id = p_cook and mi.is_available
       order by mi.sort_order
       limit 3
    ) t;

  return jsonb_build_object(
    'kind',   'alert',
    'tokens', v_tokens,
    'title',  v_name || ' is cooking',
    'body',   coalesce(v_items, 'Tap to see what''s on today.'),
    -- APNs `thread-id` is a *grouping* key, not a reference to our
    -- conversations: passing the cook groups every "just lit up" alert about
    -- them into one stack. When deep linking is built it must tell these apart
    -- from message alerts, which put a conversation id here.
    'thread_id', p_cook,
    'badge',  0
  );
end $$;

revoke all on function follow_alert_payload(uuid, uuid[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The trigger.
-- ---------------------------------------------------------------------------
create or replace function push_cook_opened() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url     text;
  v_secret  text;
  v_buyers  uuid[];
  v_payload jsonb;
begin
  begin
    select value into v_url    from app_secrets where key = 'push_fn_url';
    select value into v_secret from app_secrets where key = 'push_fn_secret';
    if v_url is null or v_secret is null then return new; end if;

    select array_agg(buyer_id) into v_buyers from followers_to_notify(new.cook_id);
    v_payload := follow_alert_payload(new.cook_id, v_buyers);
    if v_payload is null then return new; end if;

    -- Recorded before sending, deliberately: if delivery fails we have told
    -- them once too few rather than once too many.
    insert into follow_notifications (buyer_id, cook_id)
    select unnest(v_buyers), new.cook_id;

    -- The send gets its **own** handler. Sharing one with the insert above
    -- meant a throw from `net.http_post` rolled the recording back with it —
    -- so a failed push would quietly restore the buyer's cap allowance and let
    -- the next opening notify them again. The comment claimed "once too few";
    -- the code did the opposite.
    begin
      perform net.http_post(
        url     := v_url,
        body    := v_payload,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-lk-secret', v_secret
        ),
        timeout_milliseconds := 10000
      );
    exception when others then
      raise warning 'follow push send failed for cook %: %', new.cook_id, sqlerrm;
    end;
  exception when others then
    -- Same rule as 035, 045 and 047: a failed push costs a notification, never
    -- the cook's ability to open their kitchen.
    raise warning 'follow push failed for cook %: %', new.cook_id, sqlerrm;
  end;
  return new;
end $$;

revoke all on function push_cook_opened() from public, anon, authenticated;

drop trigger if exists serving_sessions_push_followers on serving_sessions;
create trigger serving_sessions_push_followers after insert on serving_sessions
  for each row execute function push_cook_opened();

comment on table follow_notifications is
  'What we told whom, and the basis for both caps. No client grants — a cook '
  'must not be able to derive their follower list from it.';
