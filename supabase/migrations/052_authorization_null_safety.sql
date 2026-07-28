-- 052 — an anonymous caller could turn on a stranger's kitchen
--
-- `open_kitchen` (005) guards itself with:
--
--     if v_cook is null or v_cook <> auth.uid() then
--       raise exception 'not authorized';
--     end if;
--
-- For an anonymous caller `auth.uid()` is NULL, so `v_cook <> NULL` evaluates
-- to NULL, `false OR NULL` is NULL, and `IF NULL THEN` does **not** branch. The
-- exception never fires. Verified, not theorised: an `anon` session called
-- `open_kitchen` against another cook's kitchen, a `serving_sessions` row was
-- created, and `cooks.serving_status` became `'serving'`.
--
-- What that means in the world: **any stranger could advertise any cook's home
-- as cooking right now**, and buyers would walk to a door where nobody is
-- expecting them. That is the exact failure the decay ladder, the address gate
-- and the fuzzed public point all exist to prevent, reachable through a hole in
-- three-valued logic.
--
-- `answer_claim` (008/029) carries the identical guard, and is worse in kind:
-- confirming a claim is what unlocks `reveal_address`, so the same NULL could
-- be used to release a cook's street address to a buyer the cook never
-- answered.
--
-- ## Two fixes, because either alone is thin
--
-- 1. **`is distinct from`**, which is NULL-safe: `uuid is distinct from NULL`
--    is true, so the exception fires. Plus an explicit unauthenticated check,
--    so the intent is legible rather than depending on an operator subtlety.
-- 2. **Revoke from `anon`.** Postgres makes every new function EXECUTE-able by
--    PUBLIC, and these were never revoked — so the logic bug was reachable at
--    all only because the door was open. A cook action should not be callable
--    by someone with no account, whatever the body does.
--
-- `cook_is_blocked`, `i_am_blocked_by` and `follower_count` stay public: the
-- anonymous feed reads through them, and 028 documents why.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. NULL-safe guards.
-- ---------------------------------------------------------------------------
create or replace function open_kitchen(p_kitchen uuid, p_note text default null)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_cook uuid; v_session uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select cook_id into v_cook from kitchens where id = p_kitchen;
  -- `is distinct from`, NOT `<>`. See the header.
  if v_cook is null or v_cook is distinct from auth.uid() then
    raise exception 'not authorized';
  end if;

  -- Idempotent: re-opening while already open just confirms the session,
  -- so a double-tap on the burner can never create a second one.
  select id into v_session
    from serving_sessions where cook_id = v_cook and closed_at is null;

  if v_session is not null then
    update serving_sessions set last_confirmed_at = now() where id = v_session;
  else
    insert into serving_sessions (cook_id, kitchen_id)
    values (v_cook, p_kitchen)
    returning id into v_session;
  end if;

  update cooks
     set serving_status = 'serving',
         serving_note = coalesce(nullif(trim(coalesce(p_note, '')), ''), serving_note)
   where id = v_cook;

  return v_session;
end $$;

create or replace function answer_claim(p_claim uuid, p_status claim_status)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_cook uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  if p_status not in ('confirmed', 'cancelled', 'no_show') then
    raise exception 'a cook may only confirm, cancel, or mark no-show';
  end if;

  select cook_id into v_cook from claims where id = p_claim;
  if v_cook is null or v_cook is distinct from auth.uid() then
    raise exception 'not authorized';
  end if;

  update claims set status = p_status where id = p_claim;
end $$;

create or replace function set_menu_headline(p_item uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_cook uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select cook_id into v_cook from menu_items where id = p_item;
  if v_cook is null or v_cook is distinct from auth.uid() then
    raise exception 'not authorized';
  end if;

  update menu_items set sort_order = sort_order + 1 where cook_id = v_cook;
  update menu_items set sort_order = 1 where id = p_item;

  with renumbered as (
    select id, row_number() over (order by sort_order, created_at, id) as rn
      from menu_items where cook_id = v_cook
  )
  update menu_items mi set sort_order = r.rn
    from renumbered r where r.id = mi.id;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Close the door as well as fixing the lock.
-- ---------------------------------------------------------------------------
revoke all on function open_kitchen(uuid, text)                    from public, anon;
revoke all on function close_kitchen(text)                         from public, anon;
revoke all on function confirm_session(uuid)                       from public, anon;
revoke all on function answer_claim(uuid, claim_status)            from public, anon;
revoke all on function create_claim(uuid, uuid, jsonb, text)       from public, anon;
revoke all on function set_menu_headline(uuid)                     from public, anon;
revoke all on function my_conversations()                          from public, anon;

grant execute on function open_kitchen(uuid, text)              to authenticated;
grant execute on function close_kitchen(text)                   to authenticated;
grant execute on function confirm_session(uuid)                 to authenticated;
grant execute on function answer_claim(uuid, claim_status)      to authenticated;
grant execute on function create_claim(uuid, uuid, jsonb, text) to authenticated;
grant execute on function set_menu_headline(uuid)               to authenticated;
grant execute on function my_conversations()                    to authenticated;

-- Trigger functions. Never usefully callable by hand, but PUBLIC-executable by
-- default, and one of them posts to the push endpoint.
revoke all on function drop_dead_activity_tokens()   from public, anon, authenticated;
revoke all on function menu_item_append_order()      from public, anon, authenticated;
revoke all on function push_claim_update()           from public, anon, authenticated;
revoke all on function sync_public_point()           from public, anon, authenticated;
revoke all on function touch_on_item_availability()  from public, anon, authenticated;
revoke all on function touch_on_note_edit()          from public, anon, authenticated;

comment on function open_kitchen is
  'Cook-only. Guarded with `is distinct from`, not `<>`: under `<>` an '
  'anonymous caller compared against a NULL auth.uid() and the check silently '
  'did not fire.';
