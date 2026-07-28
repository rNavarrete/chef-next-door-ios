-- 035 — tell the Lock Screen when the claim changes
--
-- The card can only change while the phone is in a pocket if something pushes
-- it. `answer_claim` is the moment that matters: the cook says yes, the address
-- becomes available, and the buyer is already walking.
--
-- ## Why an Edge Function and not pg_net alone
--
-- APNs authenticates with an ES256-signed JWT. `pgcrypto` cannot sign ECDSA, so
-- unlike the permit-register sync — which pg_net performs entirely inside the
-- database — this needs somewhere that can do crypto. The Edge Function is that
-- and nothing more: **it is transport, not logic.** Everything about *what* the
-- card should say is decided here, in SQL, next to the data.
--
-- ## The address travels through Apple
--
-- A confirmed card shows the cook's street address, so the push payload
-- contains it, which means it transits APNs. That is inherent to Live Activity
-- push — there is no end-to-end encrypted variant — and it is worth stating
-- plainly given how carefully `kitchen_locations` is guarded everywhere else.
-- The payload is only ever built for a buyer who already holds a
-- cook-confirmed claim, i.e. someone `reveal_address` would serve anyway.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Everything the card needs, assembled server-side.
--
-- Mirrors `CookingActivityAttributes.ContentState` field for field. If that
-- Swift type changes, this changes with it — a mismatch is not an error, the
-- card simply ignores the update, which is the worst kind of failure.
-- ---------------------------------------------------------------------------
create or replace function activity_payload_for_claim(p_claim uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_claim   record;
  v_token   record;
  v_cook    record;
  -- Scalars, not a record: a plpgsql `record` that is never assigned cannot be
  -- referenced at all, so the waiting case — where there is deliberately no
  -- address — raised "tuple structure of a not-yet-assigned record is
  -- indeterminate" rather than producing a null address line.
  v_street  text;
  v_city    text;
  v_zip     text;
  v_lat     double precision;
  v_lon     double precision;
  v_items   text;
  v_total   integer;
  v_stage   text;
  v_since   text;
begin
  select c.*, ss.opened_at, ss.last_confirmed_at, ss.closed_at
    into v_claim
    from claims c
    join serving_sessions ss on ss.id = c.serving_session_id
   where c.id = p_claim;
  if not found then return null; end if;

  select * into v_token from live_activity_tokens where claim_id = p_claim;
  if not found then return null; end if;          -- nothing to push to

  select co.display_name, k.id as kitchen_id
    into v_cook
    from cooks co join kitchens k on k.cook_id = co.id
   where co.id = v_claim.cook_id;

  select string_agg(ci.quantity || '× ' || coalesce(mi.name_es, mi.name_en), ', '),
         sum(ci.quantity * mi.amount_cents)
    into v_items, v_total
    from claim_items ci join menu_items mi on mi.id = ci.menu_item_id
   where ci.claim_id = p_claim;

  v_stage := case when v_claim.status = 'confirmed' then 'confirmed' else 'waiting' end;

  if v_stage = 'confirmed' then
    select kl.street, kl.city, kl.postal_code,
           ST_Y(kl.exact_point::geometry),
           ST_X(kl.exact_point::geometry)
      into v_street, v_city, v_zip, v_lat, v_lon
      from kitchen_locations kl
     where kl.kitchen_id = v_cook.kitchen_id;
  end if;

  -- Same rule as the app: waiting shows when *you* claimed, confirmed shows
  -- how long the cook has been cooking.
  v_since := 'since ' || lower(to_char(
    case when v_stage = 'confirmed' then v_claim.opened_at else v_claim.created_at end
      at time zone 'America/Los_Angeles', 'FMHH12:MI am'));

  return jsonb_build_object(
    'token', v_token.token,
    'environment', v_token.environment,
    'claimId', p_claim,
    'contentState', jsonb_build_object(
      'stage', v_stage,
      'cookIsCooking', freshness_of(v_claim.last_confirmed_at, v_claim.closed_at) in ('lit','dimming'),
      'itemSummary', coalesce(v_items, 'Your order'),
      'priceSummary', case when v_total is null then ''
                           else '$' || to_char(v_total / 100.0, 'FM999990.00') end,
      'addressLine', case when v_street is null then ''
                          else v_street || ', ' || v_city || ' ' || v_zip end,
      'sinceLabel', v_since,
      'directionsURL', case when v_lat is null then null
                            else 'maps://?daddr=' || v_lat || ',' || v_lon end
    )
  );
end $$;

revoke all on function activity_payload_for_claim(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Fire on the transitions the buyer needs to see.
--
-- Configuration lives in `app_secrets`, which no client can read. Absent
-- configuration is a silent no-op rather than an error: the trigger must never
-- be able to fail a cook's "Sí".
-- ---------------------------------------------------------------------------
create or replace function push_claim_update() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url     text;
  v_secret  text;
  v_payload jsonb;
begin
  if new.status = old.status then return new; end if;
  if new.status not in ('confirmed', 'cancelled', 'no_show') then return new; end if;

  -- EVERYTHING below is inside one handler. Nothing about sending a push may
  -- roll back the cook saying yes — building the payload reads five tables and
  -- any of them can surprise us, so "assemble" belongs inside the net that
  -- "send" is already under. An earlier version guarded only the HTTP call and
  -- a payload error would have failed answer_claim outright.
  begin
    select value into v_url    from app_secrets where key = 'push_fn_url';
    select value into v_secret from app_secrets where key = 'push_fn_secret';
    if v_url is null or v_secret is null then return new; end if;

    v_payload := activity_payload_for_claim(new.id);
    if v_payload is null then return new; end if;   -- no token registered

    -- A declined claim ends the card rather than updating it.
    v_payload := v_payload || jsonb_build_object(
      'event', case when new.status = 'confirmed' then 'update' else 'end' end
    );

    perform net.http_post(
      url := v_url,
      body := v_payload,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-lk-secret', v_secret
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    raise warning 'push_claim_update failed for claim %: %', new.id, sqlerrm;
  end;

  return new;
end $$;

drop trigger if exists claims_push_update on claims;
create trigger claims_push_update
  after update of status on claims
  for each row execute function push_claim_update();
