-- 034 — somewhere to put the push token
--
-- `Activity.request(pushType: .token)` now succeeds on device and ActivityKit
-- hands back a per-activity push token. `CookingActivityManager.observeTokens`
-- has had it in hand since M0 and only ever logged it, with a `// M1:` note
-- where the write should be. This is that write.
--
-- ## Per activity, not per device
--
-- This is not the APNs device token. It identifies **one Live Activity on one
-- phone**, it is reissued during the activity's life, and it is useless once
-- the activity ends. So the row is keyed by claim, replaced whenever the token
-- rotates, and deleted with the claim.
--
-- ## Nobody can read it back
--
-- A buyer may write their own token; the cook must never see it, and neither
-- may the buyer once written. A push token is a capability — anything holding
-- it can put content on that Lock Screen — so the only reader is the sender,
-- running as the definer. There is no SELECT policy for anyone.

set search_path = public, extensions;

create table if not exists live_activity_tokens (
  claim_id     uuid not null references claims(id) on delete cascade,
  buyer_id     uuid not null references auth.users(id) on delete cascade,
  token        text not null,
  activity_id  text,
  -- Which APNs host to use. A development-signed build gets tokens that only
  -- the sandbox will accept; sending those to production APNs fails with
  -- BadDeviceToken, which is a confusing way to discover a build-config
  -- mismatch.
  environment  text not null default 'development'
    check (environment in ('development', 'production')),
  updated_at   timestamptz not null default now(),
  primary key (claim_id)
);

alter table live_activity_tokens enable row level security;

-- Write your own, for your own claim. Nothing else.
drop policy if exists lat_own_insert on live_activity_tokens;
create policy lat_own_insert on live_activity_tokens for insert
  with check (
    buyer_id = auth.uid()
    and exists (select 1 from claims c where c.id = claim_id and c.buyer_id = auth.uid())
  );

drop policy if exists lat_own_update on live_activity_tokens;
create policy lat_own_update on live_activity_tokens for update
  using (buyer_id = auth.uid())
  with check (buyer_id = auth.uid());

drop policy if exists lat_own_delete on live_activity_tokens;
create policy lat_own_delete on live_activity_tokens for delete
  using (buyer_id = auth.uid());

-- Deliberately no SELECT policy and no SELECT grant: see the header. The
-- sender reads it as the definer.
grant insert, update, delete on live_activity_tokens to authenticated;

comment on table live_activity_tokens is
  'Per-activity ActivityKit push tokens. Write-only from the client — a token '
  'is a capability to write to someone''s Lock Screen, so nothing reads it '
  'back except the sender.';

-- ---------------------------------------------------------------------------
-- Registration, as an RPC rather than a bare upsert.
--
-- The client does not get to say whose token it is or which claim it belongs
-- to unchallenged: buyer_id comes from auth.uid() here, and the claim is
-- checked. Doing it as a PostgREST upsert would have meant trusting a body
-- that a client composes.
-- ---------------------------------------------------------------------------
create or replace function register_activity_token(
  p_claim       uuid,
  p_token       text,
  p_activity_id text default null,
  p_environment text default 'development'
)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid := auth.uid();
begin
  if v_buyer is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  if p_environment not in ('development', 'production') then
    raise exception 'unknown APNs environment %', p_environment;
  end if;

  if not exists (select 1 from claims c where c.id = p_claim and c.buyer_id = v_buyer) then
    raise exception 'not authorized';
  end if;

  insert into live_activity_tokens (claim_id, buyer_id, token, activity_id, environment)
  values (p_claim, v_buyer, trim(p_token), p_activity_id, p_environment)
  on conflict (claim_id) do update
    set token       = excluded.token,
        activity_id = excluded.activity_id,
        environment = excluded.environment,
        buyer_id    = excluded.buyer_id,
        updated_at  = now();
end $$;

revoke all on function register_activity_token(uuid, text, text, text) from public, anon;
grant execute on function register_activity_token(uuid, text, text, text) to authenticated;

-- A finished claim can never need another push, and the token is dead anyway.
create or replace function drop_dead_activity_tokens() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status in ('completed', 'cancelled', 'no_show') then
    delete from live_activity_tokens where claim_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists claims_drop_activity_token on claims;
create trigger claims_drop_activity_token
  after update of status on claims
  for each row execute function drop_dead_activity_tokens();
