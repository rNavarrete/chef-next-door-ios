# Lit Kitchen — Design Brief

*For handoff to design. High-level direction, not specs.*

**Read first:** [`PRD.md`](PRD.md) for scope, [`DESIGN_RESEARCH.md`](DESIGN_RESEARCH.md) for competitive patterns, [`RESEARCH.md`](RESEARCH.md) for the market evidence behind every claim here.

---

## 1. The product, in one paragraph

Lit Kitchen is a native iOS app for finding home-cooked food from permitted cooks in your neighborhood — tamales, birria, pupusas, sourdough — and knowing who's actually cooking right now. Cooks post a storefront once, then flip it **on when they're serving and off when they're done.** Buyers browse a map and an open-now feed, claim what they want, and are handed off to the cook's own channel (text, WhatsApp, Instagram) to arrange it. We don't take payment. We make supply visible.

## 2. The design thesis

> **Who's cooking right now.**

This is the one idea the whole interface should express. Not a catalog, not a schedule — a live picture of which kitchens in your neighborhood are open at this moment.

The design consequence: **availability is the highest-priority information on every surface.** Not price, not rating, not distance — whether this person is cooking *today*. A closed cook is nearly invisible; an open cook is unmistakable. That distinction should be legible from across the room, at a glance, in a thumbnail.

Two things follow that are easy to get wrong:

**Freshness is part of availability.** "Open" is a claim the cook made at some point in the past, and its trustworthiness decays. A kitchen lit at 9:40 this morning and one lit twenty minutes ago are not the same offer, and the interface must not present them as though they are — without turning freshness into an accusation against a cook who is simply busy. Solved by the decay ladder in §7a.

**Distance matters again.** An earlier version of this brief argued time was the primary axis and distance was secondary. That was downstream of a scheduled-batch model we've since cut. With availability as a live binary, the buyer's question becomes "who's open *and* close," so proximity returns as a real sorting dimension — subordinate to open/closed, but ahead of everything else.

## 3. Who we're designing for

**The buyer.** Lives in the San Gabriel Valley. Grew up on this food or moved here and fell for it. Currently finds cooks through word of mouth, a friend's Instagram story, a flyer at the carniceria. Isn't looking for "a restaurant experience" — is looking for *the good tamales, the ones that sell out.* Often bilingual, frequently switching languages mid-sentence without thinking about it.

**The cook.** Makes 20–80 units out of a permitted home kitchen, on their own rhythm — some weekly, some whenever they feel like cooking. Already semi-organized: has an Instagram, a rotating menu, a group chat of regulars. Is proud of this food; it's usually family cooking. Runs the business from a phone, between batches, often with flour on their hands. Frequently a woman working solo out of her own home, which makes address privacy a safety matter, not a preference.

**Design implication worth stating loudly:** this person will not sit down and plan a schedule. They decide to cook, they cook, they sell, they're done. The single control they touch most is *"I'm open" / "I'm done"* — and it has to be flippable in about a second, one-handed, without opening the app if possible. If that interaction has any friction at all, availability goes stale and the whole product breaks.

**Register check.** Two failure modes to avoid, both easy to fall into:

- **Too DoorDash** — commoditized, orange, urgent, transactional. Wrong, because we're not a transaction, and it strips the food of the person who made it.
- **Too artisanal** — muted pastels, precious serif, "small-batch" copywriting. Also wrong, and worse: it's the aesthetic of a different, whiter, wealthier food culture, and it would read as condescending to the actual cooks and buyers here.

The real register is **warm, proud, and legible.** Closer to a hand-lettered farmers-market sign or a well-shot family recipe than to either a delivery app or a Brooklyn bakery. Note that the sellers in our research are *already* designing for attention — emoji-loaded titles, bright thumbnails, bold claims. Don't sand that off. Give it structure.

## 4. Principles

1. **Photo first, always.** Yelp's own redesign deliberately mirrored Instagram to create "food lust," and it worked. The food photo is the hero of every card, every detail view. Chrome recedes.
2. **Open/closed is the loudest signal.** More prominent than price, rating, or distance. A buyer scanning the feed should never have to read to find out who's serving.
3. **Show freshness with availability, in absolute clock time.** `Cooking · since 9:40 am` — never "15 min ago" or "8h ago." See §7a for the full decay ladder.
4. **Price is never ambiguous.** Always amount + unit + minimum: "$3 each," "$36/dozen ($3 ea)," "$110/week." Never a bare number. This is a direct inversion of the exact failure that makes the existing marketplaces unusable.
5. **The cook is a person.** Face, name, neighborhood, a sentence in their own words. Trust comes from personhood first, permit second — but both are visible, and both belong on the card, not buried in a profile.
6. **Bilingual by construction.** Spanish and English coexist in the same view, in the same list, sometimes in the same string. There is no language toggle — that solves a problem this market doesn't have.
7. **Honest scarcity only.** "Sold out" appears when the cook says so, never synthesized. We're a platform under active health-regulator attention; manufactured urgency isn't just a dark pattern here, it's a liability.

## 5. Visual direction

Opinionated starting point — the designer should push on this, not treat it as locked.

**Mood:** Warm, confident, uncluttered. Food and faces supply all the color; the interface supplies calm and structure. It should feel like a well-designed neighborhood bulletin board, not a storefront.

**Color:** A warm off-white/cream ground rather than clinical white. Deep near-black ink for text — high contrast, not gray-on-gray. **One** saturated accent reserved almost exclusively for *"this kitchen is open right now"* — nothing else earns it. If the accent means "open," it stays meaningful, and the open/closed distinction does its work through color before anyone reads a word. Closed cooks go quiet: desaturated, lower contrast, present but clearly dormant. Explicitly avoid the red/orange delivery-app palette; it reads as urgency-for-its-own-sake and puts us in the wrong category.

**Type:** Large, confident, high-legibility. Must handle Spanish diacritics and ~30% longer strings gracefully — test layouts with `Vaporera para tamales con división`, not with "Tacos." Dish names want presence. Prefer a type system with real weight range over decorative display faces.

**Imagery:** Cook-submitted photos, unretouched, imperfect. Steam, foil trays, a hand holding a plate. Do **not** art-direct toward stock-food-photography polish — our research found stock-looking photos are a *distrust* signal in this market. Real beats pretty. Design the card so a mediocre phone photo still looks good in it (consistent crop, generous corner radius, subtle overlay for legibility).

**Motion:** Restrained. Two places to spend it: the moment a claim is confirmed and the Live Activity appears, and the cook-side moment of flipping open — that toggle should feel *good*, because we need them to use it every single time they cook.

## 6. Screens

**Buyer**

| Screen | Job | Notes |
|---|---|---|
| **Discover (map)** | "Who's cooking near me?" | Fuzzed pins, clustered at zoom-out. Open cooks in accent color, closed dimmed or filtered. Tapping a pin surfaces a card *in place* — never navigate away and lose map context. |
| **Open Now (feed)** | "Who's serving today?" | Cooks currently open, nearest first, freshness visible. The default tab. |
| **Search** | Known-item finding | Bilingual, typo-tolerant, synonym-aware. Zero-result state must offer something — nearest open cooks, or "notify me when X opens" — never a dead end. |
| **Cook detail** | Decide and claim | Photos, menu with structured prices, per-item availability, serving note, allergens, permit badge. Claim CTA persistent. |
| **Cook profile** | Trust and follow | Story, photos, reviews, permit + agency name, follow button. |
| **Claim → handoff** | Get to the cook | Confirmation, exact address revealed *here and only here*, one tap into their channel. |
| **Live Activity** | Keep the claim alive | Lock Screen / Dynamic Island: cook, items, address, tap-to-contact. A persistent handoff card rather than a countdown — there's no fixed window to count down to. |

**Cook**


---
(Excerpt. Full brief lives at DESIGN_BRIEF.md in the repo.)
