-- 030 — permit verification without a human reviewer
--
-- M4 assumed an admin queue: cook uploads a document, someone looks at it.
-- There is no someone. And a document upload is exactly the hoop that stops a
-- cook finishing signup.
--
-- LA County publishes the permitted-MEHKO register as machine-readable JSON —
-- `publichealth.lacounty.gov/eh/data/mehko.json`, 382 records, updated daily,
-- fields `name / city / zip / recordid / startdate`. So the cook types the
-- permit number they already have on a piece of paper, and we check it against
-- the county's own list. No document, no reviewer, no waiting.
--
-- ## What this proves, and what it does not
--
-- The register is **public**. Anyone can read a real permit number off it. So a
-- match proves *"a permit with this number exists, at this city and ZIP"* — it
-- does **not** prove the person typing it holds that permit. Three things
-- narrow the gap, and none of them closes it:
--
--   1. `recordid` is unique here — one permit, one cook, first claim wins. A
--      second cook cannot attach the same number at all.
--   2. The permit's city and ZIP must match the kitchen's, so a stolen number
--      only works for someone on the same street.
--   3. Every attempt is logged, matched or not, so a pattern is visible.
--
-- That is a real bar — impersonation requires a neighbour's permit number, the
-- same ZIP, and getting there first — but it is not identity verification, and
-- the badge copy must not imply otherwise. `PRD.md` §8.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- A local mirror of the county register.
-- ---------------------------------------------------------------------------
create table if not exists permit_registry (
  record_id   text primary key,          -- 'PR0366690'
  name        text not null,
  city        text not null,
  postal_code text,
  start_date  date,
  agency_id   uuid references enforcement_agencies(id),
  synced_at   timestamptz not null default now()
);

create index if not exists permit_registry_city_idx on permit_registry (upper(city));

alter table permit_registry enable row level security;

-- Readable so a cook can be told "that number isn't on the county list yet"
-- rather than a blank failure. It is public data; the county publishes it.
drop policy if exists permit_registry_read on permit_registry;
create policy permit_registry_read on permit_registry for select using (true);
grant select on permit_registry to anon, authenticated;

comment on table permit_registry is
  'Mirror of LA County''s published MEHKO register. Refreshed by '
  'refresh_permit_registry(); never written by clients.';

-- ---------------------------------------------------------------------------
-- Refresh from the county payload.
--
-- Takes the JSON exactly as published so the caller is a dumb pipe — anything
-- that can fetch a URL and call an RPC can run this (pg_cron + pg_net, a CI
-- job, a laptop). Deliberately NOT client-callable.
--
-- Permits that vanish from the register are deleted here and demoted below:
-- the county removes closed and revoked operations, and a badge that outlives
-- the permit is worse than no badge.
-- ---------------------------------------------------------------------------
create or replace function refresh_permit_registry(p_payload jsonb)
returns table (inserted integer, removed integer, demoted integer)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_before integer;
  v_after  integer;
  v_removed integer;
  v_demoted integer;
begin
  if jsonb_typeof(p_payload -> 'programs') <> 'array' then
    raise exception 'payload has no programs array';
  end if;
  -- A truncated fetch must not wipe the register and strip every badge.
  if jsonb_array_length(p_payload -> 'programs') < 50 then
    raise exception 'refusing to refresh from a suspiciously small payload (% records)',
      jsonb_array_length(p_payload -> 'programs');
  end if;

  select count(*) into v_before from permit_registry;

  create temporary table incoming (
    record_id text primary key, name text, city text, postal_code text, start_date date
  ) on commit drop;

  insert into incoming (record_id, name, city, postal_code, start_date)
  select upper(trim(p ->> 'recordid')),
         trim(p ->> 'name'),
         trim(p ->> 'city'),
         nullif(trim(p ->> 'zip'), ''),
         nullif(p ->> 'startdate', '')::date
    from jsonb_array_elements(p_payload -> 'programs') p
   where nullif(trim(p ->> 'recordid'), '') is not null
  on conflict (record_id) do nothing;

  insert into permit_registry (record_id, name, city, postal_code, start_date, agency_id, synced_at)
  select i.record_id, i.name, i.city, i.postal_code, i.start_date,
         agency_for_city(i.city), now()
    from incoming i
  on conflict (record_id) do update
    set name = excluded.name, city = excluded.city,
        postal_code = excluded.postal_code, start_date = excluded.start_date,
        agency_id = excluded.agency_id, synced_at = now();

  delete from permit_registry r
   where not exists (select 1 from incoming i where i.record_id = r.record_id);
  get diagnostics v_removed = row_count;

  -- A cook whose permit left the register loses the badge automatically. This
  -- is the half of verification that a one-off document check never gives you.
  update cooks c
     set permit_status = 'expired'
   where c.permit_status = 'verified'
     and c.permit_number is not null
     and not exists (
       select 1 from permit_registry r
        where r.record_id = upper(trim(c.permit_number))
     );
  get diagnostics v_demoted = row_count;

  select count(*) into v_after from permit_registry;
  return query select v_after - v_before + v_removed, v_removed, v_demoted;
end $$;

revoke all on function refresh_permit_registry(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Every attempt, matched or not. A stolen-number pattern is only visible if
-- the misses are recorded too.
-- ---------------------------------------------------------------------------
create table if not exists permit_checks (
  id          uuid primary key default gen_random_uuid(),
  cook_id     uuid references cooks(id) on delete cascade,
  submitted   text not null,
  outcome     text not null,   -- 'verified' | 'not_found' | 'wrong_area' | 'already_claimed' | 'agency_not_covered'
  checked_at  timestamptz not null default now()
);

alter table permit_checks enable row level security;
-- No client policy at all: this is an abuse signal, and a cook who could read
-- it would learn which numbers are unclaimed.
revoke all on permit_checks from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The check itself.
-- ---------------------------------------------------------------------------
create or replace function verify_permit(p_number text)
returns table (outcome text, registered_name text, agency_name text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_cook    uuid := auth.uid();
  v_norm    text := upper(regexp_replace(coalesce(p_number, ''), '[^A-Za-z0-9]', '', 'g'));
  v_city    text;
  v_zip     text;
  v_agency  uuid;
  v_mehko   boolean;
  r         permit_registry%rowtype;
  v_outcome text;
begin
  if v_cook is null then raise exception 'not authenticated'; end if;
  if v_norm = '' then raise exception 'permit number required'; end if;

  select k.city, kl.postal_code, k.agency_id, a.mehko_opted_in
    into v_city, v_zip, v_agency, v_mehko
    from kitchens k
    join kitchen_locations kl on kl.kitchen_id = k.id
    join enforcement_agencies a on a.id = k.agency_id
   where k.cook_id = v_cook;

  if v_city is null then raise exception 'no kitchen to check against'; end if;

  select * into r from permit_registry where record_id = v_norm;

  if not found then
    -- Pasadena, Long Beach and Vernon run their own health departments and do
    -- not appear in the county register at all, so "not found" there means
    -- "we cannot check", not "not permitted". Saying otherwise would accuse a
    -- cook of something on the strength of a dataset that never covered them.
    v_outcome := case when v_mehko then 'not_found' else 'agency_not_covered' end;

  elsif exists (
    select 1 from cooks c
     where upper(regexp_replace(coalesce(c.permit_number, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
       and c.id <> v_cook
       and c.permit_status = 'verified'
  ) then
    v_outcome := 'already_claimed';

  elsif upper(r.city) <> upper(v_city)
        and (r.postal_code is null or v_zip is null or r.postal_code <> v_zip) then
    v_outcome := 'wrong_area';

  else
    v_outcome := 'verified';
  end if;

  insert into permit_checks (cook_id, submitted, outcome) values (v_cook, v_norm, v_outcome);

  update cooks
     set permit_number = v_norm,
         permit_status = case when v_outcome = 'verified'
                              then 'verified'::permit_status
                              else 'pending'::permit_status end
   where id = v_cook;

  return query
    select v_outcome,
           case when v_outcome = 'verified' then r.name else null end,
           (select a.name from enforcement_agencies a where a.id = v_agency);
end $$;

revoke all on function verify_permit(text) from public, anon;
grant execute on function verify_permit(text) to authenticated;

comment on function verify_permit is
  'Checks a permit number against the mirrored county register. Proves the '
  'permit exists at that city/ZIP and is unclaimed here — NOT that the caller '
  'holds it. Badge copy must not overstate this.';
