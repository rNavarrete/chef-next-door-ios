-- 021 — atomic claim creation
--
-- TWO BUGS, found on the first real claim from the app:
--
-- 1. `claim_items` had a SELECT policy (010) and an INSERT *grant* (011), but
--    no INSERT *policy*. Grants make a table addressable; policies decide
--    which rows may be written. With RLS on and no INSERT policy, every write
--    is refused:
--      new row violates row-level security policy for table "claim_items"
--
-- 2. The client inserted the claim and its items as two separate statements,
--    so bug 1 left an orphaned claim with no items — a buyer telling a cook
--    they're coming for nothing. Two writes that must both land are one
--    operation, and this is exactly the case for a function rather than
--    client-side sequencing.
--
-- This also lets the server validate what the client should never be trusted
-- with: that the items actually belong to the cook being claimed from, and
-- that the session is genuinely open.

set search_path = public, extensions;

-- Fixes bug 1 on its own terms, so a direct insert isn't silently broken for
-- any future caller.
create policy claim_items_insert on claim_items for insert
  with check (exists (
    select 1 from claims c
     where c.id = claim_id and c.buyer_id = auth.uid()
  ));

-- Fixes bug 2, and adds the validation.
create or replace function create_claim(
  p_cook    uuid,
  p_session uuid,
  p_items   jsonb,      -- [{"menu_item_id": "...", "quantity": 2}, …]
  p_note    text default null
)
returns claims
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_buyer  uuid := auth.uid();
  v_claim  claims;
  v_open   boolean;
  v_bad    int;
begin
  if v_buyer is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  -- The session must be the cook's, and still open. A claim against a closed
  -- kitchen is how someone ends up driving to a dark house.
  select exists (
    select 1 from serving_sessions s
     where s.id = p_session and s.cook_id = p_cook and s.closed_at is null
  ) into v_open;

  if not v_open then
    raise exception 'that kitchen is not open right now' using errcode = 'P0002';
  end if;

  -- Every item must belong to this cook and be available. Prevents claiming a
  -- dish from someone else's menu, or one that just sold out.
  select count(*) into v_bad
    from jsonb_array_elements(p_items) e
   where not exists (
     select 1 from menu_items mi
      where mi.id = (e->>'menu_item_id')::uuid
        and mi.cook_id = p_cook
        and mi.is_available
   );

  if v_bad > 0 then
    raise exception 'one of those items is no longer available' using errcode = 'P0003';
  end if;

  insert into claims (cook_id, serving_session_id, buyer_id, status, note)
  values (p_cook, p_session, v_buyer, 'pending', p_note)
  returning * into v_claim;

  insert into claim_items (claim_id, menu_item_id, quantity)
  select v_claim.id, (e->>'menu_item_id')::uuid, (e->>'quantity')::int
    from jsonb_array_elements(p_items) e;

  return v_claim;
end $$;

grant execute on function create_claim(uuid, uuid, jsonb, text) to authenticated;

-- Clean up anything the broken two-step left behind.
delete from claims c
 where not exists (select 1 from claim_items ci where ci.claim_id = c.id)
   and c.status = 'pending';
