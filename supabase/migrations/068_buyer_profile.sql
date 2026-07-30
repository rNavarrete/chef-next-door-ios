-- 068 — what a cook may know about a buyer
--
-- A cook deciding whether to answer at nine at night wants to know one thing:
-- have I cooked for this person before, and did they turn up. Today that
-- answer is buried in a thread they have to scroll.
--
-- ## Why an RPC and not a view
--
-- Two of these numbers cross a line RLS draws deliberately. `profiles_self`
-- (041) lets a cook read a buyer's profile *only* where a conversation exists
-- between them, and `messages_parties_read` (049) confines messages to threads
-- the reader is party to. That is correct and stays correct: a cook has no
-- business enumerating who else a buyer orders from.
--
-- But "has ordered 12 times on the platform" is a useful signal and is not the
-- same disclosure as "here is who from". So this function computes across every
-- conversation and returns **counts only** — never a cook name, never a thread,
-- never a date that could be matched against someone else's kitchen. It is
-- SECURITY DEFINER so it can see past RLS, and it checks the caller's standing
-- itself, in the first statement, before reading anything.
--
-- ## Reviews are counted, not listed
--
-- Reviews render anonymously on a kitchen page — stars and text, no name. That
-- is what makes an honest two-star review possible: the next cook cannot look
-- up who wrote it. Listing a buyer's reviews here would quietly undo that, and
-- a marketplace where buyers know they are being scored on their reviews gets
-- politer reviews and less true ones.
--
-- So: a count of how many they have written, and the full text of the one they
-- wrote *for the caller*, which the caller can already read on their own
-- kitchen page. Nothing new is revealed about anyone else.
--
-- ## A pickup is the transaction; an order is only one way to start one
--
-- Claims were retired in 043, so both counts come from `messages` rather than
-- the vestigial `claims` table, which is empty for anything recent and would
-- silently report zero.
--
-- Which kind to count is the part that matters. The structured order flow is
-- optional: a buyer can message a cook, agree on the food in prose, get the
-- address and collect it, and never produce a message of kind 'order'. The
-- first real buyer checked against this function had exactly that history —
-- one pickup, a five-star review, and no order row anywhere. Counting orders
-- would have introduced him to his own cook as somebody who had never bought
-- anything.
--
-- So `pickup` is the headline number on both scopes: it is the only message
-- that means food actually changed hands. Orders are returned alongside it,
-- because "ordered four times, collected twice" is worth knowing — but they
-- are the smaller truth and must not be the one on the badge.

set search_path = public, extensions;

-- `create or replace` refuses to change a function's OUT parameters, so adding
-- a column to the returned row needs the drop. Kept here rather than left to
-- whoever hits it next: this file was already re-applied once during its own
-- development and failed on exactly that.
drop function if exists buyer_profile(uuid);

create or replace function buyer_profile(p_buyer uuid)
returns table (
  display_name        text,
  avatar_path         text,
  member_since        timestamptz,
  orders_with_me      integer,
  pickups_with_me     integer,
  first_order_with_me timestamptz,
  last_order_with_me  timestamptz,
  orders_total        integer,
  pickups_total       integer,
  reviews_written     integer,
  review_for_me       text,
  review_for_me_stars smallint
)
language plpgsql stable security definer
set search_path = public, extensions as $$
declare
  v_me     uuid := auth.uid();
  v_thread uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- Standing, checked before a single row is read. A cook may ask about a
  -- buyer they have a conversation with, and nobody may ask about anyone else.
  -- Without this, SECURITY DEFINER would hand every caller a lookup table of
  -- every buyer on the platform.
  select c.id into v_thread
    from conversations c
   where c.cook_id = v_me and c.buyer_id = p_buyer
   order by c.last_message_at desc
   limit 1;

  if v_thread is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  select
    p.display_name,
    p.avatar_path,
    p.created_at,

    -- With me. Scoped to this cook's own threads, which the caller could have
    -- counted by hand.
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'pickup'),
    (select min(m.created_at) from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),
    (select max(m.created_at) from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),

    -- Platform-wide, and bare numbers on purpose. "Buys a lot, turns up" is a
    -- fair thing for a cook to know; "buys from these four kitchens" is not.
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.buyer_id = p_buyer and m.kind = 'order'),
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.buyer_id = p_buyer and m.kind = 'pickup'),

    -- Likewise. How engaged they are, not what they said about anyone else.
    (select count(*)::int from reviews r
       join conversations c on c.id = r.conversation_id
      where c.buyer_id = p_buyer),

    -- The exception, and only because the caller can already read this on
    -- their own kitchen page. Shown here so they do not have to go looking.
    (select r.body from reviews r
      where r.conversation_id = v_thread limit 1),
    (select r.rating from reviews r
      where r.conversation_id = v_thread limit 1)
  from profiles p
  where p.id = p_buyer;
end $$;

revoke all on function buyer_profile(uuid) from public, anon;
grant execute on function buyer_profile(uuid) to authenticated;

comment on function buyer_profile(uuid) is
  'What a cook may know about one of their buyers. Cross-cook figures are '
  'returned as counts only — never a cook, a thread or a date that could be '
  'matched to another kitchen. Caller standing is checked in the body.';
