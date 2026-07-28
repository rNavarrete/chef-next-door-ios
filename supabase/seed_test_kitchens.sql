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
-- **Avatars** are placeholder portraits from pravatar.cc, fetched once into
-- supabase/seed-assets/portraits and uploaded to storage — not generated, and
-- not tied to the cook they sit above. The pool holds 70 distinct faces, so
-- with 90 cooks about twenty share one; that is the source's ceiling, not an
-- oversight.
--
-- They will not match the names or the stories: the grandmother who learned her
-- abuela's tamales may appear as a man in his twenties. That is the trade for
-- having real photographs at all, and real photographs earn their place here by
-- stressing the layout the way a cook's own upload will — skin tones, contrast,
-- busy backgrounds — which flat initials never did.
--
-- Tools/MakeAvatars.swift still generates the initials fallback if you would
-- rather have marks that make no claim about anybody.
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
  v_av   text := 'https://niehxlaegsuhdqbyikut.supabase.co/storage/v1/object/public/kitchen-photos/seed/portraits/';
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
       'Champurrado and tamales, together, because that is how they are eaten and separating them never made sense to me. Cold mornings only. When it warms up I stop.'),
      ('Marisa V.','Long Beach','90802',33.7701,-118.1937,'455 E Ocean Blvd','(562) 555-0201','marisav',
       'Tres leches, but with strawberries because my daughter refuses it any other way. She is nineteen and still refuses. I have stopped arguing.'),
      ('Trần H.','Westminster','92683',33.7592,-117.994,'9200 Bolsa Ave','(714) 555-0202','tranh',
       'Bánh mì on Bolsa, which means the competition is fierce and everyone here is a critic. My bread comes from a bakery two doors down. That is not cheating, that is Little Saigon.'),
      ('Kenji S.','Torrance','90501',33.8358,-118.3406,'1247 Sartori Ave','(310) 555-0203','kenji',
       'Katsu sando, and I brine the pork for a day. My father ran a lunch counter in Gardena for thirty years and told me the brine was unnecessary. He was wrong about that one thing.'),
      ('Rocío A.','Santa Ana','92701',33.7455,-117.8677,'401 W 4th St','(714) 555-0204','rocio',
       'Birria de chivo, goat not beef, the way it is in Jalisco. People order it expecting the beef version and then they come back.'),
      ('Nadia F.','Anaheim','92805',33.8353,-117.9145,'500 S Anaheim Blvd','(714) 555-0205','nadia',
       'Manaeesh with za''atar, baked flat and eaten hot. My mother would not recognise the oven but she would recognise the bread.'),
      ('Sam O.','Huntington Beach','92648',33.6595,-118.0,'300 Pacific Coast Hwy','(714) 555-0206','samo',
       'Beach pizza is a real category and I will defend it. Thin, foldable, eaten standing up with sand in your shoes.'),
      ('Lorena P.','Costa Mesa','92627',33.6412,-117.9187,'1810 Newport Blvd','(949) 555-0207','lorena',
       'Alfajores, dulce de leche, rolled in coconut. My abuela sent them from Mendoza every winter until the customs forms got too complicated.'),
      ('Devi R.','Irvine','92614',33.6846,-117.8265,'4255 Campus Dr','(949) 555-0208','devi',
       'Hakka noodles, Indian-Chinese, which confuses people until they eat them. It is its own cuisine and it is older than most of the arguments about it.'),
      ('Bao N.','Garden Grove','92840',33.7739,-117.9414,'12866 Main St','(714) 555-0209','bao',
       'Bún bò Huế, properly spicy. If you ask me to make it mild I will, and I will be quietly disappointed, and you will taste that.'),
      ('Elena M.','San Clemente','92672',33.427,-117.612,'111 Avenida Del Mar','(949) 555-0210','elena',
       'Flan de coco. Learned it in Havana, make it in a beach town, and it has never once tasted the same. Weather, I think.'),
      ('Ahmad B.','Fullerton','92832',33.8704,-117.9243,'125 E Commonwealth Ave','(714) 555-0211','ahmad',
       'Sangak, stone-baked, the length of your forearm. The stones came from my uncle''s oven in Shiraz in a suitcase, which was a whole thing at the airport.'),
      ('Kai L.','San Diego','92101',32.7157,-117.1611,'501 Fifth Ave','(619) 555-0212','kail',
       'Fish tacos with the batter my dad used at his stand in Ensenada. Beer in the batter, cabbage not lettuce, crema not sour cream. These are not preferences.'),
      ('Gloria E.','Chula Vista','91910',32.6401,-117.0842,'276 Fourth Ave','(619) 555-0213','gloria',
       'Tamales de elote, sweet corn, no meat. My grandmother sold them at the border crossing for forty years. I sell them from my porch and it is a much shorter walk.'),
      ('Yusuf D.','El Cajon','92020',32.7948,-116.9625,'250 E Main St','(619) 555-0214','yusuf',
       'Sambusa, Somali, with the green chili sauce that people always ask about and I always make too little of.'),
      ('Priscila T.','Oceanside','92054',33.1959,-117.3795,'300 N Coast Hwy','(760) 555-0215','priscila',
       'Pan de polvo, the wedding cookies, cinnamon and anise. I make eight hundred at Christmas and I am tired just typing that.'),
      ('Ravi K.','Escondido','92025',33.1192,-117.0864,'201 E Grand Ave','(760) 555-0216','ravi',
       'Biryani, Hyderabadi, layered and sealed with dough. It takes the afternoon and cannot be hurried and I have made peace with that.'),
      ('Camila S.','Carlsbad','92008',33.1581,-117.3506,'2965 Roosevelt St','(760) 555-0217','camila',
       'Pastel de tres leches with a burnt meringue top, which is not traditional and I do not care.'),
      ('Mateo J.','Riverside','92501',33.9806,-117.3755,'3737 Main St','(951) 555-0218','mateo',
       'Carne asada, mesquite, marinated in citrus overnight. My tío taught me that the marinade matters less than the fire. He was right and it took me ten years.'),
      ('Aisha M.','Moreno Valley','92553',33.9425,-117.2297,'14075 Frederick St','(951) 555-0219','aisha',
       'Injera takes three days to ferment and there is no shortening it. The doro wat is my mother''s and it is spicier than you think.'),
      ('Hugo C.','Corona','92879',33.8753,-117.5664,'815 W 6th St','(951) 555-0220','hugo',
       'Wood-fired, in the backyard, on weekends only. The oven took a year to build and my wife still calls it ''the project''.'),
      ('Simone W.','Temecula','92590',33.4936,-117.1484,'28464 Old Town Front St','(951) 555-0221','simone',
       'Lemon olive-oil cake with fruit from the tree out back. When the tree is done, I am done, and people find that very frustrating.'),
      ('Ivan P.','Palm Springs','92262',33.8303,-116.5453,'155 S Palm Canyon Dr','(760) 555-0222','ivan',
       'Pelmeni, hand-pinched, frozen in trays. It is 110 degrees outside and I am making Siberian dumplings. I know.'),
      ('Lucia F.','Indio','92201',33.7206,-116.2156,'45500 Oasis St','(760) 555-0223','luciaf',
       'Dátiles con queso and date shakes, because I live where the dates grow and it would be strange not to.'),
      ('Omar S.','San Bernardino','92401',34.1083,-117.2898,'201 N E St','(909) 555-0224','omar',
       'Kubz and mezze, Iraqi, cooked for whoever turns up. My mother fed a street in Baghdad. I feed a cul-de-sac.'),
      ('Bianca R.','Fontana','92335',34.0922,-117.435,'8353 Sierra Ave','(909) 555-0225','bianca',
       'Empanadas dulces and alfajores. I bake at night because the house is quiet and the oven does not heat the whole place in August.'),
      ('Terrence H.','Ontario','91762',34.0633,-117.6509,'215 N Euclid Ave','(909) 555-0226','terrence',
       'Hot links and brisket sandwiches, smoked twelve hours. My grandfather had a pit in Bakersfield. Same rub, worse patience.'),
      ('Ji-woo C.','Rancho Cucamonga','91730',34.1064,-117.5931,'8916 Foothill Blvd','(909) 555-0227','jiwoo',
       'Japchae and kimbap for lunchboxes. I started making them for my own kids and then their friends'' parents started asking.'),
      ('Fernanda L.','Victorville','92392',34.5362,-117.2928,'14343 Civic Dr','(760) 555-0228','fernanda',
       'Barbacoa on Sundays, wrapped in maguey when I can get it, banana leaf when I cannot. The desert makes everything harder and nothing impossible.'),
      ('Noor H.','Chino','91710',34.0122,-117.6889,'13220 Central Ave','(909) 555-0229','noor',
       'Kunafa, cheese not cream, and I will not be taking questions on that.'),
      ('Marisol Q.','Oxnard','93030',34.1975,-119.1771,'300 W 5th St','(805) 555-0230','marisolq',
       'Mariscos — shrimp tacos, ceviche tostadas. My father fished out of Channel Islands Harbor and I still buy from the boats he used to drink with.'),
      ('David A.','Thousand Oaks','91360',34.1706,-118.8376,'2200 E Thousand Oaks Blvd','(805) 555-0231','davida',
       'Challah and babka. I am the only Jewish baker for some distance and Fridays are chaos in a way I have come to enjoy.'),
      ('Rosalinda G.','Ventura','93001',34.2746,-119.229,'451 E Main St','(805) 555-0232','rosalinda',
       'Buñuelos and champurrado in winter, nothing in summer. People ask why. Because nobody wants fried dough in August, that is why.'),
      ('Nina B.','Santa Barbara','93101',34.4208,-119.6982,'1129 State St','(805) 555-0233','nina',
       'Sourdough pizza, twenty-four hour cold ferment, and toppings from the Saturday market. It changes every week and that is the point.'),
      ('Tomás E.','Santa Maria','93454',34.953,-120.4357,'120 E Main St','(805) 555-0234','tomas',
       'Santa Maria tri-tip, red oak, pinquito beans. This is a regional style with rules and I follow all of them.'),
      ('Kalani M.','Carson','90745',33.8317,-118.282,'701 E Carson St','(310) 555-0235','kalani',
       'Pancit and lumpia for parties. Filipino food is party food. If you are ordering for two I will still send enough for six.'),
      ('Ana Sofía D.','Inglewood','90301',33.9617,-118.3531,'330 E Queen St','(310) 555-0236','anasofia',
       'Pastelitos and quesitos, Puerto Rican, guava and cheese. There are not many of us out here and people find me anyway.'),
      ('Hyun J.','Koreatown','90005',34.058,-118.308,'3300 W 6th St','(213) 555-0237','hyunj',
       'Jjajangmyeon, black bean noodles, made the way the Chinese-Korean shops in Seoul do it. Nobody makes this at home. That is exactly why I do.'),
      ('Beatriz N.','Boyle Heights','90033',34.0339,-118.21,'2000 E Cesar E Chavez Ave','(323) 555-0238','beatriz',
       'Tacos de guisado, seven stews, from a pot my mother brought from Puebla in 1981. It is too heavy and I will never replace it.'),
      ('Efrain V.','Compton','90220',33.8958,-118.2201,'205 S Willowbrook Ave','(310) 555-0239','efrain',
       'Pozole rojo on cold weekends. I make thirty gallons and it is gone by Sunday afternoon every single time.'),
      ('Malia K.','Redondo Beach','90277',33.8492,-118.3884,'1611 S Catalina Ave','(310) 555-0240','malia',
       'Haupia and butter mochi. Hawaiian desserts do not travel well so I make them here, badly at first, better now.'),
      ('Ines R.','Pomona','91766',34.0553,-117.752,'250 W Second St','(909) 555-0241','ines',
       'Conchas and cuernitos before dawn. I have a day job. This is the other one, and it is the one I would keep.'),
      ('Zaid A.','Anaheim','92806',33.8353,-117.8845,'1440 S State College Blvd','(714) 555-0242','zaid',
       'Falafel, fried to order, never sitting. If you get soft falafel from me something has gone badly wrong and you should tell me.'),
      ('Paloma S.','Whittier','90605',33.9558,-118.027,'13421 Whittier Blvd','(562) 555-0243','paloma',
       'Marranitos, the little pig cookies, molasses and ginger. My kids call them piggies and refuse the real name.'),
      ('Tenzin D.','Monterey Park','91755',34.05,-118.1228,'2020 S Atlantic Blvd','(626) 555-0244','tenzin',
       'Momos and thukpa. There are four Tibetan families in this valley that I know of and we all cook for each other''s weddings.'),
      ('Consuelo B.','Bell Gardens','90201',33.9653,-118.1514,'7100 Garfield Ave','(562) 555-0245','consuelo',
       'Menudo on Sunday mornings, which is the only correct time for menudo, and I will not be making it on a Tuesday.'),
      ('Andrés M.','Downey','90241',33.9401,-118.1332,'8320 Firestone Blvd','(562) 555-0246','andresm',
       'Cemitas poblanas — sesame roll, papalo, quesillo. The papalo is the whole thing and it is hard to get and I have three plants.'),
      ('Sunisa P.','Hollywood','90028',34.1016,-118.3267,'6300 Hollywood Blvd','(323) 555-0247','sunisa',
       'Pad see ew and boat noodles. I worked the line on Hollywood Blvd for nine years. Now the line is my kitchen and it is much shorter.'),
      ('Georgi V.','Glendale','91206',34.145,-118.235,'1200 E Broadway','(818) 555-0248','georgi',
       'Lavash and khachapuri. Georgian, not Armenian, which I explain roughly once a day and do not mind.'),
      ('Rosa Elena T.','North Hollywood','91601',34.172,-118.378,'5200 Lankershim Blvd','(818) 555-0249','rosaelena',
       'Pastel de elote and arroz con leche. Comfort food, no ambition, entirely the point.'),
      ('Wei C.','Arcadia','91007',34.13,-118.029,'1000 S Baldwin Ave','(626) 555-0250','weic',
       'Beef noodle soup, Taiwanese, broth going since yesterday. Twenty years in Rowland Heights before that. The recipe has not changed.'),
      ('Farah Q.','Cerritos','90703',33.8583,-118.0648,'11800 South St','(562) 555-0251','farah',
       'Biryani and haleem in Ramadan, when I do not sleep much and cook more than the rest of the year combined.'),
      ('Julio E.','San Pedro','90731',33.7361,-118.2922,'400 W 6th St','(310) 555-0252','julio',
       'Ceviche and aguachile from what came off the boats this morning. If the boats had a bad day, so do I, and I say so.'),
      ('Amara O.','Altadena','91001',34.1897,-118.131,'2300 Lake Ave','(626) 555-0253','amara',
       'Nigerian meat pies and puff-puff. My mother sold them outside a church in Lagos. Different church, same recipe.'),
      ('Lidia H.','Bell','90201',33.9775,-118.187,'6330 Pine Ave','(323) 555-0246','lidia',
       'Churros rellenos, filled with cajeta or chocolate. Plain churros are fine. Filled ones are better and I am willing to argue.'),
      ('Nasrin K.','Irvine','92612',33.654,-117.8265,'4200 Barranca Pkwy','(949) 555-0254','nasrin',
       'Persian rice with tahdig, and the tahdig is the reason anyone orders. Getting it out of the pot in one piece is a party trick I have failed at publicly.')
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
