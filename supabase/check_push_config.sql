-- Push diagnostics. Paste into the Supabase SQL editor when a notification
-- doesn't arrive.
--
-- Every failure in the push path is silent by construction: the triggers wrap
-- everything in an exception handler so a failed push can never cost a message,
-- and the Edge Function answers a bad request with a 4xx nobody reads. That is
-- the right trade — but it means "no notification" and "everything is fine"
-- look identical from the app. This is the only place to tell them apart.
--
-- **One statement, no psql meta-commands.** The dashboard sends raw SQL to
-- Postgres, so `\echo` is a syntax error there, and it renders only the last
-- result set — so four separate selects would show one table and hide the rest.
--
-- Run as the owner (the editor's default). `app_secrets` is deliberately
-- unreadable to every client role, so this cannot be an in-app screen. No
-- secret value is ever printed, only whether one is set.

select section, item, detail
from (
  -- 1. Secrets the triggers need. A missing row means the trigger returns
  --    early and no push is attempted — the usual cause of total silence.
  select 1 as ord, '1. secrets' as section, k as item,
         coalesce(
           (select case when trim(value) = '' then 'EMPTY — push disabled'
                        else 'set (' || length(value) || ' chars)' end
              from app_secrets where key = k),
           'MISSING — no push will be sent') as detail
    from (values ('push_fn_url'), ('push_fn_secret')) v(k)

  union all

  -- 2. Expect three, and the order is the point: the alert fires first so it
  --    cannot be skipped by a later trigger throwing.
  select 2, '2. triggers on messages', tgname,
         case when tgenabled = 'O' then 'enabled' else 'DISABLED' end
    from pg_trigger
   where tgrelid = 'messages'::regclass and not tgisinternal

  union all

  -- 3. Zero device tokens means the app never got permission, or never reached
  --    the prompt. Zero activity tokens means no Lock Screen card is live.
  select 3, '3. registered to receive', 'device_tokens',
         count(*) || ' rows, ' || count(distinct user_id) || ' people'
    from device_tokens

  union all

  select 3, '3. registered to receive', 'live_activity_tokens',
         count(*) || ' rows, ' || count(distinct buyer_id) || ' people'
    from live_activity_tokens

  union all

  -- 4. What actually happened. 401 = the shared secret does not match
  --    LK_PUSH_SECRET in the function env. 400 = wrong payload shape. A 200
  --    whose body contains apnsStatus 400/403 means Apple rejected it — usually
  --    a development build's token sent to production APNs, or a bad topic.
  --    `pg_net` logs ALL outbound HTTP, so the permit-registry fetch from 033's
  --    cron job lands here too and reads as a push attempt. Labelled rather
  --    than filtered: seeing "not a push" is more useful than a silently short
  --    list, which would look like "nothing was attempted".
  select 4, '4. recent HTTP (pushes labelled)',
         to_char(created, 'MM-DD HH24:MI:SS') || '  HTTP ' || coalesce(status_code::text, '—')
           || case
                when content like '%apnsStatus%' then '  ← APNs'
                when content like '%"sent"%'     then '  ← alert fan-out'
                when content like '%programs%'   then '  (permit registry, not a push)'
                else ''
              end,
         left(coalesce(content, '(no body)'), 200)
    from (select * from net._http_response order by created desc limit 8) r
) x
order by ord, item;
