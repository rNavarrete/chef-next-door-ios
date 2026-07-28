-- 033 — keep the register fresh, and make it obvious when it isn't
--
-- `refresh_permit_registry` (030) has to run repeatedly or "verified" quietly
-- decays into "was verified once, months ago" — a permit gets revoked and the
-- badge stays up, which is the exact failure verification exists to prevent.
--
-- Scheduled inside Postgres with pg_cron + pg_net rather than from CI or a
-- runner, for one reason above convenience: **pg_cron executes as the database
-- owner, so it can call refresh_permit_registry() directly.** No service-role
-- key in a repo secret, in an env file, or anywhere else it can leak. The only
-- thing leaving the database is a GET to a public county URL.
--
-- ## Why two jobs and not one
--
-- pg_net is asynchronous: `net.http_get()` returns a request id and a
-- background worker writes the response to `net._http_response` some seconds
-- later. You cannot fetch and apply in one transaction.
--
-- It also expires responses after a few hours. So a single daily job that
-- fetched and then tried to read *yesterday's* response would find it already
-- swept away — the naive version of this is broken in a way that only shows up
-- after a day of running. Two jobs, minutes apart, stay well inside that
-- window.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- One row, tracking the in-flight request and the last outcome.
-- ---------------------------------------------------------------------------
create table if not exists permit_sync_state (
  only_row     boolean primary key default true check (only_row),
  request_id   bigint,
  requested_at timestamptz,
  last_result  text,
  last_ok_at   timestamptz
);

insert into permit_sync_state (only_row) values (true) on conflict do nothing;

alter table permit_sync_state enable row level security;
revoke all on permit_sync_state from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Step 1 — ask the county for the current list.
-- ---------------------------------------------------------------------------
create or replace function fetch_permit_registry()
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare v_id bigint;
begin
  -- EXECUTE so the reference to net.* is resolved at call time. The function
  -- can then be created on a plain Postgres (CI, a local container) that has
  -- no pg_net, and simply fail if anything actually calls it there.
  execute 'select net.http_get(url := $1, timeout_milliseconds := 20000)'
     into v_id
    using 'http://publichealth.lacounty.gov/eh/data/mehko.json';

  update permit_sync_state
     set request_id = v_id, requested_at = now();
  return v_id;
exception when others then
  update permit_sync_state set last_result = 'fetch failed: ' || sqlerrm;
  raise;
end $$;

-- ---------------------------------------------------------------------------
-- Step 2 — apply whatever came back.
-- ---------------------------------------------------------------------------
create or replace function apply_permit_registry()
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_req    bigint;
  v_status integer;
  v_body   text;
  v_counts record;
  v_msg    text;
begin
  select request_id into v_req from permit_sync_state;
  if v_req is null then
    return 'nothing in flight';
  end if;

  execute 'select status_code, content from net._http_response where id = $1'
     into v_status, v_body using v_req;

  if v_body is null then
    -- Either still in flight, or expired before we looked. Leaving request_id
    -- set would wedge it forever, so clear and let tomorrow try again.
    update permit_sync_state
       set last_result = 'no response for request ' || v_req, request_id = null;
    return 'no response yet';
  end if;

  if v_status <> 200 then
    update permit_sync_state
       set last_result = 'http ' || v_status, request_id = null;
    return 'http ' || v_status;
  end if;

  select * into v_counts from refresh_permit_registry(v_body::jsonb);

  v_msg := format('inserted %s, removed %s, demoted %s',
                  v_counts.inserted, v_counts.removed, v_counts.demoted);
  update permit_sync_state
     set last_result = v_msg, last_ok_at = now(), request_id = null;
  return v_msg;
exception when others then
  update permit_sync_state
     set last_result = 'apply failed: ' || sqlerrm, request_id = null;
  raise;
end $$;

revoke all on function fetch_permit_registry() from public, anon, authenticated;
revoke all on function apply_permit_registry() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- How stale is the register?
--
-- Readable by anyone, because the app shows the date on the badge explainer.
-- A promise that we "re-check daily" is a claim about our infrastructure;
-- the date is a fact, and a stale one is visible to users before it is
-- visible to us.
-- ---------------------------------------------------------------------------
create or replace function permit_registry_freshness()
returns table (synced_at timestamptz, age_hours numeric, is_fresh boolean)
language sql stable set search_path = public, extensions as $$
  select max(r.synced_at),
         round(extract(epoch from (now() - max(r.synced_at))) / 3600.0, 1),
         max(r.synced_at) > now() - interval '3 days'
    from permit_registry r;
$$;

grant execute on function permit_registry_freshness() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Scheduling. Guarded, because CI and any local container run a plain Postgres
-- with neither extension, and the schema must still apply cleanly there.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then

    create extension if not exists pg_cron;
    create extension if not exists pg_net;

    perform cron.unschedule('permit-registry-fetch')
      where exists (select 1 from cron.job where jobname = 'permit-registry-fetch');
    perform cron.unschedule('permit-registry-apply')
      where exists (select 1 from cron.job where jobname = 'permit-registry-apply');

    -- 09:10 and 09:20 UTC — roughly 2am Pacific, after the county's own
    -- overnight publish and well clear of anyone cooking.
    perform cron.schedule('permit-registry-fetch', '10 9 * * *',
                          'select public.fetch_permit_registry()');
    perform cron.schedule('permit-registry-apply', '20 9 * * *',
                          'select public.apply_permit_registry()');

    raise notice 'permit registry refresh scheduled (fetch 09:10 UTC, apply 09:20 UTC)';
  else
    raise notice 'pg_cron/pg_net unavailable — refresh not scheduled. Run scripts/refresh_permit_registry.sh instead.';
  end if;
end $$;
