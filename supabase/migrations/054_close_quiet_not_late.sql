-- 054 — close what has gone quiet, not what is late
--
-- Two rules were switching cooks off for reasons that had nothing to do with
-- whether they were still cooking:
--
--   * `close_kitchens_for_the_night` (037) — everything open, once it is 8pm in
--     Los Angeles.
--   * `auto_close_stale_sessions` (005) — anything open more than 12 hours,
--     measured from `opened_at` and **ignoring confirmation entirely**. A cook
--     actively serving, toggling dishes sold out all afternoon, was closed at
--     the twelve-hour mark anyway.
--
-- Both were written to solve *stale availability* — the failure where a cook
-- forgets and buyers drive to a cold kitchen — and both implemented it as a
-- curfew. Those are different things. A taquero serving until 2am is not stale;
-- a kitchen opened at noon and abandoned by 3pm is, whatever the clock says.
--
-- ## One rule
--
-- Close a session that has not been **confirmed** in ten hours. Confirmation is
-- already defined and already deliberate (007): only actions that assert
-- current service count, which is why marking an old claim picked up at 9pm
-- does not relight a kitchen that went cold at noon.
--
-- Ten hours sits well past `unconfirmed` (6h), so the decay ladder has already
-- stopped asserting the cook is there before anything is closed. The close is
-- tidying up, not the first line of defence — which is the correct order, since
-- the ladder degrades a claim gracefully and closing it is final.
--
-- No hour of the day appears anywhere below. Serving at 3am is a decision a
-- cook is entitled to make.

set search_path = public, extensions;

create or replace function close_quiet_kitchens()
returns integer language plpgsql security definer
set search_path = public, extensions as $$
declare v_count integer;
begin
  with closed as (
    update serving_sessions
       set closed_at = now(), closed_by = 'auto_quiet', status = 'closed'
     where closed_at is null
       -- `last_confirmed_at`, not `opened_at`. The old rule punished a long
       -- shift; this one only catches an unattended one.
       and last_confirmed_at < now() - interval '10 hours'
    returning cook_id
  )
  update cooks set serving_status = 'closed'
   where id in (select cook_id from closed);

  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function close_quiet_kitchens() from public, anon, authenticated;

comment on function close_quiet_kitchens is
  'Closes sessions unconfirmed for ten hours, at any hour of the day. Replaces '
  'the 8pm curfew and the 12-hour cap, neither of which measured whether the '
  'cook was still cooking.';

comment on column serving_sessions.closed_by is
  'How the session ended: ''cook'', ''auto_quiet'', or ''admin''.';

-- ---------------------------------------------------------------------------
-- Retire the curfew.
-- ---------------------------------------------------------------------------
drop function if exists close_kitchens_for_the_night();
drop function if exists auto_close_stale_sessions();

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    perform cron.unschedule('kitchens-night-close')
      where exists (select 1 from cron.job where jobname = 'kitchens-night-close');
    perform cron.unschedule('kitchens-stale-close')
      where exists (select 1 from cron.job where jobname = 'kitchens-stale-close');
    perform cron.unschedule('kitchens-quiet-close')
      where exists (select 1 from cron.job where jobname = 'kitchens-quiet-close');

    -- Hourly. There is no longer a local-time check to get right across
    -- daylight saving, which was the only reason 037 ran hourly rather than
    -- nightly — an elapsed-time rule is timezone-free by construction.
    perform cron.schedule('kitchens-quiet-close', '5 * * * *',
                          'select public.close_quiet_kitchens()');

    raise notice 'quiet-close scheduled hourly; 8pm curfew removed';
  else
    raise notice 'pg_cron unavailable — kitchens will NOT auto-close.';
  end if;
end $$;
