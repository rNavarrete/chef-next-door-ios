-- 048 — 045 was speaking the wrong protocol to the Edge Function
--
-- Three mismatches, none of which fail loudly. Found by reading 036 and the
-- function side by side while adding alert push, not by anything going wrong —
-- which is the point: every one of these produces a card that simply never
-- updates.
--
--   1. The payload key was `state`. The function reads `contentState` and
--      returns 400 "missing token or contentState" when it is absent.
--   2. The auth header was `Authorization: Bearer …`. The function checks
--      `x-lk-secret` and returns 401 to anything else. 035 had this right.
--   3. There was no thread id, so the function's stale-token cleanup had
--      nothing to delete by — a token Apple had retired would be retried on
--      every future message, forever.
--
-- Also drops `headline`, which the function ignores: it is a computed property
-- on `ContentState` in Swift, and sending a second copy from the server invites
-- the two to disagree.
--
-- Fixed forward rather than by editing 045, which is already applied. Editing
-- an applied migration changes nothing on a live database and quietly desyncs
-- the file from what is actually running — the failure mode this project has
-- hit before (035 → 036).

set search_path = public, extensions;

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
  if not found then return null; end if;

  select co.display_name, k.id as kitchen_id
    into v_cook
    from cooks co join kitchens k on k.cook_id = co.id
   where co.id = v_thread.cook_id;

  select m.payload, m.created_at into v_order
    from messages m
   where m.conversation_id = p_thread and m.kind = 'order'
   order by m.created_at desc limit 1;
  if not found then return null; end if;

  -- `in ('lit','dimming')`: the lamp goes out at *unconfirmed*, not at closed.
  select (s.id is not null
          and freshness_of(s.last_confirmed_at, s.closed_at) in ('lit','dimming'))
    into v_cooking
    from cooks c
    left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
   where c.id = v_thread.cook_id;

  v_shared := exists (select 1 from address_disclosures ad
                       where ad.conversation_id = p_thread);
  v_stage  := case when v_shared then 'confirmed' else 'waiting' end;

  -- Still read only behind the disclosure check. A push does not pass through
  -- RLS, so this remains the whole gate.
  if v_shared then
    select kl.street, kl.city, kl.postal_code,
           ST_Y(kl.exact_point::geometry), ST_X(kl.exact_point::geometry)
      into v_street, v_city, v_zip, v_lat, v_lon
      from kitchen_locations kl where kl.kitchen_id = v_cook.kitchen_id;
    v_address := v_street || ', ' || v_city || ' ' || v_zip;
  end if;

  v_since := 'since ' || lower(to_char(v_order.created_at at time zone 'America/Los_Angeles',
                                       'FMHH:MI am'));

  return jsonb_build_object(
    'token',       v_token.token,
    'environment', v_token.environment,
    -- What the function actually reads. `threadId` replaces `claimId`, and is
    -- what its 410-cleanup deletes by.
    'threadId',    p_thread,
    'contentState', jsonb_build_object(
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
    )
  );
end $$;

revoke all on function activity_payload_for_thread(uuid) from public, anon, authenticated;

create or replace function push_thread_activity() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url     text;
  v_secret  text;
  v_payload jsonb;
begin
  if new.kind not in ('address', 'pickup') then return new; end if;

  begin
    select value into v_url    from app_secrets where key = 'push_fn_url';
    select value into v_secret from app_secrets where key = 'push_fn_secret';
    if v_url is null or v_secret is null then return new; end if;

    v_payload := activity_payload_for_thread(new.conversation_id);
    if v_payload is null then return new; end if;

    v_payload := v_payload || jsonb_build_object(
      'event', case when new.kind = 'pickup' then 'end' else 'update' end
    );

    perform net.http_post(
      url     := v_url,
      body    := v_payload,
      -- `x-lk-secret`, matching what the function checks. An Authorization
      -- header gets a 401 and the card never moves.
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-lk-secret', v_secret
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    raise warning 'live activity push failed for conversation %: %',
      new.conversation_id, sqlerrm;
  end;

  return new;
end $$;

revoke all on function push_thread_activity() from public, anon, authenticated;
