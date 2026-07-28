-- 026 — menu order that the app actually maintains
--
-- 019 added `sort_order` to let a cook choose which dish leads their card, and
-- backfilled the seeded rows. Nothing ever wrote it again: the menu builder
-- inserts without it, so every cook-created dish landed on the default `0` and
-- the headline fell through to the `created_at, id` tiebreak.
--
-- Invisible until cooks could upload photos (024/025), at which point the
-- headline dish — the one whose name and photo carry the whole feed card —
-- was effectively chosen at random.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Backfill. Every cook's menu gets a dense 1..n order, preserving whatever
-- order they already had (019's backfill, then insertion order).
-- ---------------------------------------------------------------------------
with ranked as (
  select id,
         row_number() over (
           partition by cook_id
           order by sort_order, created_at, id
         ) as rn
    from menu_items
)
update menu_items m
   set sort_order = r.rn
  from ranked r
 where r.id = m.id
   and m.sort_order is distinct from r.rn;

-- ---------------------------------------------------------------------------
-- New dishes append rather than tie.
--
-- Server-side because two dishes added from two devices would otherwise race
-- to the same max+1. It also means the client can keep sending 0 and stay
-- ignorant of ordering, which is the right split — the client has no way to
-- know what else is on the menu without an extra round trip.
-- ---------------------------------------------------------------------------
create or replace function menu_item_append_order() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.sort_order is null or new.sort_order = 0 then
    select coalesce(max(sort_order), 0) + 1
      into new.sort_order
      from menu_items
     where cook_id = new.cook_id;
  end if;
  return new;
end $$;

drop trigger if exists menu_items_append_order on menu_items;
create trigger menu_items_append_order
  before insert on menu_items
  for each row execute function menu_item_append_order();

-- ---------------------------------------------------------------------------
-- "Make this the one people see first."
--
-- A full renumber rather than `min - 1`, so the values stay dense and a cook
-- who promotes a dish every day doesn't drift into negative numbers.
-- ---------------------------------------------------------------------------
create or replace function set_menu_headline(p_item uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_cook uuid;
begin
  select cook_id into v_cook from menu_items where id = p_item;
  if v_cook is null or v_cook <> auth.uid() then
    raise exception 'not authorized';
  end if;

  with ordered as (
    select id,
           row_number() over (
             order by (id = p_item) desc, sort_order, created_at, id
           ) as rn
      from menu_items
     where cook_id = v_cook
  )
  update menu_items m
     set sort_order = o.rn
    from ordered o
   where o.id = m.id;
end $$;

revoke all on function set_menu_headline(uuid) from public, anon;
grant execute on function set_menu_headline(uuid) to authenticated;

comment on function set_menu_headline is
  'Promotes one dish to sort_order 1 and renumbers the rest, so the feed '
  'card''s name and photo come from the dish the cook chose.';
