# Getting to liquidity

How Chef Next Door gets its first real cooks and its first real buyers, and why
the usual chicken-and-egg framing understates the position we are actually in.

---

## The thing we already have that most marketplaces do not

**A named list of 392 legally permitted home cooks in Los Angeles County, already
in our own database.**

`permit_registry` is synced nightly by `fetch_permit_registry()`. It carries
`name`, `city`, `postal_code` and `start_date` for every MEHKO operator the
county has permitted. Two agencies: LA County Environmental Health (390) and
Pasadena Public Health (2).

That list is our Craigslist.

Airbnb's single most-cited growth move was not a growth hack in the modern sense
— it was noticing that their supply already existed somewhere else and going to
get it. They emailed people posting rentals on Craigslist and offered them a
better place to be. Fourteen of the seventeen marketplaces in Lenny Rachitsky's
survey attacked supply before demand, for the same reason: supply is harder, and
supply is findable.

Ours is more findable than Airbnb's was. These are not anonymous listings. They
are people who:

- **Paid several hundred dollars a year for a permit.** Nobody does that on a
  whim. Every one of them has already decided to sell food.
- **Are legally allowed to sell**, which is exactly the thing our badge checks.
- **Have no distribution.** There is no MEHKO directory a normal person uses.
  Their customers come from Instagram, WhatsApp and their own street.

### And the market is inflecting right now

Permits by start year, from our own table:

| Year | New permits |
|---|---|
| 2024 | 18 |
| 2025 | 200 |
| 2026 (partial) | 174 |

Eighteen to two hundred in a year. 2026 is on pace to beat it. Whatever the
cause — county outreach, cost of living, restaurant closures — the supply side
of this market is being created faster than anyone is serving it. That is a
timing argument, and timing arguments expire.

**Use the list carefully.** It is public record, but it is public record about
individuals cooking in their homes, many of them immigrants. Contact is fine.
Bulk-scraping it into a cold email blast is how you become the reason the county
stops publishing it. Never publish the list, never expose it in the client, and
approach in person or by name — not as a mail merge.

---

## The real unlock: be worth using with zero buyers

The chicken-and-egg problem dissolves if the first side gets value before the
second side exists. OpenTable sold restaurants a reservation book that was
useful with no diners on it. Chris Dixon calls this **single-player mode**.

**Our single-player mode is the storefront.**

A permitted home cook in LA today sells through a WhatsApp broadcast list and an
Instagram grid. That means: menus retyped every morning, "is this still
available?" forty times a day, orders lost in a thread, no way for a new
customer to see what is cooking without a DM. It is genuinely bad, and it is
what every one of these 392 people is doing right now.

Chef Next Door already fixes most of that — a menu, prices with honest units,
a light you turn on when you start cooking, threads that are per-buyer instead
of a broadcast list, push when someone messages. **None of that requires us to
bring them a single customer.**

So the pitch is not "join our marketplace". The pitch is:

> Stop retyping your menu into WhatsApp every morning. Turn your light on when
> you start cooking and your regulars get told. Keep every dollar — we take
> nothing and never touch your money.

Then they bring their existing customers with them. That is Airbnb's Craigslist
move inverted: rather than us importing demand, supply imports its own.

### The one thing missing to make that work

**A cook needs a public link they can paste into an Instagram bio or a WhatsApp
status, and it has to work for someone who does not have the app.**

We have `KitchenDeepLink`, which is an app-to-app deep link. Sent to a customer
without the app it does nothing useful. A cook cannot bring their audience
across a link that only works for people who have already crossed.

This is the highest-leverage thing left to build: a public, shareable kitchen
page — dish, price, whether they are cooking right now, and one button that
opens the app or the App Store. It converts every cook into a distribution
channel for us at the same moment it makes the product worth having for them.

---

## Where to launch

Not "Southern California". Density decides everything in a hyperlocal
marketplace: supply spread thin is indistinguishable from a broken app, which is
exactly the failure our own testers reported when they were on the 5-mile radius
build.

Permitted cooks by city:

| City | Permits |
|---|---|
| Los Angeles | 122 |
| Palmdale | 15 |
| Compton / Norwalk / Rowland Heights / Whittier | 7 each |
| Arcadia / San Gabriel / Alhambra | 6, 6, 5 |

"Los Angeles" is the biggest number and the wrong answer — it is 500 square
miles, so 122 cooks is sparse everywhere. Palmdale is dense but isolated.

**Launch the San Gabriel Valley.** Rowland Heights, Arcadia, San Gabriel,
Alhambra and their neighbours put roughly two dozen permitted cooks inside a
radius people actually drive, it is already the app's `launchCluster`, and it
has two overlapping food cultures — Latino and Chinese — with established
habits of buying food from neighbours. Get that one valley genuinely liquid
before touching anything else.

Define the threshold before starting, so "are we ready to expand" is a number
rather than a feeling. A reasonable first bar: **15 real cooks lighting up in a
week, and 30 buyer-initiated threads a week**, sustained for a month.

---

## Supply plays, in the order I would run them

1. **Door-knock the valley.** Twenty-five addresses. Not email — turn up, buy
   something, cook the app with them on their phone. Airbnb's founders spent
   about thirty days doing exactly this and have said it was the difference
   between working and not. It does not scale, and that is the point: it is a
   month of work that produces the first fifteen cooks and everything you learn
   from watching them fail to use the app.
2. **Do the work for them.** Shef's playbook: menus, pricing, bios, and above
   all **photography**. Airbnb sent photographers to hosts and it moved bookings
   more than anything else they tried. We have a hard requirement here that most
   marketplaces do not — the feed *hides* kitchens with no dish photo — so a
   cook with no photos is not merely unattractive, they are invisible. Show up
   with a phone and shoot three dishes.
3. **Lead with the take rate.** Shef and every delivery app take a cut. We take
   nothing and never hold their money. Against a cook doing $800 a month on
   WhatsApp, "we take zero" is not a feature, it is the entire conversation.
4. **Recruit in Spanish.** The dish names already resolve both ways and the app
   is bilingual. A large share of LA MEHKO operators are Spanish-first. Most
   competitors are not having this conversation in Spanish at all.
5. **Go where they already gather.** Not generic ads — the county's own MEHKO
   permit classes, the SGV neighbourhood Facebook groups, WhatsApp community
   groups, church and school fundraisers. Hyperlocal supply lives in those
   rooms, and they are rooms you can physically walk into.
6. **Ride the permit wave.** 174 new permits already this year. Every one is a
   person who just decided to start selling and has nothing to sell through. If
   we can be the thing handed to them the week their permit clears — via the
   county class, via the inspector, via a leaflet — we get them before anyone
   else does.

---

## Demand plays, once ~15 cooks are live

Do not run these first. Demand arriving before supply is worse than no demand:
they see an empty map and never come back.

1. **Let supply bring it.** The shareable kitchen page above. A cook with 400
   Instagram followers is a better acquisition channel than any ad we can buy,
   and they have every reason to use it.
2. **"Cooking right now" is the marketing.** Our premise is a live one. It is
   made for exactly the local Facebook groups and Nextdoor posts where "who has
   tamales today?" gets asked constantly. A daily "here's who is cooking in the
   SGV tonight" post costs nothing.
3. **One neighbourhood at a time on the demand side too.** Flyers on the
   specific streets where the cooks are. The buyer's whole decision is "can I
   walk there", so anything wider is wasted.
4. **Make the empty state recruit.** When nobody is cooking near a buyer, the
   app currently offers to search elsewhere. It should also offer *"know someone
   who cooks? tell them about us"* — the moment of disappointment is the moment
   someone thinks of their aunt.
5. **Word of mouth is the actual channel.** Over 50% of Airbnb's early guest
   growth and over 70% of host growth was word of mouth. Food is more
   word-of-mouth-native than lodging. The job is to make the product worth
   talking about and get out of the way, not to buy installs.

---

## What I would not do

- **Do not buy install ads yet.** Paid demand against thin supply burns money to
  create bad first impressions.
- **Do not expand geographically to look bigger.** Ninety-two seeded kitchens
  spread from San Diego to Santa Maria is what made the map look broken to real
  testers. Sparse is worse than small.
- **Do not add a take rate to look like a business.** Zero commission is
  currently our sharpest recruiting weapon and the reason a cook would move off
  WhatsApp. Monetise later, from somewhere that is not the cook's margin.
- **Do not keep the seed data past launch.** The moment a real cook can be
  compared against a fake one, the fake ones are a liability. Teardown is
  `cron.unschedule('seed-keep-lit')` plus the seed accounts.

---

## Sources

- [28 ways to grow marketplace supply — Lenny Rachitsky / Andrew Chen](https://andrewchen.com/grow-marketplace-supply/)
- [How to kickstart and scale a marketplace: supply vs demand](https://www.lennysnewsletter.com/p/how-to-kickstart-and-scale-a-marketplace-9ee)
- [How to kickstart and scale a marketplace: growing initial demand](https://www.lennysnewsletter.com/p/how-to-kickstart-and-scale-a-marketplace-2e5)
- [Vampire attacks: how marketplaces overcome chicken-and-egg](https://www.gardinercolin.com/p/vampire-attacks-marketplaces)
- [How Uber, Airbnb and OpenTable cracked the chicken-and-egg problem](https://xartup.substack.com/p/how-uber-airbnb-and-opentable-cracked)
- [Shef: doing things that don't scale](https://www.alexanderjarvis.com/shef-doing-things-that-dont-scale/)
- [This food-delivery startup is helping home cooks become entrepreneurs — Inc.](https://www.inc.com/rebecca-deczynski/shef-food-delivery-service-home-cooks.html)
- [On Facebook Marketplace, home-cooked food can be a viral hit — Boston Globe](https://www.bostonglobe.com/2026/07/21/business/facebook-marketplace-food-cooking-influencers/)
- [How to use Facebook groups to sell local food](https://findhomegrown.com/blog/how-to-sell-food-on-facebook-groups)
