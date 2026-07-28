-- 053 — who turned this light on
--
-- `serving_sessions` has recorded `closed_by` since 005 and nothing at all
-- about the open. That asymmetry went unnoticed until 052, when an anonymous
-- caller was found able to open any cook's kitchen — and the first question,
-- "did anyone actually do this?", turned out to be unanswerable. Three sessions
-- were open at the time; one was a known test and the other two could not be
-- attributed to anything.
--
-- For a product whose entire claim is *this light means someone is really
-- cooking*, the open event deserves at least the provenance the close already
-- has.
--
-- ## Why not just `opened_by uuid`
--
-- The obvious shape is wrong. After 052 only the owning cook can call
-- `open_kitchen`, so a uuid column would equal `cook_id` on every row and carry
-- no information. The question worth answering is not *which cook* — it is
-- **whether the row came through the app at all**, and under whose session.
--
-- So two columns doing different jobs:
--
--   * `opened_by`      — provenance, mirroring `closed_by`. Set by the function
--                        that did it. A row inserted any other way keeps the
--                        default, `'unknown'`, which is exactly the signal that
--                        was missing today.
--   * `opened_by_user` — the `auth.uid()` in force at insert time, stamped by a
--                        trigger rather than by `open_kitchen`, so it is
--                        captured on **every** path including a direct insert.
--                        While the 052 guard holds this equals `cook_id`; the
--                        day it does not, this column is the evidence.
--
-- A NULL there means the insert happened with no session — a migration, a seed,
-- or someone at the SQL console. All legitimate, none of them a cook tapping a
-- burner, and worth being able to tell apart.

set search_path = public, extensions;

alter table serving_sessions
  add column if not exists opened_by text not null default 'unknown';
alter table serving_sessions
  add column if not exists opened_by_user uuid references auth.users(id);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'serving_sessions_opened_by') then
    alter table serving_sessions add constraint serving_sessions_opened_by
      check (opened_by in ('cook', 'widget', 'admin', 'seed', 'unknown'));
  end if;
end $$;

-- Existing rows predate the column and genuinely are unknown. Saying so is
-- more useful than backfilling them to 'cook', which would assert something
-- nobody checked.
comment on column serving_sessions.opened_by is
  'How the session was opened. ''unknown'' means it did not come through '
  'open_kitchen — a seed, a migration, or a direct insert.';

-- ---------------------------------------------------------------------------
-- Stamped by a trigger, so no insert path can skip it.
-- ---------------------------------------------------------------------------
create or replace function stamp_session_opener() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
begin
  -- Only fills what the caller left blank: `open_kitchen` sets `opened_by`
  -- itself, and a future admin tool should be able to say so too.
  new.opened_by_user := coalesce(new.opened_by_user, auth.uid());
  return new;
end $$;

revoke all on function stamp_session_opener() from public, anon, authenticated;

drop trigger if exists serving_sessions_stamp_opener on serving_sessions;
create trigger serving_sessions_stamp_opener before insert on serving_sessions
  for each row execute function stamp_session_opener();

-- ---------------------------------------------------------------------------
-- `open_kitchen` says it was a cook. Otherwise unchanged from 052 — the
-- NULL-safe guard and the explicit unauthenticated check both stay.
-- ---------------------------------------------------------------------------
create or replace function open_kitchen(p_kitchen uuid, p_note text default null)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_cook uuid; v_session uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select cook_id into v_cook from kitchens where id = p_kitchen;
  -- `is distinct from`, NOT `<>` — see migration 052.
  if v_cook is null or v_cook is distinct from auth.uid() then
    raise exception 'not authorized';
  end if;

  select id into v_session
    from serving_sessions where cook_id = v_cook and closed_at is null;

  if v_session is not null then
    update serving_sessions set last_confirmed_at = now() where id = v_session;
  else
    insert into serving_sessions (cook_id, kitchen_id, opened_by)
    values (v_cook, p_kitchen, 'cook')
    returning id into v_session;
  end if;

  update cooks
     set serving_status = 'serving',
         serving_note = coalesce(nullif(trim(coalesce(p_note, '')), ''), serving_note)
   where id = v_cook;

  return v_session;
end $$;

revoke all on function open_kitchen(uuid, text) from public, anon;
grant execute on function open_kitchen(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The question this exists to answer, as one call.
-- ---------------------------------------------------------------------------
create or replace function suspicious_sessions()
returns table (
  cook          text,
  opened_at     timestamptz,
  opened_by     text,
  matched_owner boolean
)
language sql stable security definer
set search_path = public, extensions as $$
  select co.display_name, s.opened_at, s.opened_by,
         -- False is the alarm: a session whose opener was not the cook who
         -- owns the kitchen. NULL means no session was in force at all.
         s.opened_by_user is not distinct from s.cook_id
    from serving_sessions s
    join cooks co on co.id = s.cook_id
   where s.opened_by <> 'cook'
      or s.opened_by_user is distinct from s.cook_id
   order by s.opened_at desc;
$$;

revoke all on function suspicious_sessions() from public, anon, authenticated;

comment on function suspicious_sessions is
  'Sessions that did not come from their own cook through open_kitchen. Owner '
  'only — there is no client grant, because the answer is an incident '
  'question, not a product surface.';
