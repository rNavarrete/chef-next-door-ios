-- 059 — a phone belongs to one account at a time
--
-- `device_tokens` is keyed `(user_id, token)`, so the same handset can be
-- registered to any number of accounts at once. Nothing ever removes the old
-- rows, and the result is exactly the failure 047 wrote a comment promising to
-- prevent:
--
--   > Signing out should stop that handset ringing for an account that is no
--   > longer on it.
--
-- Observed on the test device: one APNs token registered to **three** different
-- users simultaneously. Signing in as a cook produced a push alert intended for
-- a completely different account, on a handset that account had signed out of.
-- A buyer's order notifications — sender name, dish, and the fact that they are
-- messaging a particular cook at all — were being delivered to whoever picked
-- up the phone next.
--
-- ## Why the client fix alone is not enough
--
-- `PushRegistrar.forgetToken()` deletes the row on sign-out, but only if it
-- still holds the token in memory: APNs hands the token to the app delegate
-- once per launch, so after a relaunch the property is nil and sign-out cleans
-- up nothing. That is being fixed too — but it only protects sign-outs from
-- here on, and it cannot repair a row that was already orphaned.
--
-- The invariant belongs on the server, where it can be stated once and enforced
-- for every client: **a token identifies a handset, and a handset has one
-- signed-in account.** Registering a token is therefore a claim on it.

set search_path = public, extensions;

create or replace function register_device_token(p_token text, p_environment text default 'development')
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  if p_environment not in ('development', 'production') then
    raise exception 'unknown APNs environment %', p_environment;
  end if;

  -- The claim. Whoever registers this token now owns it, and any previous
  -- account on this handset stops being notified on it.
  --
  -- Safe because the token is APNs' identifier for *this app on this device*:
  -- two accounts holding the same one always means a stale row, never two live
  -- devices. Deleting is also the only self-healing option — an orphaned row
  -- has no owner left to come back and clean it up.
  delete from device_tokens
   where token = trim(p_token)
     and user_id is distinct from v_me;

  insert into device_tokens (user_id, token, environment)
  values (v_me, trim(p_token), p_environment)
  on conflict (user_id, token) do update
    set environment = excluded.environment, updated_at = now();
end $$;

revoke all on function register_device_token(text, text) from public, anon;
grant execute on function register_device_token(text, text) to authenticated;

comment on function register_device_token is
  'Claims an APNs token for the caller and releases it from every other '
  'account. A handset has one signed-in user; the table used to allow many.';

-- ---------------------------------------------------------------------------
-- Repair what is already there.
--
-- Keeps the most recently updated row per token — the account currently on the
-- handset — and drops the rest. These are live misroutes, not history: every
-- one of them is a phone being told about somebody else's orders right now.
-- ---------------------------------------------------------------------------
with ranked as (
  select ctid,
         row_number() over (partition by token order by updated_at desc) as rn
    from device_tokens
)
delete from device_tokens dt
 using ranked r
 where dt.ctid = r.ctid and r.rn > 1;

-- Enforced from here on, so this cannot silently come back.
do $$ begin
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and indexname = 'device_tokens_token_unique'
  ) then
    create unique index device_tokens_token_unique on device_tokens (token);
  end if;
end $$;
