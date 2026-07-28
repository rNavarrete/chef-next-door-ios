-- 036 — the card's "since" says what it is timing
--
-- Found on a real Lock Screen, which is the only place it could be found: the
-- card read **"ANA HASN'T CONFIRMED SINCE SINCE 2:15 PM"**. `headline` ended
-- in "since" and `sinceLabel` began with it.
--
-- Fixing the headline (in `CookingActivityAttributes`) left a second problem:
-- with the headline now reading "said yes ·", a bare "since 2:15 pm" gives no
-- clue what 2:15 refers to. Confirmed cards say "cooking since 2:15 pm".
--
-- This has to match `MyClaimsView` and `ClaimSentView` exactly, because the
-- card is assembled by whichever path updated it last — a push from here, or
-- the app in the foreground. Two spellings of the same label means the text
-- changes depending on how you happened to look at it.
--
-- A separate migration rather than an edit to 035: that one is already applied,
-- and `db push` will never re-run it. Editing an applied migration changes the
-- file and nothing else.

set search_path = public, extensions;

create or replace function activity_payload_for_claim(p_claim uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_claim   record;
  v_token   record;
  v_cook    record;
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
  if not found then return null; end if;

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

  -- Waiting: since you claimed. Confirmed: how long she has been cooking.
  v_since := (case when v_stage = 'confirmed' then 'cooking since ' else 'since ' end)
    || lower(to_char(
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
