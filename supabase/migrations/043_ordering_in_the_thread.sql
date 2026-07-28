-- 043 — ordering happens in the conversation
--
-- Retires "claiming" as a user-facing concept. Nobody files a claim for
-- tamales; it was an invented intermediate noun sitting between "I want food"
-- and "come pick it up", and it made the buyer learn a word before they could
-- eat. The interaction is a conversation, so it is modelled as one.
--
-- ## What replaces it
--
--   browse (anonymous)  →  message the cook (account required, 040/041)
--   →  buyer picks dishes, which posts a tidy order into the thread
--   →  cook shares their address  →  cook marks it picked up  →  review
--
-- ## What must NOT change
--
-- The address gate. `reveal_address` (009/022) is the only door out of
-- `kitchen_locations`, and it works because a *cook* affirmatively confirmed a
-- specific person. Losing claims must not lose that, so `share_address` below
-- carries the identical properties: cook-initiated, per-buyer, rate-limited on
-- the same rolling daily cap, and audited into `address_disclosures` before
-- anything is released.
--
-- **The address is deliberately not written into the message.** The 'address'
-- message is a marker with no location in it; the buyer's client then calls
-- `thread_address()`, which reads `kitchen_locations` through a definer
-- function exactly as `reveal_address` does. Putting the street into
-- `messages.payload` would have been simpler and would have created a second
-- copy of every disclosed address in a table with ordinary RLS — turning one
-- carefully guarded door into two, the second of which nobody would remember
-- to guard.
--
-- ## Claims are not dropped here
--
-- Deliberately. `claims` has live rows and is referenced by `reviews`,
-- `address_disclosures`, `complaints` and `live_activity_tokens`; dropping it
-- in the same change that introduces the replacement would make a bad day
-- unrecoverable. This migration is additive. The tables stop being written to
-- once the app stops calling `create_claim`, and a later migration can drop
-- them once this has run in production for a while.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- A thread becomes a timeline of typed events, not just text.
-- ---------------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'message_kind') then
    create type message_kind as enum ('text', 'order', 'address', 'pickup');
  end if;
end $$;

alter table messages add column if not exists kind message_kind not null default 'text';
-- Order lines, so the cook sees "3× Tamal de puerco · $9" rather than parsing
-- prose while three pots are going. Structured on the way in, immutable after:
-- a price is what it was when the order was placed.
alter table messages add column if not exists payload jsonb;

-- ---------------------------------------------------------------------------
-- Disclosures can now come from a conversation rather than a claim.
-- ---------------------------------------------------------------------------
alter table address_disclosures alter column claim_id drop not null;
alter table address_disclosures
  add column if not exists conversation_id uuid references conversations(id) on delete set null;

-- Exactly one origin, always. Without this a row could carry neither and the
-- audit trail would have a hole in precisely the table that exists to not have
-- holes in it.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'address_disclosures_origin') then
    alter table address_disclosures add constraint address_disclosures_origin
      check (num_nonnulls(claim_id, conversation_id) = 1);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- The buyer places an order.
--
-- Same gate and same block checks as `send_message` — this *is* a message, and
-- routing round the gate by ordering instead of typing would defeat 040.
-- ---------------------------------------------------------------------------
create or replace function post_order(p_cook uuid, p_items jsonb, p_note text default null)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me      uuid := auth.uid();
  v_gate    text;
  v_thread  uuid;
  v_lines   jsonb;
  v_total   int;
  v_summary text;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  v_gate := sender_can_message();
  if v_gate = 'anonymous' then
    raise exception 'sign in to order' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to order' using errcode = 'P0003';
  end if;

  if v_me = p_cook then raise exception 'a cook cannot order from themselves'; end if;
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  -- Prices and names are resolved server-side from `menu_items`. A client that
  -- could supply them could order a $40 dozen for $1, and the cook would only
  -- notice at the door.
  select jsonb_agg(jsonb_build_object(
           'menu_item_id', mi.id,
           'name',         coalesce(mi.name_es, mi.name_en),
           'quantity',     (i ->> 'quantity')::int,
           'unit_cents',   mi.amount_cents
         ) order by mi.sort_order),
         sum(mi.amount_cents * (i ->> 'quantity')::int)::int,
         string_agg((i ->> 'quantity') || '× ' || coalesce(mi.name_es, mi.name_en),
                    ', ' order by mi.sort_order)
    into v_lines, v_total, v_summary
    from jsonb_array_elements(p_items) i
    join menu_items mi on mi.id = (i ->> 'menu_item_id')::uuid
   where mi.cook_id = p_cook            -- items must belong to THIS cook
     and mi.is_available                -- and still be on offer
     and (i ->> 'quantity')::int between 1 and 99;

  if v_lines is null then
    raise exception 'nothing orderable in that request' using errcode = 'P0001';
  end if;

  -- Blocked buyers: accept and discard, same as `send_message` (042). An error
  -- here would tell them they had been blocked.
  if exists (select 1 from blocked_buyers b
              where b.cook_id = p_cook and b.buyer_id = v_me) then
    return gen_random_uuid();
  end if;

  insert into conversations (cook_id, buyer_id)
  values (p_cook, v_me)
  on conflict (cook_id, buyer_id) do update set last_message_at = now()
  returning id into v_thread;

  insert into messages (conversation_id, sender_id, body, kind, payload)
  values (v_thread, v_me,
          v_summary || ' · $' || to_char(v_total / 100.0, 'FM999990.00'),
          'order',
          jsonb_build_object('lines', v_lines, 'total_cents', v_total,
                             'note', nullif(trim(coalesce(p_note, '')), '')))
  returning id into v_message;

  return v_message;
end $$;

revoke all on function post_order(uuid, jsonb, text) from public, anon;
grant execute on function post_order(uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The cook shares their address.
--
-- This is `reveal_address` with the trigger moved from the buyer to the cook,
-- which is strictly safer: previously the buyer pulled the address once a claim
-- was confirmed, so confirmation and disclosure were one decision made in
-- advance. Here the cook decides, per person, at the moment they mean it.
-- ---------------------------------------------------------------------------
create or replace function share_address(p_thread uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid; v_kitchen uuid; v_recent int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select c.buyer_id into v_buyer
    from conversations c
   where c.id = p_thread and c.cook_id = auth.uid();
  if v_buyer is null then raise exception 'not authorized'; end if;

  select k.id into v_kitchen from kitchens k where k.cook_id = auth.uid();
  if v_kitchen is null then raise exception 'no kitchen'; end if;

  -- Same rolling daily cap as reveal_address, counted per buyer. A cook cannot
  -- raise it for someone by sharing repeatedly, because it counts distinct
  -- kitchens disclosed *to that buyer*, not disclosures made by this cook.
  select count(distinct kitchen_id) into v_recent
    from address_disclosures
   where buyer_id = v_buyer
     and disclosed_at > now() - interval '24 hours'
     and kitchen_id <> v_kitchen;
  if v_recent >= 5 then
    raise exception 'that person has unlocked too many addresses today'
      using errcode = 'P0001';
  end if;

  -- Log first, then release — if the audit insert fails, nothing is disclosed.
  insert into address_disclosures (conversation_id, kitchen_id, buyer_id)
  values (p_thread, v_kitchen, v_buyer);

  -- A marker, carrying no address. See the header.
  insert into messages (conversation_id, sender_id, body, kind)
  values (p_thread, auth.uid(), 'Shared their address', 'address');

  update conversations set last_message_at = now() where id = p_thread;
end $$;

revoke all on function share_address(uuid) from public, anon;
grant execute on function share_address(uuid) to authenticated;

-- The buyer's door to it. Mirrors `reveal_address`: reads `kitchen_locations`
-- as definer, and only when a disclosure for this pair already exists.
create or replace function thread_address(p_thread uuid)
returns table (street text, city text, postal_code text,
               latitude double precision, longitude double precision)
language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_kitchen uuid;
begin
  select ad.kitchen_id into v_kitchen
    from address_disclosures ad
    join conversations c on c.id = ad.conversation_id
   where ad.conversation_id = p_thread
     and (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
   order by ad.disclosed_at desc
   limit 1;

  if v_kitchen is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
    select kl.street, kl.city, kl.postal_code,
           ST_Y(kl.exact_point::geometry), ST_X(kl.exact_point::geometry)
      from kitchen_locations kl where kl.kitchen_id = v_kitchen;
end $$;

revoke all on function thread_address(uuid) from public, anon;
grant execute on function thread_address(uuid) to authenticated;

comment on function thread_address is
  'The second door to a home address, and the only other one. Requires an '
  'existing address_disclosures row for this conversation.';

-- ---------------------------------------------------------------------------
-- The cook marks it picked up. This is what unlocks a review.
-- ---------------------------------------------------------------------------
create or replace function mark_picked_up(p_thread uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from conversations c
                  where c.id = p_thread and c.cook_id = auth.uid()) then
    raise exception 'not authorized';
  end if;

  -- Idempotent: a cook tapping twice should not stack up pickup events, and
  -- the review gate below only asks whether one exists.
  if exists (select 1 from messages m
              where m.conversation_id = p_thread and m.kind = 'pickup'
                and m.created_at > now() - interval '12 hours') then
    return;
  end if;

  insert into messages (conversation_id, sender_id, body, kind)
  values (p_thread, auth.uid(), 'Marked as picked up', 'pickup');

  update conversations set last_message_at = now() where id = p_thread;
end $$;

revoke all on function mark_picked_up(uuid) from public, anon;
grant execute on function mark_picked_up(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reviews, now attested by a pickup rather than a completed claim.
-- ---------------------------------------------------------------------------
alter table reviews alter column claim_id drop not null;
alter table reviews
  add column if not exists conversation_id uuid references conversations(id) on delete set null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'reviews_origin') then
    alter table reviews add constraint reviews_origin
      check (num_nonnulls(claim_id, conversation_id) = 1);
  end if;
end $$;

-- One review per thread, matching the one-per-claim rule it replaces.
create unique index if not exists reviews_one_per_conversation
  on reviews (conversation_id) where conversation_id is not null;

drop policy if exists reviews_by_conversation on reviews;
create policy reviews_by_conversation on reviews for insert
  with check (
    conversation_id is not null
    and exists (
      select 1 from conversations c
       where c.id = reviews.conversation_id
         and c.buyer_id = auth.uid()
         -- The cook said the food changed hands. Without this a review is
         -- something anyone can leave after sending one message.
         and exists (select 1 from messages m
                      where m.conversation_id = c.id and m.kind = 'pickup')
         -- Pinned server-side, as 027 does: the client supplies cook_id and
         -- must not be able to aim a review at a different kitchen.
         and c.cook_id = reviews.cook_id
    )
  );

-- ---------------------------------------------------------------------------
-- The thread, as the app reads it. One call: messages plus the state the
-- header needs, so the view does not assemble it from four round trips.
-- ---------------------------------------------------------------------------
create or replace function thread_state(p_thread uuid)
returns table (
  address_shared boolean,
  picked_up      boolean,
  reviewed       boolean,
  i_am_the_cook  boolean
)
language sql stable security definer
set search_path = public, extensions as $$
  select
    exists (select 1 from address_disclosures ad where ad.conversation_id = c.id),
    exists (select 1 from messages m where m.conversation_id = c.id and m.kind = 'pickup'),
    exists (select 1 from reviews r where r.conversation_id = c.id),
    c.cook_id = auth.uid()
  from conversations c
 where c.id = p_thread
   and (c.buyer_id = auth.uid() or c.cook_id = auth.uid());
$$;

revoke all on function thread_state(uuid) from public, anon;
grant execute on function thread_state(uuid) to authenticated;
