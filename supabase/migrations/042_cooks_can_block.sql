-- 042 — a cook can block and report a buyer
--
-- 028 gave buyers `blocked_cooks` and `report_cook`. Nothing was ever built
-- going the other way, and until this week that was defensible: a buyer was an
-- anonymous identity who could file a claim and nothing else, and a cook could
-- simply decline it.
--
-- 039–041 changed that. A stranger can now write directly to a cook, at the
-- home they cook in, and the cook has no recourse of any kind — no block, no
-- report, no way to make it stop. Every protection in this schema runs one
-- direction. That asymmetry is the thing this migration exists to remove, and
-- it should have landed alongside messaging rather than after it.
--
-- ## A block here is total, not just a mute
--
-- Blocking only the messages would leave the person still able to see the
-- kitchen lit, still able to claim, still able to turn up. So a blocked buyer
-- loses the kitchen entirely — it disappears from their feed, map, search and
-- saved rows, exactly as a buyer-blocked kitchen disappears. Same mechanism,
-- pointed the other way.
--
-- ## And it is silent
--
-- 028's reasoning ("a cook who could tell they had been blocked could work out
-- by whom, in a market where the buyer lives a few streets away") applies with
-- more force in this direction, not less: there is only one cook in a thread,
-- so a buyer told they were blocked knows exactly who did it — and if they
-- have ever completed a claim, they have been given that cook's home address.
-- Telling them would hand a retaliation target to the one person the block
-- exists to protect against.
--
-- So: no error, no notice, no visible change. The kitchen is simply not there
-- any more, which is indistinguishable from a cook who stopped cooking.

set search_path = public, extensions;

create table if not exists blocked_buyers (
  cook_id    uuid not null references cooks(id) on delete cascade,
  buyer_id   uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (cook_id, buyer_id)
);

alter table blocked_buyers enable row level security;

-- Only the cook's own rows, and — as with `blocked_cooks` — there is
-- deliberately no policy letting a buyer read rows about themselves.
drop policy if exists blocked_buyers_own on blocked_buyers;
create policy blocked_buyers_own on blocked_buyers for all
  using (cook_id = auth.uid())
  with check (cook_id = auth.uid());

-- No client grants at all. Every path a cook needs — block, unblock, list —
-- goes through a SECURITY DEFINER function below, so the table needs no direct
-- access, and `kitchen_locations` is the precedent: protected by the absence of
-- a grant rather than by a policy that has to be got right.
--
-- The RLS policy above is therefore belt-and-braces. It is not redundant: a
-- future `grant ... to authenticated` added without reading this comment would
-- otherwise expose every cook's block list to every buyer.
revoke all on blocked_buyers from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The two directions of the question, each as a SECURITY DEFINER helper.
--
-- Same hazard 028 documented: `cooking_now` is a plain function, so an inline
-- subquery over `blocked_buyers` would be read as the *caller* — and `anon`
-- has no grant on it. That would fail the entire anonymous feed with
-- "permission denied", which is how blocking broke discovery the first time.
-- ---------------------------------------------------------------------------

-- Asked by a buyer, about a kitchen: "has this cook blocked me?"
create or replace function i_am_blocked_by(p_cook uuid)
returns boolean language sql stable security definer
set search_path = public, extensions as $$
  select exists (
    select 1 from blocked_buyers
     where cook_id = p_cook and buyer_id = auth.uid()
  );
$$;

grant execute on function i_am_blocked_by(uuid) to anon, authenticated;

-- Asked by a cook, about a buyer: "have I blocked them?"
create or replace function buyer_is_blocked(p_buyer uuid)
returns boolean language sql stable security definer
set search_path = public, extensions as $$
  select exists (
    select 1 from blocked_buyers
     where cook_id = auth.uid() and buyer_id = p_buyer
  );
$$;

revoke all on function buyer_is_blocked(uuid) from public, anon;
grant execute on function buyer_is_blocked(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Blocking and unblocking.
--
-- Takes the conversation rather than a raw buyer id: a cook only ever
-- encounters a buyer through a thread or a claim, and accepting a bare uuid
-- would let anyone block anyone, which is harmless in effect but is a write
-- primitive with no reason to exist.
-- ---------------------------------------------------------------------------
create or replace function block_buyer_in(p_thread uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select c.buyer_id into v_buyer
    from conversations c
   where c.id = p_thread and c.cook_id = auth.uid();
  if v_buyer is null then raise exception 'not authorized'; end if;

  insert into blocked_buyers (cook_id, buyer_id)
  values (auth.uid(), v_buyer)
  on conflict do nothing;
end $$;

revoke all on function block_buyer_in(uuid) from public, anon;
grant execute on function block_buyer_in(uuid) to authenticated;

create or replace function unblock_buyer(p_buyer uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from blocked_buyers where cook_id = auth.uid() and buyer_id = p_buyer;
end $$;

revoke all on function unblock_buyer(uuid) from public, anon;
grant execute on function unblock_buyer(uuid) to authenticated;

-- Who the cook has blocked, so the block can be undone. Without this the
-- action is one-way and the "you can unblock any time" promise the buyer-side
-- UI makes would not be true here.
create or replace function my_blocked_buyers()
returns table (buyer_id uuid, display_name text, avatar_path text, blocked_at timestamptz)
language sql stable security definer
set search_path = public, extensions as $$
  select b.buyer_id,
         coalesce(p.display_name, 'Someone nearby'),
         p.avatar_path,
         b.created_at
    from blocked_buyers b
    left join profiles p on p.id = b.buyer_id
   where b.cook_id = auth.uid()
   order by b.created_at desc;
$$;

revoke all on function my_blocked_buyers() from public, anon;
grant execute on function my_blocked_buyers() to authenticated;

-- ---------------------------------------------------------------------------
-- Reporting a buyer.
--
-- A separate table from `complaints`, not a `kind` added to it. `complaints` is
-- about food safety and routes to the enforcement agency (028); this routes to
-- us and nowhere else. A cook reporting harassment is not filing a health
-- complaint, and handing either one to the wrong destination would be worse
-- than not collecting it.
-- ---------------------------------------------------------------------------
create table if not exists buyer_reports (
  id              uuid primary key default gen_random_uuid(),
  cook_id         uuid not null references cooks(id) on delete cascade,
  buyer_id        uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid references conversations(id) on delete set null,
  kind            text not null check (kind in ('harassment','no_show','spam','other')),
  body            text,
  created_at      timestamptz not null default now()
);

alter table buyer_reports enable row level security;

-- Write-only from the client's perspective: a cook files one and cannot read
-- the table back. Nothing here is theirs to browse, and a readable reports
-- table is a way to learn who else has reported whom.
drop policy if exists buyer_reports_insert_own on buyer_reports;
create policy buyer_reports_insert_own on buyer_reports for insert
  with check (cook_id = auth.uid());

grant insert on buyer_reports to authenticated;

create or replace function report_buyer(
  p_thread uuid,
  p_kind   text,
  p_body   text default null,
  p_block  boolean default true
)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_kind not in ('harassment','no_show','spam','other') then
    raise exception 'unknown report kind %', p_kind;
  end if;

  select c.buyer_id into v_buyer
    from conversations c
   where c.id = p_thread and c.cook_id = auth.uid();
  if v_buyer is null then raise exception 'not authorized'; end if;

  insert into buyer_reports (cook_id, buyer_id, conversation_id, kind, body)
  values (auth.uid(), v_buyer, p_thread, p_kind,
          nullif(trim(coalesce(p_body, '')), ''));

  -- Reporting someone you must keep hearing from is not a resolution, so the
  -- block is the default rather than a second thing to remember. Still
  -- optional: "this happened, but I'll keep serving them" is a real answer.
  if p_block then
    insert into blocked_buyers (cook_id, buyer_id)
    values (auth.uid(), v_buyer)
    on conflict do nothing;
  end if;
end $$;

revoke all on function report_buyer(uuid, text, text, boolean) from public, anon;
grant execute on function report_buyer(uuid, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- The block takes effect everywhere.
-- ---------------------------------------------------------------------------

-- 1. The cook stops seeing the thread; the buyer keeps their own copy, so
--    nothing about their view changes and nothing leaks.
create or replace function my_conversations()
returns table (
  id            uuid,
  cook_id       uuid,
  buyer_id      uuid,
  other_name    text,
  other_avatar  text,
  last_body     text,
  last_at       timestamptz,
  unread        integer,
  i_am_the_cook boolean
)
language sql stable security definer
set search_path = public, extensions as $$
  select c.id, c.cook_id, c.buyer_id,
         case when c.cook_id = auth.uid()
              then coalesce(bp.display_name, 'Someone nearby')
              else co.display_name end,
         case when c.cook_id = auth.uid() then bp.avatar_path else co.avatar_url end,
         (select m.body from messages m
           where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*)::int from messages m
           where m.conversation_id = c.id
             and m.sender_id <> auth.uid() and m.read_at is null),
         c.cook_id = auth.uid()
    from conversations c
    join cooks co        on co.id = c.cook_id
    left join profiles bp on bp.id = c.buyer_id
   where (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
     -- Only hides it from the cook's side. The buyer's inbox is untouched, so
     -- the thread does not vanish from under them and reveal the block.
     and not (c.cook_id = auth.uid()
              and exists (select 1 from blocked_buyers b
                           where b.cook_id = c.cook_id and b.buyer_id = c.buyer_id))
   order by c.last_message_at desc;
$$;

grant execute on function my_conversations() to authenticated;

-- 2. New messages from a blocked buyer are dropped rather than refused.
--    Silently, per the note at the top: an error is a notification.
create or replace function send_message(
  p_cook  uuid,
  p_body  text,
  p_claim uuid default null
)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me      uuid := auth.uid();
  v_gate    text;
  v_thread  uuid;
  v_recent  integer;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  v_gate := sender_can_message();
  if v_gate = 'anonymous'  then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to send a message' using errcode = 'P0003';
  end if;

  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;
  if v_me = p_cook then
    raise exception 'a cook cannot open a conversation with themselves';
  end if;
  if not exists (select 1 from cooks where id = p_cook) then
    raise exception 'no such cook';
  end if;
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  select count(*) into v_recent
    from messages m
   where m.sender_id = v_me and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  -- Blocked by this cook: accept, discard, return a plausible id. The rate
  -- limit above is checked first on purpose, so this path cannot be used as an
  -- oracle to probe for a block by watching which sends stay cheap.
  if exists (select 1 from blocked_buyers b
              where b.cook_id = p_cook and b.buyer_id = v_me) then
    return gen_random_uuid();
  end if;

  insert into conversations (cook_id, buyer_id, opening_claim)
  values (p_cook, v_me, p_claim)
  on conflict (cook_id, buyer_id) do update set last_message_at = now()
  returning id into v_thread;

  insert into messages (conversation_id, sender_id, body)
  values (v_thread, v_me, trim(p_body))
  returning id into v_message;

  return v_message;
end $$;

revoke all on function send_message(uuid, text, uuid) from public, anon;
grant execute on function send_message(uuid, text, uuid) to authenticated;

create or replace function reply_in_conversation(p_thread uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_gate text; v_ok boolean; v_cook uuid;
        v_message uuid; v_recent integer;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  v_gate := sender_can_message();
  if v_gate = 'anonymous' then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to send a message' using errcode = 'P0003';
  end if;

  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;

  select (c.buyer_id = v_me or c.cook_id = v_me), c.cook_id into v_ok, v_cook
    from conversations c where c.id = p_thread;
  if not coalesce(v_ok, false) then raise exception 'not authorized'; end if;

  select count(*) into v_recent
    from messages m where m.sender_id = v_me and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  -- Same silent drop, for the buyer replying in a thread they already had.
  if v_me <> v_cook and exists (select 1 from blocked_buyers b
                                 where b.cook_id = v_cook and b.buyer_id = v_me) then
    return gen_random_uuid();
  end if;

  insert into messages (conversation_id, sender_id, body)
  values (p_thread, v_me, trim(p_body))
  returning id into v_message;

  update conversations set last_message_at = now() where id = p_thread;
  return v_message;
end $$;

revoke all on function reply_in_conversation(uuid, text) from public, anon;
grant execute on function reply_in_conversation(uuid, text) to authenticated;

-- 3. The kitchen disappears from discovery for that buyer, which is what makes
--    this a block rather than a mute. Same shape as `not cook_is_blocked`
--    directly above it — the two predicates are the two directions.
create or replace function cooking_now(
  lat            double precision,
  lon            double precision,
  radius_m       integer default 8000,
  include_closed boolean default false
)
returns setof discovery_row
language sql stable
set search_path = public, extensions as $$
  with origin as (
    select ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography as p
  ),
  menu as (
    select mi.cook_id,
           count(*)::int as item_count,
           array_agg(coalesce(mi.name_es, mi.name_en)
                     order by mi.sort_order, mi.created_at, mi.id) as items,
           -- No FILTER: the headline photo is the headline dish's own (025).
           (array_agg(mi.photo_url
                      order by mi.sort_order, mi.created_at, mi.id))[1] as photo,
           min(mi.amount_cents) as min_cents,
           (array_agg(mi.unit order by mi.amount_cents))[1] as min_unit,
           (array_agg(mi.min_quantity order by mi.amount_cents))[1] as min_qty
      from menu_items mi
     where mi.is_available
     group by mi.cook_id
  )
  select
    c.id, c.display_name, c.avatar_url, c.permit_status, c.permit_number,
    a.name, k.neighborhood,
    ST_Distance(k.public_point, o.p),
    ST_Y(k.public_point::geometry),
    ST_X(k.public_point::geometry),
    s.id, s.opened_at, s.last_confirmed_at,
    case when s.id is null then null
         else freshness_of(s.last_confirmed_at, s.closed_at) end,
    coalesce(m.item_count, 0), m.items, m.photo,
    m.min_cents, m.min_unit, m.min_qty
  from cooks c
  join kitchens k on k.cook_id = c.id
  join enforcement_agencies a on a.id = k.agency_id
  left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
  left join menu m on m.cook_id = c.id
  cross join origin o
  where ST_DWithin(k.public_point, o.p, radius_m)
    and (include_closed or s.id is not null)
    and not cook_is_blocked(c.id)
    and not i_am_blocked_by(c.id)
  order by
    case when s.id is null then 3
         else freshness_rank(freshness_of(s.last_confirmed_at, s.closed_at)) end,
    ST_Distance(k.public_point, o.p);
$$;

grant execute on function cooking_now(double precision, double precision, integer, boolean) to anon, authenticated;

-- 4. And they cannot claim.
--
-- Discovery hiding the kitchen is what a normal person experiences, but it is
-- not a control — `create_claim` is reachable directly, and a blocked buyer
-- turning up at the door is the precise scenario this migration exists for.
--
-- A trigger rather than a rewrite of `create_claim`: the invariant is "a
-- blocked buyer has no claims", not "one function remembers to check", and
-- `create_claim` is long enough that copying it to add two lines is how the
-- copy drifts from the original.
--
-- **This one raises rather than dropping silently**, breaking the rule used for
-- messages, and the difference is deliberate. An unanswered message costs the
-- sender nothing. A claim that appears to succeed and reaches nobody sends
-- someone driving across town for food that was never coming. The wording is
-- the same thing a closed or full kitchen says, so it still discloses nothing.
create or replace function claims_reject_blocked() returns trigger
language plpgsql security definer
set search_path = public, extensions as $$
begin
  if exists (select 1 from blocked_buyers b
              where b.cook_id = new.cook_id and b.buyer_id = new.buyer_id) then
    raise exception 'this kitchen isn''t taking claims right now';
  end if;
  return new;
end $$;

revoke all on function claims_reject_blocked() from public, anon, authenticated;

drop trigger if exists claims_block_check on claims;
create trigger claims_block_check before insert on claims
  for each row execute function claims_reject_blocked();

comment on table blocked_buyers is
  'A cook''s own blocks. Silent to the buyer by design — see the header of '
  'migration 042.';
