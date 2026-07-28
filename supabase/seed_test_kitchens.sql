-- 35 lit kitchens across the San Gabriel Valley, for testing and demos.
--
--     npx supabase db query --linked --file supabase/seed_test_kitchens.sql
--
-- Teardown is one command, and you should run it before real cooks arrive:
--
--     npx supabase db query --linked --file supabase/seed_test_kitchens_teardown.sql
--
-- ## What this is for
--
-- An empty marketplace cannot be tested. You cannot judge the feed's density,
-- the map's clustering, the price-pill zoom threshold, or whether search is
-- useful, against one kitchen. This gives 35 — enough that the map clusters,
-- the feed scrolls, and search has to actually discriminate.
--
-- ## Honest about its limits
--
-- **Photography.** Seven real food photographs exist in this repo — bread,
-- cake, cookies, pizza, sandwich, spaghetti, tacos, each in five framings.
-- Every dish below is matched to whichever of those genuinely resembles it: a
-- torta gets the sandwich shot, birria gets the taco shot, tres leches gets the
-- cake. That is a real constraint, not a shortcut, and it is why you will see
-- the same seven images recur. Adding photographs is the only way to fix it.
--
-- **Avatars** are generated, not photographed — see Tools/MakeAvatars.swift.
-- Flat initials on the app's palette. They read as deliberate rather than as a
-- broken image, and inventing headshots of people who do not exist would be
-- worse than not having any.
--
-- **The cooks are fictional.** Names, stories and menus are invented. They are
-- plausible for the SGV because implausible test data hides real layout bugs —
-- a two-word name never wraps, and "Kim & Sons" and "Doña Chuy" break different
-- things. None of them claims a permit: every kitchen here is unbadged, because
-- a fake verified badge is the one thing in this app that must never be faked.
--
-- ## Cities
--
-- Spread west to east along the 10, Santa Monica to Covina — about 35 miles.
-- That is deliberately wider than the app's 12km search radius, so no single
-- origin sees all of them. It is the only way to exercise what the app is
-- actually for: searching a place, and finding that who is cooking depends on
-- where you are standing. A cluster that fits inside one radius would hide
-- every bug in that.
--
-- Pasadena, Long Beach and Vernon are deliberately absent — they run their own
-- health departments, are not in the county register, and would behave
-- differently for reasons unrelated to what you are testing.

set search_path = public, extensions;

do $$
declare
  v_base text := 'https://niehxlaegsuhdqbyikut.supabase.co/storage/v1/object/public/kitchen-photos/seed/seedpix/';
  -- kitchen-photos, NOT the avatars bucket. `avatars` is private by design —
  -- buyer profile pictures live there and are served through signed URLs
  -- (ProfileRepository). A *cook's* avatar is public, and PhotoUploader puts it
  -- in kitchen-photos. Seeding into `avatars` produced a public URL that
  -- returned 400 for every cook, and a Polaroid frame with nothing in it.
  v_av   text := 'https://niehxlaegsuhdqbyikut.supabase.co/storage/v1/object/public/kitchen-photos/seed/avatars/';
  v_user uuid;
  v_kitchen uuid;
  k record;
  d record;
  v_i int;
begin
  for k in
    select * from (values
      -- name, city, zip, lat, lon, street, contact, avatar slug, story
      ('Doña Chuy','Santa Monica','90401',34.0195,-118.4912,'1433 Third Street Promenade','(310) 555-0142','chuy',
       'Mi abuela made tamales every December for the whole block. When she passed in 2019 nobody made them, and that first Christmas without them felt wrong in a way I could not explain to my kids. So I learned. Badly at first — the masa was dense, the chile too smoky. Three years later my tía says they taste like her mother''s. That is the only review I have ever needed.'),
      ('Kim & Sons','Venice','90291',33.985,-118.4695,'1305 Abbot Kinney Blvd','(310) 555-0198','kim',
       'We ran a dumpling counter in a food court in Seoul for eleven years. My sons grew up folding them after school, and complained about it constantly. Now the eldest is 34 and calls on Sundays to argue about the filling ratio. The pleats are his mother''s; the chili oil is mine.'),
      ('Lupita S.','Mar Vista','90066',34.0,-118.43,'12444 Venice Blvd','(310) 555-0177','lupita',
       'I started baking to stay awake through night shifts at the hospital. Sourdough is patient in a way nothing else in my life was — it does not care that you are tired, it just needs you at the right hour. I have not worked nights in four years and I still get up at 4am.'),
      ('Beto R.','Culver City','90232',34.0211,-118.3965,'9500 Culver Blvd','(310) 555-0121','beto',
       'Birria is a Sunday food. That is not a rule, it is just how it was in my house — the pot going since Saturday night, everyone drifting into the kitchen. I sell it on Sundays only. People ask me to do Fridays and I say no, and they think I am difficult, and they are right.'),
      ('Priya N.','Palms','90034',34.028,-118.402,'3475 Motor Ave','(310) 555-0164','priya',
       'My mother-in-law taught me her dosa batter the week I got married, which I now understand was a test. It took me two years to get the fermentation right in California — the air here is drier than Chennai and the batter knows it. She has never said it is good. She has also never left any.'),
      ('Ana P.','West Los Angeles','90025',34.043,-118.445,'11301 Olympic Blvd','(310) 555-0133','ana',
       'I bake because my daughter has a nut allergy and every bakery within ten miles is a minefield. Once you learn to make everything from scratch you cannot stop. Now half my customers are parents who have read a hundred ingredient labels and are tired.'),
      ('Marisol T.','Westwood','90024',34.0635,-118.4455,'1099 Westwood Blvd','(310) 555-0155','marisol',
       'Pan dulce is not fancy and it is not supposed to be. Conchas, orejas, cuernitos. My father sold them from a bicycle in Puebla. I sell them from a house in Azusa, which he would have found extremely funny.'),
      ('Chef Danny','Beverly Hills','90211',34.065,-118.383,'8383 Wilshire Blvd','(310) 555-0188','danny',
       'Twelve years in restaurant kitchens, and the thing I missed was cooking for people I could see. Now I make forty pizzas on a Friday and I know most of the names. My back hurts less and I sleep at night.'),
      ('Rosa M.','Mid-City','90019',34.048,-118.34,'5371 W Pico Blvd','(323) 555-0109','rosa',
       'Pupusas were what my mother made when money was short, which was most of the time. Masa, beans, whatever cheese we had. I did not know they were special until I moved here and people started paying me for them.'),
      ('Yolanda V.','Koreatown','90006',34.048,-118.294,'3122 W Olympic Blvd','(213) 555-0142','yolanda',
       'Churros, and only churros. Everyone tells me to expand the menu. I have watched people expand the menu. I would rather make one thing so well that you think about it on the drive home.'),
      ('Mei L.','Pico-Union','90015',34.043,-118.267,'1420 S Union Ave','(213) 555-0171','mei',
       'My grandmother''s noodle recipe is four ingredients and forty years of feel. I have written it down six times and it is wrong every time. Come watch me make it and you will learn more in ten minutes than the paper will ever tell you.'),
      ('Armen K.','Downtown Los Angeles','90013',34.045,-118.24,'317 S Broadway','(213) 555-0119','armen',
       'Lahmajun, the way my mother made it in Yerevan — thin enough to fold, never thick. My kids grew up thinking this was normal Tuesday food. It is, in my house.'),
      ('Nena G.','Echo Park','90026',34.078,-118.26,'1511 Sunset Blvd','(213) 555-0146','nena',
       'I make flan because it is the dessert nobody makes at home anymore and everybody misses. Six ingredients. No shortcuts. If it has cracks on top I do not sell it.'),
      ('Tuan P.','Silver Lake','90039',34.095,-118.26,'2903 Rowena Ave','(323) 555-0187','tuan',
       'Bánh mì is a sandwich that argues with itself — pickled and rich and hot and cold all at once. My father ran a stand in Đà Nẵng. His bread was better. I am still working on the bread.'),
      ('Sofia C.','Highland Park','90042',34.113,-118.192,'5619 N Figueroa St','(323) 555-0138','sofia',
       'Tres leches was my mother''s birthday cake for every one of us, seven kids, seven birthdays a year. She is 81 and does not bake anymore, so now I do. Same pan. It has a dent in it.'),
      ('Ricardo B.','Eagle Rock','90041',34.139,-118.211,'2118 Colorado Blvd','(323) 555-0192','ricardo',
       'Carnitas take five hours and cannot be rushed, which is the whole appeal. I put the pot on and the day organises itself around it. My wife says it is the only time I sit still.'),
      ('Grace O.','Glendale','91205',34.14,-118.255,'316 N Brand Blvd','(818) 555-0173','grace',
       'Pancit for every birthday, every graduation, every funeral. Long noodles for long life — my lola was serious about it. I do not know if I believe it, but I have never once made it short.'),
      ('Hassan A.','South Pasadena','91030',34.116,-118.15,'1012 Mission St','(626) 555-0116','hassan',
       'My mother''s mansaf is a wedding dish, which means it is not a thing you make for two people. So I make it for thirty, and I have stopped apologising for the minimum order.'),
      ('Jasmine W.','Alhambra','91801',34.0953,-118.127,'320 W Main St','(626) 555-0154','jasmine',
       'I make the cookies my mother sent me at college — the ones that arrived broken and I ate anyway. Mine arrive whole. I am not sure that is an improvement.'),
      ('Paolo R.','San Gabriel','91776',34.0961,-118.1058,'140 W Valley Blvd','(626) 555-0128','paolo',
       'Sicilian, thick, in a pan, the way my nonno did it. Every time somebody asks for thin crust I tell them where the good thin-crust place is, and I mean it kindly.'),
      ('Fatima Z.','Monterey Park','91754',34.0625,-118.1228,'500 N Atlantic Blvd','(626) 555-0163','fatima',
       'Msemen takes a hundred folds and about that many failures before your hands learn it. Nobody can teach you the pressure. My mother tried for a year.'),
      ('Diego M.','Montebello','90640',34.0165,-118.1137,'2100 W Beverly Blvd','(323) 555-0141','diego',
       'Al pastor without a trompo is a compromise and I will admit that up front. What I do have is my uncle''s adobo, and a very hot pan, and thirty years of eating the real thing.'),
      ('Linh T.','Rosemead','91770',34.0806,-118.0728,'8632 Valley Blvd','(626) 555-0195','linh',
       'Phở broth runs twelve hours and the house smells like star anise for two days after. My neighbours have stopped mentioning it, which I choose to read as approval.'),
      ('Carmen D.','Temple City','91780',34.1072,-118.0578,'9601 Las Tunas Dr','(626) 555-0107','carmen',
       'Empanadas, Argentine, baked not fried, and the repulgue matters — the crimp tells you what is inside. Mine are ugly for the first dozen every time and then my hands remember.'),
      ('Ben S.','Arcadia','91006',34.1397,-118.0353,'400 S Baldwin Ave','(626) 555-0182','ben',
       'Challah on Fridays. That is it, that is the whole business. I braid six strands because four looked lazy and eight looked like showing off.'),
      ('Aiko N.','El Monte','91731',34.0686,-118.0276,'11333 Valley Blvd','(626) 555-0159','aiko',
       'Katsu sando is convenience-store food in Japan and I refuse to be precious about it. Good pork, good bread, too much sauce. It should be slightly difficult to eat.'),
      ('Miguel A.','Whittier','90602',33.9792,-118.0328,'6742 Greenleaf Ave','(562) 555-0174','miguel',
       'Quesabirria is new and people act like it is heresy. My grandfather would have loved it. He put cheese on everything and nobody stopped him either.'),
      ('Ruth E.','Pico Rivera','90660',33.9831,-118.0967,'6615 Passons Blvd','(562) 555-0136','ruth',
       'Carrot cake, cream cheese frosting, walnuts unless you tell me otherwise. My husband asked for it every year for thirty-one years. I still make it on his birthday and give it away.'),
      ('Javier O.','Duarte','91010',34.1394,-117.977,'1600 Huntington Dr','(626) 555-0148','javier',
       'Tacos de canasta — steamed, soft, wrapped in cloth in a basket. This is not restaurant food and it never was. It is the food of somebody with a bicycle and somewhere to be.'),
      ('Hana K.','Baldwin Park','91706',34.0853,-117.9609,'4021 Maine Ave','(626) 555-0193','hana',
       'Japchae for celebrations, which in my family means roughly every eleven days. Sweet potato noodles, done right, should squeak slightly against your teeth.'),
      ('Oscar V.','West Covina','91790',34.0686,-117.939,'1442 W Merced Ave','(626) 555-0125','oscar',
       'Tortas ahogadas, drowned properly, which means you will need a fork and probably a second napkin. If you can pick it up I have not done my job.'),
      ('Sunny P.','La Puente','91744',34.02,-117.9495,'15905 Amar Rd','(626) 555-0117','sunny',
       'Mooncakes, and only for six weeks a year. The moulds were my mother''s. One of them is cracked and I will not replace it — that crack is on every cake I make.'),
      ('Delia F.','Hacienda Heights','91745',33.9931,-117.9686,'1731 Hacienda Blvd','(626) 555-0169','delia',
       'Polvorones that fall apart if you look at them, which is the point. My tía calls them Mexican wedding cookies. My kids call them the sand ones. Both are correct.'),
      ('Marco T.','Azusa','91702',34.1336,-117.9076,'809 N San Gabriel Ave','(626) 555-0184','marco',
       'Focaccia with whatever the garden gives me. In August it is tomatoes and it is very good. In February it is rosemary and it is fine. I do not pretend otherwise.'),
      ('Estela R.','Covina','91722',34.09,-117.8903,'1148 N Puente Ave','(626) 555-0151','estela',
       'Champurrado and tamales, together, because that is how they are eaten and separating them never made sense to me. Cold mornings only. When it warms up I stop.')
    ) as t(name, city, zip, lat, lon, street, contact, slug, story)
  loop
    -- opened_by_user is a NO ACTION foreign key (063): a plain delete of the
    -- auth user trips it. Nulled first, exactly as delete_my_account() does.
    update serving_sessions set opened_by_user = null
     where opened_by_user in (
       select id from auth.users
        where email = 'seed.' || k.slug || '@litkitchen.test');

    delete from auth.users
     where email = 'seed.' || k.slug || '@litkitchen.test';

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data, is_anonymous
    ) values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
      'authenticated', 'authenticated',
      'seed.' || k.slug || '@litkitchen.test',
      crypt('litkitchen', gen_salt('bf')),
      now(), now(), now(), '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false
    ) returning id into v_user;

    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      v_user::text, v_user,
      jsonb_build_object('sub', v_user::text,
                         'email', 'seed.' || k.slug || '@litkitchen.test',
                         'email_verified', true),
      'email', now(), now(), now()
    );

    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user::text)::text, true);

    -- Through the real RPC, so the public point is fuzzed exactly as a genuine
    -- registration's would be and the agency lookup actually runs.
    select register_cook(
      p_display_name   => k.name,
      p_contact_method => 'sms',
      p_contact_value  => k.contact,
      p_street         => k.street,
      p_city           => k.city,
      p_postal_code    => k.zip,
      p_latitude       => k.lat,
      p_longitude      => k.lon,
      p_neighborhood   => k.city,
      p_permit_kind    => null,
      p_permit_number  => null
    ) into v_kitchen;

    update cooks
       set bio = k.story,
           avatar_url = v_av || k.slug || '.jpg'
     where id = v_user;

    -- Lit, with the light on at a plausible spread of times rather than all at
    -- once — the feed sorts by freshness, and 35 identical timestamps would
    -- hide whether that ordering works at all.
    perform open_kitchen(v_kitchen, null);
    update serving_sessions
       set opened_at = now() - (random() * interval '5 hours'),
           last_confirmed_at = now() - (random() * interval '90 minutes')
     where cook_id = v_user and closed_at is null;
  end loop;
end $$;

select count(*) as seeded_cooks from cooks
 where id in (select id from auth.users where email like 'seed.%@litkitchen.test');
