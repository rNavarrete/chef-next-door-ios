-- 057 — more than one photo per dish
--
-- `photo_url` (017) holds exactly one image. One photo is enough to prove a
-- dish is real, which was 017's whole argument, but it is not enough to sell
-- it: a tamal looks like a husk from the outside, and the picture that makes
-- someone order is the one of it opened. Cooks need to show the plate, the
-- cut, the spread, the portion in a hand.
--
-- ## An array, not a child table
--
-- The normalised shape would be `menu_item_photos(item_id, url, sort_order)`.
-- It is not worth it here. There is no per-photo data to hold — no caption, no
-- alt text, no dimensions — so the table would carry a surrogate key and an
-- ordinal to express something a Postgres array already expresses natively,
-- and every read would gain a join. Ordering is positional and the cap is
-- small and fixed. If per-photo metadata ever appears, that is the migration
-- that earns the table.
--
-- ## `photo_url` stays, and stays correct
--
-- Four functions read `mi.photo_url` to build the feed thumbnail —
-- `cooking_now` (056), `search_cooks` (017), `cooks_by_ids` (016), and the
-- headline logic in 025. Rewriting all four to read `photos[1]` would touch
-- every discovery path in the schema to change nothing a user can see.
--
-- So `photo_url` becomes a *derived* column, kept equal to `photos[1]` by a
-- trigger. Discovery is untouched. The one rule that matters: nothing may
-- write `photo_url` and expect it to stick unless it writes `photos` too — the
-- trigger reconciles both directions so an older client that sets only
-- `photo_url` still works.

set search_path = public, extensions;

alter table menu_items
  add column if not exists photos text[] not null default '{}';

-- Existing single photos become the first of the set. Runs before the
-- constraint so a hypothetical bad row fails loudly here rather than silently
-- surviving.
update menu_items
   set photos = array[photo_url]
 where photo_url is not null
   and cardinality(photos) = 0;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'menu_items_photos_max') then
    -- Four is the ask. The cap exists because this array is inlined into every
    -- discovery row; unbounded growth here is unbounded payload on the feed.
    alter table menu_items add constraint menu_items_photos_max
      check (cardinality(photos) <= 4);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'menu_items_photos_no_blanks') then
    -- An empty string is not a photo, and it would become a `photo_url` of ''
    -- which renders as a broken image rather than as "no photo".
    alter table menu_items add constraint menu_items_photos_no_blanks
      check (array_position(photos, '') is null and array_position(photos, null) is null);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Keep the derived column honest, from either direction.
-- ---------------------------------------------------------------------------
create or replace function sync_headline_photo() returns trigger
language plpgsql
set search_path = public, extensions as $$
begin
  if cardinality(new.photos) > 0 then
    -- The set is authoritative: the first photo is the headline, always.
    new.photo_url := new.photos[1];
  elsif new.photo_url is not null and nullif(trim(new.photo_url), '') is not null then
    -- Nothing in `photos` but a URL arrived: an older client, or a direct
    -- insert. Adopt it rather than dropping it on the floor.
    new.photos := array[new.photo_url];
  else
    -- Neither: normalise '' to NULL so "no photo" has exactly one spelling.
    new.photo_url := null;
  end if;
  return new;
end $$;

revoke all on function sync_headline_photo() from public, anon, authenticated;

drop trigger if exists menu_items_sync_headline_photo on menu_items;
-- Both names dropped: 045 and 047 each shipped a `create` whose name did not
-- match its own `drop`, and re-running them threw 42710.
drop trigger if exists menu_items_a_sync_headline_photo on menu_items;
create trigger menu_items_sync_headline_photo
  before insert or update of photos, photo_url on menu_items
  for each row execute function sync_headline_photo();

comment on column menu_items.photos is
  'Up to four cook photos, first is the headline. `photo_url` is derived from '
  'photos[1] by trigger — write this column, not that one.';

comment on column menu_items.photo_url is
  'DERIVED from photos[1] since migration 057. Kept because cooking_now, '
  'search_cooks and cooks_by_ids all read it; do not write it directly.';

-- No new grants. 011 already gives `authenticated` insert/update/delete on
-- menu_items, gated by the owner RLS policy, and a new column inherits that.
