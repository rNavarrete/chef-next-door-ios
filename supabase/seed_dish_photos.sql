-- Seed dish photo sets — four per dish.
--
-- Not a migration. This is development data and must never run against a real
-- deployment: it overwrites `menu_items.photos` for every seeded dish.
--
--     npx supabase db query --linked --file supabase/seed_dish_photos.sql
--
-- ## Why four framings rather than four dishes
--
-- Migration 057 lets a cook attach up to four photos, and the dish page
-- (`DishDetailSheet`) is a swipeable gallery with a thumbnail strip. Testing
-- that needs dishes that actually *have* four photos, and the seed set only
-- ever had seven images total — one per food category.
--
-- Padding each dish out with the other categories' images would put cookies in
-- a pizza gallery, which tests the carousel while making every screenshot
-- useless. So each category image was cropped into four framings — the whole
-- plate, a closer crop, an off-centre detail, a tight macro — which is roughly
-- the set a real cook shoots, and keeps every photo in a gallery on-topic.
--
-- Generated locally with `sips` from the existing seed images and uploaded to
-- `kitchen-photos/seed/seedpix/` with `supabase storage cp`. The originals at
-- `seed/<name>.jpg` are left in place; `-1` is a copy of each.
--
-- ## Ordering matters
--
-- `photos[1]` is the headline: migration 057's trigger derives `photo_url` from
-- it, and that drives the feed card, the map pin and search. So the first entry
-- of every set is the full-plate framing — the one that reads at thumbnail
-- size. The tight macro is last, where it belongs.

set search_path = public, extensions;

do $$
declare
  v_base text := 'https://niehxlaegsuhdqbyikut.supabase.co/storage/v1/object/public/kitchen-photos/seed/seedpix/';
  v_cat  text;
  v_rows int;
begin
  -- Each dish already carries a category image as its single photo. That
  -- assignment was made by hand last session against the dish names, so it is
  -- the mapping to preserve — this only widens each one into a set.
  foreach v_cat in array array['pizza','tacos','cookies','sandwich','spaghetti','bread','cake']
  loop
    update menu_items
       set photos = array[
             v_base || v_cat || '-1.jpg',
             v_base || v_cat || '-2.jpg',
             v_base || v_cat || '-3.jpg',
             v_base || v_cat || '-4.jpg'
           ]
     where photo_url like '%/seed/' || v_cat || '.jpg'
        -- Re-runnable: matches sets this script wrote on a previous pass too.
        or photos[1] like '%/seedpix/' || v_cat || '-1.jpg';

    get diagnostics v_rows = row_count;
    raise notice '% -> % dishes', v_cat, v_rows;
  end loop;
end $$;

-- The trigger from 057 keeps `photo_url` equal to `photos[1]`, so discovery
-- needs no separate update. Proving that here rather than assuming it.
select
  count(*)                                                     as dishes,
  count(*) filter (where cardinality(photos) = 4)              as with_four,
  count(*) filter (where photo_url is distinct from photos[1]) as headline_out_of_sync
from menu_items;
