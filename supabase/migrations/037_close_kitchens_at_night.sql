-- 037 — actually turn the burners off at 8pm
--
-- `auto_close_stale_sessions` (005) has existed since M0 and **nothing has
-- ever called it**. Sessions opened yesterday were still open this morning,
-- showing "LIT AT 12:15 PM" on a card at 11am — a kitchen advertised as
-- cooking twenty hours after the cook went to bed. This is the exact failure
-- the decay ladder exists to prevent, sitting one unscheduled job away.
--
-- ## It also didn't do what the app promises
--
-- `KitchenView` tells cooks "If you forget, we turn the burner off at 8 pm."
-- The function closes anything open more than **12 hours** — a different rule
-- with a different meaning. A cook lighting up at 9am was closed at 9pm, and
-- one lighting at 6pm stayed lit past midnight. Neither is what they were told.
--
-- So: two jobs, both hourly.
--
--   * `close_kitchens_for_the_night` — the promise. Closes everything open
--     once it is 8pm in Los Angeles.
--   * `auto_close_stale_sessions` — the safety net, unchanged. Catches
--     anything that survives, e.g. because cron missed a night.
--
-- ## Why hourly with a local-time check, rather than a nightly UTC schedule
--
-- pg_cron schedules in UTC. 8pm Pacific is 03:00 UTC in summer and 04:00 UTC
-- in winter, so a fixed UTC time is wrong for half the year — cooks would be
-- closed an hour early or late every time the clocks moved. Checking the local
-- hour inside the function is DST-correct by construction.

set search_path = public, extensions;

create or replace function close_kitchens_for_the_night()
returns integer language plpgsql security definer
set search_path = public, extensions as $$
declare v_count integer;
begin
  -- Nothing to do until the evening, wherever the caller thinks it is.
  if extract(hour from (now() at time zone 'America/Los_Angeles')) < 20 then
    return 0;
  end if;

  with closed as (
    update serving_sessions
       set closed_at = now(), closed_by = 'auto_8pm', status = 'closed'
     where closed_at is null
    returning cook_id
  )
  update cooks set serving_status = 'closed'
   where id in (select cook_id from closed);

  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function close_kitchens_for_the_night() from public, anon, authenticated;
revoke all on function auto_close_stale_sessions() from public, anon, authenticated;

comment on function close_kitchens_for_the_night is
  'Closes every open serving session once it is 8pm in Los Angeles. Runs '
  'hourly; the local-hour check rather than a UTC schedule is what makes it '
  'correct across daylight saving.';

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    perform cron.unschedule('kitchens-night-close')
      where exists (select 1 from cron.job where jobname = 'kitchens-night-close');
    perform cron.unschedule('kitchens-stale-close')
      where exists (select 1 from cron.job where jobname = 'kitchens-stale-close');

    perform cron.schedule('kitchens-night-close', '5 * * * *',
                          'select public.close_kitchens_for_the_night()');
    perform cron.schedule('kitchens-stale-close', '35 * * * *',
                          'select public.auto_close_stale_sessions()');

    raise notice 'burner auto-off scheduled (hourly)';
  else
    raise notice 'pg_cron unavailable — burners will NOT auto-close.';
  end if;
end $$;
