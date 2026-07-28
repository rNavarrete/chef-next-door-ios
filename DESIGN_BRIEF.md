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

| Screen | Job | Notes |
|---|---|---|
| **Availability toggle** | Open / close the kitchen | **The most important control in the entire product.** Must be reachable in ~1 second, one-handed, ideally without opening the app — home screen widget, Control Center, Lock Screen. Design this first, not last. |
| **Menu builder** | Define what they make | Entered once, reused indefinitely. The structured-price input is the highest-leverage input in the app — fast, not bureaucratic. Photo capture inline. Per-item "sold out" toggle lives here too. |
| **Claim inbox** | Respond to buyers | One-tap reply. |
| **Permit & trust** | Get verified | Upload, status, expiry reminder. Should feel like a credential earned, not a form endured. |

## 7. The Cook card — the centerpiece

This component appears on the map, in the feed, in search, and on profiles. Get it right and most of the app is designed.

Rough hierarchy (not a layout spec):

```
┌────────────────────────────┐
│                            │
│      [ food photo ]        │   hero — fills the card
│                            │
│  ● COOKING · SINCE 9:40 AM │   ← accent color, loudest element
├────────────────────────────┤
│  María G.       ★4.9 (127) │   cook, large, with face
│  Tamales · Champurrado     │   what they're making today
│  $36/dozen  ·  $3 each     │   ← unambiguous, always
│                            │
│  ✓ Permitted · Covina      │   badge + neighborhood
│  1.2 mi                    │   ← proximity, quiet
└────────────────────────────┘
```

The closed state is the same card, desaturated, with the accent bar replaced by something dormant — "Light's off · usually Saturdays." Closed cooks should still be browsable (that's how you find someone to follow) but never compete visually with open ones. The follow action on a closed card reads **"Turn her light on for me."**

## 7a. The decay ladder — how "open" is allowed to age

*Designed and resolved. This is the answer to the hardest problem in the brief.*

The light metaphor makes "open" unmissable — which means it can also lie unmissably. Availability is therefore not binary over time. It decays, and past six hours the interface stops leading with the clock and starts leading with the question.

| Age since last confirmation | Dot | Card | Label | Primary action |
|---|---|---|---|---|
| 0–4 h · **lit** | filled, pulsing | full glow | `Cooking · since 9:40 am` | Claim |
| 4–6 h · **dimming** | desaturated, no pulse | glow drops sharply | `Cooking · since 9:40 am` + `Last said something at 9:40 am` | Claim |
| 6 h+ · **unconfirmed** | **hollow ring**, no fill | no glow, neutral 1px border | `Lit at 9:40 am · unconfirmed since` (neutral gray, **not amber**) | **Ask if he's still cooking** (blue) |
| Auto-off 8 pm | dim filled | dark treatment | `Light went out at 8:00 pm` | Turn his light on for me |

**Three rules, so it can't erode:**

1. **One time format everywhere: absolute clock time.** Elapsed durations — "15 min ago", "6h ago" — never appear anywhere in the interface. They're either ambiguous (is that distance? time left?) or accusatory.
2. **Actions that assert current service reset the clock and relight the dot** — an item flipped sold out, a note edited, a claim from *this session* answered, an explicit "still cooking." Diligence is rewarded automatically; there is never a "still open?" chore. **Deliberately excluded:** clearing a claim from a previous session, or editing prices, photos, and permit docs. Bookkeeping is not cooking — counting it would relight a kitchen that went cold at noon, which is the exact failure this ladder exists to prevent.
3. **Unconfirmed cooks rank below confirmed ones** and are never the first row of the feed.

**Never assert the cook is closed.** State what's known, and give one tap that resolves it:

> "Beto turned his light on this morning and hasn't touched the app since. That usually means he's busy — sometimes it means he's done. Ask before you drive."

Claiming stays possible, demoted to a secondary `Claim anyway`. The cook-side nudge (~8h, answerable from the Lock Screen) is honest about why it matters: *"Still cooking, Beto? Your light has been on since 9:40. Two people are looking at it right now."*

Compare with COOK Connect's shipped card (documented in `DESIGN_RESEARCH.md` §2): theirs leads with cook and rating, ours leads with **live availability**. That difference is the entire product thesis expressed in one component.

## 8. Hard constraints

Non-negotiable. Several are safety or legal requirements, not preferences.

- **Never show a cook's exact address** before the cook has confirmed that specific buyer's claim. Map pins show a coarse, non-invertible approximation. Design the neighborhood-level display so it feels intentional and sufficient, not like missing data.
- **The claim → address path is rate-limited and logged.** Buyers are phone-verified, cooks confirm before anything is released, and there's a daily cap per buyer. If a limit is hit, the copy should read as protecting the cook — not as accusing the buyer.
- **Allergens at the dish level**, as visible chips — not a footnote, not a tooltip (no hover on mobile), not inside a collapsed accordion. This is the one screen where an accessibility failure is a safety failure.
- **Permit number, issuing agency name, and "Made in a Home Kitchen"** must render on MEHKO listings. Legally required. Design them to look like a credential, not a disclaimer.
- **A platform insurance disclosure** must be findable. Needs a home in the IA.
- **The word "catering" is prohibited** on MEHKO listings. Never use it in UI copy, placeholders, or example content.
- **Dynamic Type and VoiceOver** throughout. Our buyers skew bilingual and multi-generational; abuelas use this app.

## 9. Don't

- Don't build a language toggle. Show the synonym expansion instead (`también: tamales · tamalito · pork tamale`) so buyers see *why* a result matched.
- Don't build a scheduling UI. Cooks don't plan; they cook and then they're done.
- Don't let open and closed cooks look similar.
- Don't show availability without showing how fresh it is.
- **Don't use elapsed durations anywhere.** Absolute clock times only (§7a).
- Don't put amber on anything tappable. Amber marks heat, blue marks affordance — with exactly one exception, the cook's own burner dial, which *is* the heat. Any other amber control is a bug.
- Don't show a price without a unit.
- Don't centralize trust on one "verified" screen — it belongs at every decision point.
- Don't invent urgency the data doesn't support.
- Don't push to a full page when a pin is tapped.
- Don't art-direct the food photography toward stock polish.
- Don't make closing feel like a penalty. A cook who closes promptly is doing the single most valuable thing in the system; the UI should thank them, not treat it as churn.

## 10. Resolved by the design handoff

- ~~Freshness without reading as a warning~~ → **the decay ladder** (§7a). Absolute clock times, activity resets the clock, and past 6h the primary action changes from claim to ask.
- ~~Claim semantics~~ → **warm intro, holds nothing**, said plainly on both sides: "Doesn't hold anything — it opens a text with her" / "Nothing is reserved until you say sí."
- ~~Follow affordance~~ → **"Turn her light on for me."**
- ~~Cook's empty state~~ → "You sold out by six. Thanks for turning it off." Closing is thanked, never penalized.
- ~~Closed cooks on the map~~ → **off by default**; browsable in feed and search under "14 kitchens dark today · Look anyway."
- ~~Dark Mode~~ → a parallel warm-black token set, not an inversion; amber unchanged, blue lifted for contrast.

## 11. Still open

- Whether Discover (map) or Open Now (feed) is the default landing tab. I lean feed; the argument for map is stronger in a dense launch cluster.
- Onboarding: ask for location first, or show a populated map immediately and ask later.
- Whether cottage-food (baked goods) and MEHKO (cooked meals) listings are visually differentiated at all, or only in their disclosure text.
- What the IFSI disclosure screen's "CDPH registration · status" field reads on launch day, given registration is a fast follow (`PRD.md` §11.7). Blocking for that screen.
