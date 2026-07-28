-- 005 — serving sessions
--
-- An append-only record of a PERIOD OF SERVICE.
--
-- This is not the scheduled "drop" object we removed: no future scheduling, no
-- declared capacity, no pickup window. It records what happened, not what is
-- planned (PRD §5). It exists because putting availability on the mutable cook
-- row erased history — nothing could say WHICH service period a claim or a
-- complaint belonged to.

set search_path = public, extensions;

create table serving_sessions (
  id                uuid primary key default gen_random_uuid(),
  cook_id           uuid not null references cooks(id) on delete cascade,
  kitchen_id        uuid not null references kitchens(id),
  opened_at         timestamptz not null default now(),  -- DISPLAYED
  last_confirmed_at timestamptz not null default now(),  -- DRIVES THE DECAY TIER
  closed_at         timestamptz,
  closed_by         text,                                 -- 'cook' | 'auto_8pm' | 'admin'
  status            serving_status not null default 'serving',

  constraint closed_after_opened check (closed_at is null or closed_at >= opened_at)
);

-- At most one open session per cook.
create unique index serving_sessions_one_open_per_cook
  on serving_sessions (cook_id) where closed_at is null;
create index serving_sessions_open_freshness_idx
  on serving_sessions (last_confirmed_at) where closed_at is null;
create index serving_sessions_cook_history_idx
  on serving_sessions (cook_id, opened_at desc);

comment on column serving_sessions.opened_at is
  'What the UI shows: "Cooking · since 9:40 am". Absolute clock time, always.';
comment on column serving_sessions.last_confirmed_at is
  'Drives the decay tier. Bumped ONLY by activity asserting current service (007).';

-- ---------------------------------------------------------------------------
-- Open / close are atomic procedures, never client-side field writes.
-- ---------------------------------------------------------------------------

create or replace function open_kitchen(p_kitchen uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_cook uuid; v_session uuid;
begin
  select cook_id into v_cook from kitchens where id = p_kitchen;
  if v_cook is null or v_cook <> auth.uid() then
    raise exception 'not authorized';
  end if;

  -- Idempotent: re-opening while already open just confirms the session,
  -- so a double-tap on the burner can never create a second one.
  select id into v_session
    from serving_sessions where cook_id = v_cook and closed_at is null;

  if v_session is not null then
    update serving_sessions set last_confirmed_at = now() where id = v_session;
  else
    insert into serving_sessions (cook_id, kitchen_id)
    values (v_cook, p_kitchen)
    returning id into v_session;
  end if;

  update cooks
     set serving_status = 'serving',
         serving_note = coalesce(p_note, serving_note)
   where id = v_cook;

  return v_session;
end $$;

create or replace function close_kitchen(p_reason text default 'cook')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update serving_sessions
     set closed_at = now(), closed_by = p_reason, status = 'closed'
   where cook_id = auth.uid() and closed_at is null;

  update cooks set serving_status = 'closed' where id = auth.uid();
end $$;

-- The 8pm auto-off. Scheduled job; also the safety net behind the ~8h nudge.
create or replace function auto_close_stale_sessions()
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare v_count integer;
begin
  with closed as (
    update serving_sessions
       set closed_at = now(), closed_by = 'auto_8pm', status = 'closed'
     where closed_at is null
       and opened_at < now() - interval '12 hours'
    returning cook_id
  )
  update cooks set serving_status = 'closed'
   where id in (select cook_id from closed);
  get diagnostics v_count = row_count;
  return v_count;
end $$;
