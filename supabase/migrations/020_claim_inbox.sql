-- 020 — the cook's claim inbox
--
-- A cook needs to see what was claimed and by whom-ish. "Whom-ish" is the
-- careful part: they get a repeat-count, not a buyer identity. Two-sided trust
-- means the cook knows this is a returning buyer without being handed a list of
-- everyone who has ever claimed from them.
--
-- Buyers are frequently anonymous identities (see SessionController), so there
-- is often no name to show even if we wanted to.

set search_path = public, extensions;

create type inbox_claim as (
  id            uuid,
  buyer_id      uuid,
  status        claim_status,
  note          text,
  created_at    timestamptz,
  item_summary  text,
  total_cents   integer,
  prior_claims  integer
);

create or replace function claim_inbox()
returns setof inbox_claim
language sql stable
set search_path = public, extensions as $$
  select
    c.id,
    c.buyer_id,
    c.status,
    c.note,
    c.created_at,
    (select string_agg(ci.quantity || '× ' || coalesce(mi.name_es, mi.name_en), ', '
                       order by mi.sort_order)
       from claim_items ci
       join menu_items mi on mi.id = ci.menu_item_id
      where ci.claim_id = c.id),
    (select sum(ci.quantity * mi.amount_cents)::int
       from claim_items ci
       join menu_items mi on mi.id = ci.menu_item_id
      where ci.claim_id = c.id),
    -- Prior claims from this buyer to THIS cook. Scoped deliberately: a cook
    -- has no business knowing a buyer's history with anyone else.
    (select count(*)::int from claims p
      where p.cook_id = c.cook_id
        and p.buyer_id = c.buyer_id
        and p.created_at < c.created_at)
  from claims c
  where c.cook_id = auth.uid()          -- own inbox only
  order by
    case c.status when 'pending' then 0 else 1 end,   -- unanswered first
    c.created_at desc;
$$;

grant execute on function claim_inbox() to authenticated;

-- Claims a cook still owes an answer on. Drives the badge and the
-- "2 waiting on you" line.
create or replace function pending_claim_count()
returns integer
language sql stable
set search_path = public, extensions as $$
  select count(*)::int from claims
   where cook_id = auth.uid() and status = 'pending';
$$;

grant execute on function pending_claim_count() to authenticated;
