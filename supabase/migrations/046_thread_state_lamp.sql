-- 046 — thread_state carries the lamp
--
-- 045 wired the Live Activity to conversations, but nothing in the app starts
-- a card: only `SpikeHarness` ever called `sync`. Doing that from the thread
-- needs one fact `thread_state` does not return — whether the cook is still
-- cooking, which drives the lamp dot on the Lock Screen.
--
-- The alternative was to pass `true` and let the first push correct it. That
-- push only fires when an address is shared or a pickup recorded, so a card
-- could sit on a Lock Screen asserting a kitchen was lit hours after the cook
-- closed. Asserting stale availability is the exact failure the decay ladder
-- exists to prevent (`DESIGN_BRIEF.md` §4); the card must not be the one
-- surface exempt from it.

set search_path = public, extensions;

drop function if exists thread_state(uuid);

create or replace function thread_state(p_thread uuid)
returns table (
  address_shared  boolean,
  picked_up       boolean,
  reviewed        boolean,
  i_am_the_cook   boolean,
  cook_is_cooking boolean,
  cook_name       text,
  ordered_at      timestamptz
)
language sql stable security definer
set search_path = public, extensions as $$
  select
    exists (select 1 from address_disclosures ad where ad.conversation_id = c.id),
    exists (select 1 from messages m where m.conversation_id = c.id and m.kind = 'pickup'),
    exists (select 1 from reviews r where r.conversation_id = c.id),
    c.cook_id = auth.uid(),
    -- `in ('lit','dimming')`, matching 036 and the doc comment on
    -- `ContentState.cookIsCooking`: the lamp goes out at *unconfirmed*, not at
    -- closed. `freshness_of` only reports 'out' for a closed session, so a
    -- `<> 'out'` test would keep a card claiming the kitchen is lit all night.
    coalesce((select s.id is not null
                     and freshness_of(s.last_confirmed_at, s.closed_at) in ('lit','dimming')
                from serving_sessions s
               where s.cook_id = c.cook_id and s.closed_at is null
               limit 1), false),
    co.display_name,
    -- When the card's clock starts: the most recent order, not the thread.
    (select m.created_at from messages m
      where m.conversation_id = c.id and m.kind = 'order'
      order by m.created_at desc limit 1)
  from conversations c
  join cooks co on co.id = c.cook_id
 where c.id = p_thread
   and (c.buyer_id = auth.uid() or c.cook_id = auth.uid());
$$;

revoke all on function thread_state(uuid) from public, anon;
grant execute on function thread_state(uuid) to authenticated;
