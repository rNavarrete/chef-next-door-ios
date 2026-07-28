-- 045 — the Lock Screen card follows the conversation
--
-- 034–036 built the Live Activity around `claims`: tokens keyed on claim_id, a
-- payload assembled from `claim_items`, and a trigger on `claims.status`. 043
-- retired claiming, so all three now point at a table nothing writes to. The
-- card is not broken — it is simply never created, which is worse, because
-- nothing fails and nobody notices.
--
-- ## The stages survive unchanged
--
-- `Stage` stays `waiting` / `confirmed`, which is a genuine simplification and
-- not laziness: the question a buyer picks up their phone to answer was "has
-- Yolanda said yes yet?", and it is now "has she sent me her address yet?" —
-- the same question with a better answer. Pickup **ends** the activity rather
-- than adding a third stage, because a card about food already collected is
-- clutter on a Lock Screen.
--
-- So the widget and `CookingActivityAttributes` need no new cases. Only what
-- feeds them changes.
--
-- ## What still must not leak
--
-- The payload carries a street address, and a Live Activity push travels to a
-- device without passing through RLS. So the assembly below reads
-- `kitchen_locations` **only when a disclosure exists for this conversation** —
-- the same condition `thread_address` enforces. A card that showed the address
-- before the cook shared it would be a disclosure channel that bypassed every
-- gate in the schema.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Tokens can belong to a conversation.
-- ---------------------------------------------------------------------------
alter table live_activity_tokens
  add column if not exists conversation_id uuid references conversations(id) on delete cascade;

-- The primary key goes first. A PK implies NOT NULL, so dropping the null
-- constraint while it is still in place fails with "column is in a primary
-- key" — the order here is load-bearing, not stylistic. Replaced by one
-- partial unique index per origin, so a conversation still gets exactly one
-- token and so does a legacy claim.
do $$ begin
  if exists (select 1 from pg_constraint where conname = 'live_activity_tokens_pkey') then
    alter table live_activity_tokens drop constraint live_activity_tokens_pkey;
  end if;
end $$;

alter table live_activity_tokens alter column claim_id drop not null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'live_activity_tokens_origin') then
    alter table live_activity_tokens add constraint live_activity_tokens_origin
      check (num_nonnulls(claim_id, conversation_id) = 1);
  end if;
end $$;

create unique index if not exists live_activity_tokens_claim
  on live_activity_tokens (claim_id) where claim_id is not null;
create unique index if not exists live_activity_tokens_conversation
  on live_activity_tokens (conversation_id) where conversation_id is not null;

-- Still no SELECT policy and no SELECT grant for anyone. A push token is
-- write-only from the client's side; 034 made that call and it stands.
create or replace function register_thread_activity_token(
  p_thread      uuid,
  p_token       text,
  p_activity_id text default null,
  p_environment text default 'development'
)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid := auth.uid();
begin
  if v_buyer is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  if p_environment not in ('development', 'production') then
    raise exception 'unknown APNs environment %', p_environment;
  end if;

  -- The buyer's card, so the buyer's thread. A cook has the order in their
  -- inbox and does not need a Lock Screen card about their own kitchen.
  if not exists (select 1 from conversations c
                  where c.id = p_thread and c.buyer_id = v_buyer) then
    raise exception 'not authorized';
  end if;

  -- The `where` clause is required, not decorative: a *partial* unique index
  -- can only arbitrate an ON CONFLICT when the statement repeats its predicate.
  -- Without it Postgres raises 42P10 and the token never registers, which
  -- fails silently as "the card just never appears".
  insert into live_activity_tokens (conversation_id, buyer_id, token, activity_id, environment)
  values (p_thread, v_buyer, trim(p_token), p_activity_id, p_environment)
  on conflict (conversation_id) where conversation_id is not null do update
    set token       = excluded.token,
        activity_id = excluded.activity_id,
        environment = excluded.environment,
        updated_at  = now();
end $$;

revoke all on function register_thread_activity_token(uuid, text, text, text) from public, anon;
grant execute on function register_thread_activity_token(uuid, text, text, text) to authenticated;

-- Dropping the primary key broke the *claim* registrar the same way — its
-- `on conflict (claim_id)` had been arbitrating against the PK. Claims are
-- retired, so nothing calls this, but a migration that leaves a working
-- function silently raising 42P10 is a trap for whoever revives it.
create or replace function register_activity_token(
  p_claim       uuid,
  p_token       text,
  p_activity_id text default null,
  p_environment text default 'development'
)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid := auth.uid();
begin
  if v_buyer is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  if p_environment not in ('development', 'production') then
    raise exception 'unknown APNs environment %', p_environment;
  end if;
  if not exists (select 1 from claims c where c.id = p_claim and c.buyer_id = v_buyer) then
    raise exception 'not authorized';
  end if;

  insert into live_activity_tokens (claim_id, buyer_id, token, activity_id, environment)
  values (p_claim, v_buyer, trim(p_token), p_activity_id, p_environment)
  on conflict (claim_id) where claim_id is not null do update
    set token       = excluded.token,
        activity_id = excluded.activity_id,
        environment = excluded.environment,
        updated_at  = now();
end $$;

revoke all on function register_activity_token(uuid, text, text, text) from public, anon;
grant execute on function register_activity_token(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The payload.
-- ---------------------------------------------------------------------------
create or replace function activity_payload_for_thread(p_thread uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_thread  record;
  v_token   record;
  v_cook    record;
  v_order   record;
  v_shared  boolean;
  v_street  text; v_city text; v_zip text;
  v_lat     double precision; v_lon double precision;
  v_stage   text;
  v_address text := '';
  v_since   text;
  v_cooking boolean;
begin
  select * into v_thread from conversations where id = p_thread;
  if not found then return null; end if;

  select * into v_token from live_activity_tokens where conversation_id = p_thread;
  if not found then return null; end if;   -- nobody is showing a card

  select co.display_name, k.id as kitchen_id
    into v_cook
    from cooks co join kitchens k on k.cook_id = co.id
   where co.id = v_thread.cook_id;

  -- The most recent order in the thread. A buyer who adds to their order gets a
  -- card about the latest one, which is the one they are walking towards.
  select m.payload, m.created_at into v_order
    from messages m
   where m.conversation_id = p_thread and m.kind = 'order'
   order by m.created_at desc limit 1;
  if not found then return null; end if;   -- nothing ordered; nothing to show

  -- Lamp state, from the cook's live session rather than anything cached.
  --
  -- `in ('lit','dimming')`, NOT `<> 'out'`. `freshness_of` returns 'out' only
  -- when the session is *closed*, so `<> 'out'` stays true for a session left
  -- open overnight with no confirmation — a card asserting a lit kitchen for
  -- hours after the cook went to bed, which is the exact thing the decay
  -- ladder exists to stop. 036 had this right; this is a regression avoided.
  select (s.id is not null
          and freshness_of(s.last_confirmed_at, s.closed_at) in ('lit','dimming'))
    into v_cooking
    from cooks c
    left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
   where c.id = v_thread.cook_id;

  v_shared := exists (select 1 from address_disclosures ad
                       where ad.conversation_id = p_thread);
  v_stage  := case when v_shared then 'confirmed' else 'waiting' end;

  -- Read the address ONLY behind the same condition `thread_address` uses. A
  -- push bypasses RLS, so this check is the only thing standing between the
  -- card and an undisclosed home address.
  if v_shared then
    select kl.street, kl.city, kl.postal_code,
           ST_Y(kl.exact_point::geometry), ST_X(kl.exact_point::geometry)
      into v_street, v_city, v_zip, v_lat, v_lon
      from kitchen_locations kl where kl.kitchen_id = v_cook.kitchen_id;
    v_address := v_street || ', ' || v_city || ' ' || v_zip;
  end if;

  -- Absolute clock time, never elapsed — same rule as 036.
  v_since := 'since ' || lower(to_char(v_order.created_at at time zone 'America/Los_Angeles',
                                       'FMHH:MI am'));

  return jsonb_build_object(
    'token',       v_token.token,
    'activity_id', v_token.activity_id,
    'environment', v_token.environment,
    'state', jsonb_build_object(
      'stage',         v_stage,
      'cookIsCooking', coalesce(v_cooking, false),
      'itemSummary',   coalesce(
                         (select string_agg((l ->> 'quantity') || '× ' ||
                                            coalesce(l ->> 'name_en', l ->> 'name'), ', ')
                            from jsonb_array_elements(v_order.payload -> 'lines') l),
                         ''),
      'priceSummary',  '$' || to_char((v_order.payload ->> 'total_cents')::int / 100.0,
                                      'FM999990.00'),
      'addressLine',   v_address,
      'sinceLabel',    v_since,
      'directionsURL', case when v_shared
                            then 'maps://?daddr=' || v_lat || ',' || v_lon
                            else null end
    ),
    'headline', case when v_shared
                     then v_cook.display_name || ' shared their address ·'
                     else v_cook.display_name || ' ·' end
  );
end $$;

revoke all on function activity_payload_for_thread(uuid) from public, anon, authenticated;

comment on function activity_payload_for_thread is
  'Live Activity payload for a conversation. Reads kitchen_locations only when '
  'an address_disclosures row exists for this thread — a push does not pass '
  'through RLS, so that check is the whole gate.';

-- ---------------------------------------------------------------------------
-- The trigger: a stage change is an address being shared, or a pickup.
--
-- Not every message. A plain reply does not change what the card says, and
-- pushing on each one would spend a Live Activity update per "ok see you soon"
-- — APNs throttles those, so the noise would cost us the updates that matter.
-- ---------------------------------------------------------------------------
create or replace function push_thread_activity() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url     text;
  v_secret  text;
  v_payload jsonb;
begin
  if new.kind not in ('address', 'pickup') then return new; end if;

  -- Everything inside one handler, for the reason 035 documents: nothing about
  -- sending a push may roll back the cook sharing their address. Assembling the
  -- payload reads six tables and any of them can surprise us, so "assemble"
  -- belongs inside the net that "send" is already under.
  begin
    select value into v_url    from app_secrets where key = 'push_fn_url';
    select value into v_secret from app_secrets where key = 'push_fn_secret';
    if v_url is null or v_secret is null then return new; end if;

    v_payload := activity_payload_for_thread(new.conversation_id);
    if v_payload is null then return new; end if;   -- no token registered

    -- Pickup ends the card rather than updating it.
    v_payload := v_payload || jsonb_build_object(
      'event', case when new.kind = 'pickup' then 'end' else 'update' end
    );

    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      ),
      body    := v_payload
    );
  exception when others then
    -- A failed push costs a card update. It must never cost the message.
    raise warning 'live activity push failed for conversation %: %',
      new.conversation_id, sqlerrm;
  end;

  return new;
end $$;

revoke all on function push_thread_activity() from public, anon, authenticated;

drop trigger if exists messages_push_activity on messages;
create trigger messages_push_activity after insert on messages
  for each row execute function push_thread_activity();

-- ---------------------------------------------------------------------------
-- Orders the cook has not closed out.
--
-- `CloseOutSheet` asks a cook turning off their light whether the people still
-- coming actually turned up. It was built on `claim_inbox` and, after 043,
-- would have kept working while always returning nothing — compiling, opening,
-- and silently listing zero orders forever. That is worse than deleting it:
-- the cook would believe nobody was waiting.
--
-- "Open" means an order exists and no pickup has been recorded. Address shared
-- or not: someone who ordered and never heard back is exactly who a cook
-- closing up should be reminded about.
-- ---------------------------------------------------------------------------
create or replace function open_orders()
returns table (
  conversation_id uuid,
  buyer_name      text,
  item_summary    text,
  total_cents     integer,
  address_shared  boolean,
  ordered_at      timestamptz
)
language sql stable security definer
set search_path = public, extensions as $$
  with latest as (
    select distinct on (m.conversation_id)
           m.conversation_id, m.payload, m.created_at
      from messages m
      join conversations c on c.id = m.conversation_id
     where m.kind = 'order' and c.cook_id = auth.uid()
     order by m.conversation_id, m.created_at desc
  )
  select c.id,
         coalesce(p.display_name, 'Someone nearby'),
         (select string_agg((l ->> 'quantity') || '× ' || (l ->> 'name'), ', ')
            from jsonb_array_elements(latest.payload -> 'lines') l),
         (latest.payload ->> 'total_cents')::int,
         exists (select 1 from address_disclosures ad where ad.conversation_id = c.id),
         latest.created_at
    from latest
    join conversations c on c.id = latest.conversation_id
    left join profiles p on p.id = c.buyer_id
   where not exists (select 1 from messages m2
                      where m2.conversation_id = c.id and m2.kind = 'pickup')
     -- A blocked buyer is not someone the cook is still waiting on.
     and not exists (select 1 from blocked_buyers b
                      where b.cook_id = c.cook_id and b.buyer_id = c.buyer_id)
   order by latest.created_at;
$$;

revoke all on function open_orders() from public, anon;
grant execute on function open_orders() to authenticated;

-- The token is dead once the food has changed hands; keeping it means a stale
-- row that APNs will reject later. 034 did the same on claim completion.
create or replace function drop_thread_activity_token() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
begin
  if new.kind = 'pickup' then
    delete from live_activity_tokens where conversation_id = new.conversation_id;
  end if;
  return new;
end $$;

revoke all on function drop_thread_activity_token() from public, anon, authenticated;

-- Both names. The first draft dropped only `messages_drop_activity_token` and
-- created `messages_zz_…`, so a re-run found nothing to drop and then collided
-- with the trigger the first run had made — 42710, on a migration this file
-- claims is safe to re-apply. A drop must name what the create makes.
drop trigger if exists messages_drop_activity_token on messages;
drop trigger if exists messages_zz_drop_activity_token on messages;
-- Fires after the push trigger (alphabetical order within the same timing), so
-- the 'end' event is sent while the token still exists.
create trigger messages_zz_drop_activity_token after insert on messages
  for each row execute function drop_thread_activity_token();
