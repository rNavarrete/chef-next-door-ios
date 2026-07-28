-- Menus for the seeded kitchens. Run after seed_test_kitchens.sql.
--
--     npx supabase db query --linked --file supabase/seed_test_menus.sql
--
-- ## The photo matching
--
-- Seven photographs exist: bread, cake, cookies, pizza, sandwich, spaghetti,
-- tacos. Every dish here is assigned the one that genuinely looks like it —
-- a torta is a sandwich, birria is tacos, tres leches is cake, pancit is
-- noodles. Nothing is assigned at random, because a taco photo on a mooncake
-- is worse than no photo: it makes the whole feed read as placeholder and you
-- stop noticing real layout problems.
--
-- Where a cuisine has no matching photograph — mansaf, phở, dosa, msemen — the
-- dish carries no photo at all rather than a misleading one. That is also worth
-- testing: the feed and dish page both have to handle a dish with nothing to
-- show, and roughly a fifth of these do.
--
-- Each photographed dish gets all four framings, so the dish page's gallery and
-- its thumbnail strip have something to page through (057).
--
-- ## Prices
--
-- Deliberately varied in unit and minimum: each, half dozen, dozen, tray. The
-- feed card renders "from $X" off the cheapest, and a menu where everything is
-- $3 each never exercises that.

set search_path = public, extensions;

do $$
declare
  v_base text := 'https://niehxlaegsuhdqbyikut.supabase.co/storage/v1/object/public/kitchen-photos/seed/seedpix/';
  v_cook uuid;
  d record;
  v_photos text[];
  v_off int;
begin
  -- Idempotent. Without this a second run appends a duplicate menu to every
  -- seeded cook, because sort_order is derived from the existing count.
  delete from menu_items
   where cook_id in (select id from auth.users
                      where email like 'seed.%@litkitchen.test');

  for d in
    select * from (values
      -- slug, name_en, name_es, category, pic (null = no photo), cents, unit, min, allergens, description
      ('chuy','Pork tamale','Tamal de puerco','tamales','tacos',300,'each',3,array['Pork','Corn'],'Pork shoulder, chile colorado, masa de maíz.'),
      ('chuy','Sweet tamale','Tamal de dulce','tamales','cake',300,'each',3,array['Corn','Dairy'],'Pineapple and raisin, pink masa.'),
      ('chuy','Champurrado','Champurrado','drinks',null,400,'each',1,array['Corn','Dairy'],'Masa, chocolate, canela. Hot.'),
      ('kim','Pork dumplings','Dumplings de puerco','dumplings','spaghetti',1400,'dozen',1,array['Pork','Gluten','Soy'],'Hand-folded, thin skin, chive and pork.'),
      ('kim','Kimchi dumplings','Dumplings de kimchi','dumplings','spaghetti',1400,'dozen',1,array['Gluten','Soy'],'Aged kimchi, tofu, sesame.'),
      ('lupita','Sourdough loaf','Masa madre','bread','bread',900,'each',1,array['Gluten'],'Two-day ferment, dark crust.'),
      ('lupita','Seeded rye','Centeno con semillas','bread','bread',1000,'each',1,array['Gluten','Sesame'],'Caraway, sunflower, flax.'),
      ('beto','Birria de res','Birria de res','tacos','tacos',400,'each',3,array['Beef','Corn'],'Sunday only. Consomé on the side.'),
      ('beto','Quesabirria','Quesabirria','tacos','tacos',500,'each',3,array['Beef','Corn','Dairy'],'Griddled with Oaxaca cheese.'),
      ('priya','Masala dosa','Dosa masala','breakfast',null,800,'each',1,array['Gluten'],'Fermented three days. Potato masala, coconut chutney.'),
      ('priya','Idli','Idli','breakfast',null,600,'half_dozen',1,array[]::text[],'Steamed, with sambar.'),
      ('ana','Chocolate chip cookie','Galleta de chocolate','cookies','cookies',300,'each',4,array['Gluten','Dairy','Egg'],'Nut-free kitchen. Browned butter.'),
      ('ana','Banana bread','Pan de plátano','bread','bread',1200,'each',1,array['Gluten','Egg'],'Nut-free. Very ripe bananas only.'),
      ('marisol','Concha','Concha','pan dulce','bread',250,'each',4,array['Gluten','Dairy','Egg'],'Vanilla and chocolate shell.'),
      ('marisol','Oreja','Oreja','pan dulce','bread',250,'each',4,array['Gluten','Dairy'],'Palmier, caramelised edges.'),
      ('danny','Margherita pizza','Pizza margarita','pizza','pizza',1600,'each',1,array['Gluten','Dairy'],'Fior di latte, basil, 48-hour dough.'),
      ('danny','Pepperoni pizza','Pizza de pepperoni','pizza','pizza',1800,'each',1,array['Gluten','Dairy','Pork'],'Cup-and-char pepperoni.'),
      ('rosa','Pupusa revuelta','Pupusa revuelta','pupusas',null,350,'each',3,array['Corn','Pork','Dairy'],'Bean, cheese, chicharrón. Curtido included.'),
      ('rosa','Pupusa de queso','Pupusa de queso','pupusas',null,300,'each',3,array['Corn','Dairy'],'Quesillo, hand-pressed.'),
      ('yolanda','Churros','Churros','desserts','cookies',900,'half_dozen',1,array['Gluten','Dairy'],'Cinnamon sugar. Cajeta on request.'),
      ('mei','Hand-pulled noodles','Fideos hechos a mano','noodles','spaghetti',1100,'each',1,array['Gluten'],'Pulled to order. Beef broth or dry.'),
      ('mei','Scallion pancake','Pan de cebollín','snacks','bread',600,'each',1,array['Gluten'],'Flaky, blistered.'),
      ('armen','Lahmajun','Lahmajun','flatbread','pizza',400,'each',4,array['Gluten','Beef'],'Thin. Fold it, do not eat it flat.'),
      ('nena','Flan','Flan','desserts','cake',500,'each',2,array['Dairy','Egg'],'Six ingredients. No cracks or it does not leave the kitchen.'),
      ('tuan','Bánh mì thịt','Bánh mì','sandwiches','sandwich',900,'each',1,array['Gluten','Pork','Egg'],'Pâté, cold cuts, pickled daikon and carrot.'),
      ('tuan','Bánh mì chay','Bánh mì vegetariano','sandwiches','sandwich',800,'each',1,array['Gluten','Soy'],'Lemongrass tofu.'),
      ('sofia','Tres leches','Tres leches','cakes','cake',3200,'each',1,array['Dairy','Egg','Gluten'],'Whole cake. Soaked overnight.'),
      ('ricardo','Carnitas','Carnitas','tacos','tacos',1800,'each',1,array['Pork'],'By the pound. Five hours, no rush.'),
      ('grace','Pancit bihon','Pancit bihon','noodles','spaghetti',2400,'tray',1,array['Soy','Gluten'],'Feeds eight. Long noodles, long life.'),
      ('grace','Lumpia','Lumpia','snacks',null,1200,'dozen',1,array['Pork','Gluten','Egg'],'Fried to order.'),
      ('hassan','Mansaf','Mansaf','mains',null,4500,'tray',1,array['Dairy','Lamb'],'Serves ten. Two days'' notice.'),
      ('jasmine','Oatmeal raisin cookie','Galleta de avena','cookies','cookies',300,'each',4,array['Gluten','Dairy','Egg'],'Chewy, not crisp.'),
      ('paolo','Sicilian pizza','Pizza siciliana','pizza','pizza',2400,'each',1,array['Gluten','Dairy'],'Thick, in a pan, 90-minute proof.'),
      ('fatima','Msemen','Msemen',' flatbread',null,500,'each',2,array['Gluten'],'A hundred folds. Honey or savoury.'),
      ('diego','Tacos al pastor','Tacos al pastor','tacos','tacos',350,'each',4,array['Pork','Corn'],'Adobo marinated overnight. Pineapple.'),
      ('linh','Phở bò','Phở de res','soups',null,1400,'each',1,array['Beef'],'Twelve-hour broth. Herbs on the side.'),
      ('carmen','Beef empanada','Empanada de carne','empanadas','bread',400,'each',3,array['Gluten','Beef','Egg'],'Baked. Olive and egg inside.'),
      ('carmen','Ham and cheese empanada','Empanada de jamón y queso','empanadas','bread',400,'each',3,array['Gluten','Pork','Dairy'],'Baked.'),
      ('ben','Challah','Challah','bread','bread',1000,'each',1,array['Gluten','Egg'],'Six strands. Fridays only.'),
      ('aiko','Katsu sando','Katsu sando','sandwiches','sandwich',1200,'each',1,array['Gluten','Pork','Egg'],'Milk bread, tonkatsu sauce, too much cabbage.'),
      ('miguel','Quesabirria','Quesabirria','tacos','tacos',500,'each',3,array['Beef','Corn','Dairy'],'Consomé included.'),
      ('ruth','Carrot cake','Pastel de zanahoria','cakes','cake',3000,'each',1,array['Gluten','Dairy','Egg','Nuts'],'Cream cheese frosting. Say the word and I leave the walnuts out.'),
      ('javier','Tacos de canasta','Tacos de canasta','tacos','tacos',200,'each',5,array['Corn','Pork'],'Steamed, soft. Potato, chicharrón or bean.'),
      ('hana','Japchae','Japchae','noodles','spaghetti',1600,'tray',1,array['Soy','Sesame','Egg'],'Sweet potato noodles. Serves four.'),
      ('oscar','Torta ahogada','Torta ahogada','sandwiches','sandwich',1000,'each',1,array['Gluten','Pork'],'Properly drowned. Bring a fork.'),
      ('sunny','Lotus mooncake','Mooncake de loto','desserts','cake',600,'each',4,array['Gluten','Egg','Nuts'],'Salted yolk centre. Six weeks a year.'),
      ('delia','Polvorones','Polvorones','cookies','cookies',1000,'dozen',1,array['Gluten','Dairy','Nuts'],'Falls apart if you look at it.'),
      ('marco','Focaccia','Focaccia','bread','bread',1100,'each',1,array['Gluten'],'Whatever the garden has. Ask.'),
      ('estela','Tamal verde','Tamal verde','tamales','tacos',300,'each',3,array['Corn','Chicken'],'Salsa verde, chicken. Cold mornings only.'),
      ('estela','Champurrado','Champurrado','drinks',null,400,'each',1,array['Corn','Dairy'],'Thick. The way it should be.'),
      ('marisav','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('tranh','Sandwich','Torta','sandwiches','sandwich',1000,'each',1,array['Gluten'],'Made to order.'),
      ('kenji','Sandwich','Torta','sandwiches','sandwich',1000,'each',1,array['Gluten'],'Made to order.'),
      ('rocio','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('nadia','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('samo','Pizza','Pizza','pizza','pizza',1700,'each',1,array['Gluten','Dairy'],'Made to order.'),
      ('lorena','Cookies','Galletas','cookies','cookies',1000,'half_dozen',1,array['Gluten','Dairy'],'Made to order.'),
      ('devi','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('bao','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('elena','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('ahmad','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('kail','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('gloria','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('yusuf','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('priscila','Cookies','Galletas','cookies','cookies',1000,'half_dozen',1,array['Gluten','Dairy'],'Made to order.'),
      ('ravi','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('camila','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('mateo','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('aisha','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('hugo','Pizza','Pizza','pizza','pizza',1700,'each',1,array['Gluten','Dairy'],'Made to order.'),
      ('simone','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('ivan','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('luciaf','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('omar','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('bianca','Cookies','Galletas','cookies','cookies',1000,'half_dozen',1,array['Gluten','Dairy'],'Made to order.'),
      ('terrence','Sandwich','Torta','sandwiches','sandwich',1000,'each',1,array['Gluten'],'Made to order.'),
      ('jiwoo','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('fernanda','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('noor','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('marisolq','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('davida','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('rosalinda','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('nina','Pizza','Pizza','pizza','pizza',1700,'each',1,array['Gluten','Dairy'],'Made to order.'),
      ('tomas','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('kalani','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('anasofia','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('hyunj','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('beatriz','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('efrain','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('malia','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('ines','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('zaid','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('paloma','Cookies','Galletas','cookies','cookies',1000,'half_dozen',1,array['Gluten','Dairy'],'Made to order.'),
      ('tenzin','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('consuelo','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('andresm','Sandwich','Torta','sandwiches','sandwich',1000,'each',1,array['Gluten'],'Made to order.'),
      ('sunisa','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('georgi','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('rosaelena','Cake slice','Rebanada de pastel','cakes','cake',600,'each',2,array['Dairy','Egg','Gluten'],'Made to order.'),
      ('weic','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('farah','Noodles','Fideos','noodles','spaghetti',1300,'each',1,array['Gluten','Soy'],'Made to order.'),
      ('julio','Tacos','Tacos','tacos','tacos',350,'each',3,array['Corn'],'Made to order.'),
      ('amara','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.'),
      ('lidia','Cookies','Galletas','cookies','cookies',1000,'half_dozen',1,array['Gluten','Dairy'],'Made to order.'),
      ('nasrin','Fresh bread','Pan fresco','bread','bread',800,'each',1,array['Gluten'],'Made to order.')
    ) as t(slug, name_en, name_es, category, pic, cents, unit, minqty, allergens, descr)
  loop
    select id into v_cook from auth.users
     where email = 'seed.' || d.slug || '@litkitchen.test';
    continue when v_cook is null;

    -- All four framings, but rotated so the *headline* differs per dish.
    -- Seven photographs across fifty dishes means categories repeat; without
    -- this, two tamale cooks sat adjacent in the feed showing byte-identical
    -- images, which reads as a rendering bug rather than as two kitchens.
    -- Derived from the dish, so it is stable across re-seeds.
    v_off := abs(hashtext(d.slug || d.name_en)) % 4;
    v_photos := case when d.pic is null then null else array[
      v_base || d.pic || '-' || (((v_off + 0) % 4) + 1) || '.jpg',
      v_base || d.pic || '-' || (((v_off + 1) % 4) + 1) || '.jpg',
      v_base || d.pic || '-' || (((v_off + 2) % 4) + 1) || '.jpg',
      v_base || d.pic || '-' || (((v_off + 3) % 4) + 1) || '.jpg'
    ] end;

    insert into menu_items
      (cook_id, name_en, name_es, category, category_type, description,
       amount_cents, unit, min_quantity, allergens, is_available,
       photos, photo_url,
       sort_order)
    values
      (v_cook, d.name_en, d.name_es, trim(d.category), 'mehko_meal', d.descr,
       d.cents, d.unit::price_unit, d.minqty, d.allergens, true,
       coalesce(v_photos, array[]::text[]),
       case when v_photos is null then null else v_photos[1] end,
       (select count(*) from menu_items m where m.cook_id = v_cook));
  end loop;
end $$;

select
  (select count(*) from menu_items mi
     join auth.users u on u.id = mi.cook_id
    where u.email like 'seed.%@litkitchen.test') as dishes,
  (select count(*) from menu_items mi
     join auth.users u on u.id = mi.cook_id
    where u.email like 'seed.%@litkitchen.test'
      and coalesce(array_length(mi.photos,1),0) > 0) as with_photos,
  (select count(distinct mi.cook_id) from menu_items mi
     join auth.users u on u.id = mi.cook_id
    where u.email like 'seed.%@litkitchen.test') as cooks_with_menus;
