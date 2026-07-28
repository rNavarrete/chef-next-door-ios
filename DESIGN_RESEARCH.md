# Design Research: Food Discovery & Home-Kitchen Marketplace UX

*Compiled 2026-07-25 · companion to [`RESEARCH.md`](RESEARCH.md), [`PRD.md`](PRD.md), [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)*

---

## 0. The single most important finding: this exact product already exists

Before any pattern-mining — a direct hit. **COOK Connect** (`cookconnect.com`, run by the nonprofit COOK Alliance) is:

- A MEHKO-specific marketplace — not general home cooking, specifically permitted MEHKOs
- Built around a **"MEHKO Map"** that plots every legal MEHKO nationally — functionally our Discover screen, already shipped
- The direct successor to **Foodnome**, the original MEHKO marketplace, which launched in **Riverside County** — adjacent to our San Gabriel Valley launch geography, not a different market
- Currently **invitation-only**, plus open to graduates of their own "COOK Academy" training program
- A **full transaction platform** — in-app ordering, curbside-pickup notifications when the buyer arrives — the opposite of our discovery-only, handoff-to-DM decision
- Carrying a genuinely strong safety data point worth borrowing for positioning: **tens of thousands of meals sold across permitted MEHKOs, zero verified foodborne illness cases**

This changes the shape of the conversation from "design a food discovery app" to "differentiate from a nonprofit competitor already running the map-plus-marketplace playbook in our region." Four real differentiators fall out of decisions already made in `PRD.md`, the fourth now user-confirmed by directly testing the live product:

1. **We're open, they're invite-only.** Access-gating is their scarcity lever; ours is discovery quality.
2. **We hand off, they process the transaction.** Ours is lower-friction for cooks who already have a working DM/Venmo flow (`RESEARCH.md` Finding 1) and matches how the market actually behaves today.
3. **We cover both MEHKO and cottage food** (`PRD.md` §3); COOK Connect appears MEHKO-only.
4. **We're native iOS; they're web.** User-confirmed by direct testing (2026-07-25) — corroborated independently: `cookconnect.com` loads as a responsive mobile-web page with a bottom tab bar dressed to resemble native navigation (Menus / Sign In / More), a PWA-style shell rather than an installed app. No official native app surfaced anywhere — the App Store hits for "Cook Connect" / "CookConnect" belong to unrelated apps from different developers. See §6 for what this specifically unlocks.

Worth a deliberate look at cookconnect.com's live product (not just the marketing page) before M2, to track whether that changes.

---

## 1. Comparable products surveyed

| Product | Model | Relevance | Key takeaway |
|---|---|---|---|
| **COOK Connect** | MEHKO-only, in-app order + curbside pickup, invite-only | **Direct competitor** | Map-based MEHKO discovery is proven to work; card design is mature (below) |
| **Hotplate** | Per-chef storefront, scheduled preorder "drops," SMS notify | **Rejected as our model** | Their drop mechanic works for *professionalized bakers who chose a drop tool*. Our observed cooks post and unpost instead. We took the storefront and notify patterns, not the scheduling (`PRD.md` §2) |
| **Shef** | General home-cook marketplace, in-app order + delivery, chef vetting | Adjacent (broader, delivery-based) | 4.8★ / 4.8k ratings at real scale — reviews mention chef unavailability with no return date as a recurring complaint |
| **WoodSpoon** | Two-app model (customer + cook), Uber-style accept/decline per order, courier delivery | Adjacent (delivery-based) | Cook-side "accept or pass" flow with an onscreen prep timer is a clean pattern if we ever add order confirmation |
| **CSA / farmers market apps** (LocalLine, Farmigo, CSAware) | Weekly order window, fixed pickup slots, skip-week/vacation hold | Largely superseded | Relevant only to the sourdough/cottage-food segment, which does run on windows. Not a model for the savory MEHKO majority (`PRD.md` §2) |
| **Yelp** | General local search, map/list toggle, feed redesign | Category-defining but not food-specific | Their 2022 redesign deliberately mirrors Instagram's feed to create "food lust" — validates photo-first as the primary hook, not a subjective choice |
| **Airbnb** | Peer-to-peer stranger's-home marketplace | Trust-pattern reference, not food | The best-documented case study of *earning trust in a stranger's home* — directly analogous to buying food from a stranger's kitchen |
| **StockX / Whatnot / drop culture generally** | Scarcity/hype commerce | Cautionary reference | Real engagement lever, but the FTC treats fake urgency as a deceptive dark pattern — matters more for us than most apps, given a health regulator is already watching this exact space (`PRD.md` §8) |

---

## 2. Screen-by-screen recommendations

### Discover (map)

- Map-first with list-toggle is the validated pattern (Yelp, COOK Connect both ship it) — don't debate build order, both surfaces are needed at launch, not sequenced
- Pin clustering at zoom-out is mandatory once pin count grows — Yelp and COOK Connect both cluster; per `IMPLEMENTATION_PLAN.md` §6, cap or cluster past ~500 pins
- Pins render the **fuzzed** `public_point` only (`PRD.md` §7) — no comparable app needs to solve this, since none of them are hiding a home address; this is a genuine design problem specific to us, not something to copy
- Selecting a pin should surface a **card preview**, not a full navigation — COOK Connect and Yelp both keep map context on-screen through a bottom sheet or inline card rather than pushing to a new page

### The Cook card — closest thing to a solved design

COOK Connect's actual production card (read directly from a live screenshot) contains, in order: cook name, star rating with review count (`4.85/5`, `(1087 ratings)`), distance (`15.4 Miles`), cuisine/dish tag (`Argentinian Empanadas`, `Indian - Punjabi`), an **order-by deadline** (`Order by Today 6:00pm`), a **pickup window header** (`FRIDAY 10:00am – 7:00pm`), and a `Pickup` label.

Map this directly onto our `Cook` + `MenuItem` objects — the fields already exist in `IMPLEMENTATION_PLAN.md`'s schema (note their "order by" deadline has no equivalent for us; live availability replaces it):

```
[food photo]
● COOKING · SINCE serving_sessions.opened_at   ← loudest element
Cook display_name          ★ rating (review_count)
category (dish name)
Price.display  (amount + unit + minimum)
✓ permit badge · kitchens.neighborhood
distance from kitchens.public_point
```

Their two time fields — the order-by deadline and the pickup-window header — have **no equivalent for us**, and that absence is the product difference. They schedule; we report live state. Where their card answers "by when must I order," ours answers "is this person cooking right now, and how recently did they say so" (the decay ladder, `DESIGN_BRIEF.md` §7a).

The one field we have that COOK Connect's card doesn't need to show: **structured price** (`Price.display`, `IMPLEMENTATION_PLAN.md` §4) — since our whole thesis is that price ambiguity is what's broken on general marketplaces (`RESEARCH.md` Finding 2), the price must be as prominent as the photo, not buried below the fold like it is in a Yelp-style listing.

### Open-now feed

- **Superseded by the availability model.** The CSA day-grouped-feed precedent assumed scheduled windows; with availability toggles the feed becomes "who's open now, nearest first." The CSA research remains relevant only for the sourdough/cottage-food segment, which is the one group that genuinely runs on windows (`PRD.md` §3)
- Hotplate's SMS-notify-on-open pattern still maps directly to our push requirement (`PRD.md` §6, "Maria is cooking today") — the notification should link straight into cook detail, not the feed root

### Search

- Yelp's autocomplete-from-partial-input is the standard, but our harder problem is bilingual mixed-language input (`RESEARCH.md` Finding 4), which none of the surveyed apps solve — this stays a genuinely novel piece of work, not something to copy from a comparable
- Don't build a language toggle (the standard multilingual-UX advice) — that solves the wrong problem. Our titles mix Spanish and English *within the same string*; the fix is the synonym table and bilingual `tsvector` already in `IMPLEMENTATION_PLAN.md` §3, not a settings switch

### Trust & cook profile

- Airbnb's core lesson, worth stating plainly since it cuts against instinct: **trust signals work best surfaced at every decision point, not centralized on a single "verified" page.** Put the permit badge on the card, the cook detail, and the profile — not just the profile
- Airbnb's two-sided trust finding matters here too — MEHKO cooks are letting strangers know where they live (even fuzzed); consider a lightweight buyer-side signal (verified phone, claim history) visible to the cook before they confirm a claim, not just cook-visible-to-buyer
- Badge design: Superhost-style compact badges near the name, not paragraph-length disclosure text on the card — save the full permit number / agency name / insurance disclosure for the cook detail and profile, where the IFSI requirements (`PRD.md` §8) actually need to render

### Allergens

- Established best practice is **per-item allergen chips at the dish level**, not a single footnote on the cook's profile — matches the mandatory `allergens text[]` field already in the schema (`IMPLEMENTATION_PLAN.md` §2)
- Explicitly avoid: color-only indicators, hover tooltips (no hover on mobile), collapsed/accordion sections — all flagged as accessibility failures in the research, and allergen information is the one place in this app where an accessibility failure is a safety failure, not just a UX one

### Cook-side (menu builder, availability toggle)

- WoodSpoon's cook-side "accept/decline with an onscreen prep timer" is a strong pattern *if* we ever add claim-confirmation — not required for v1 (handoff-only), but worth keeping in mind for `PRD.md` §11's open question on claim semantics
- Hotplate's "clone last drop" is called out by their own users as what makes recurring selling sustainable. The underlying insight — **the recurring action must be near-zero effort** — carries over, but our version is stronger: the menu is entered once and the recurring action is a single availability toggle, so there's nothing to clone at all

---

## 3. Anti-patterns — grounded in our own research, not generic advice

These aren't standard UX warnings; each one maps to a specific failure this project already diagnosed.

| Anti-pattern | Why it matters *here* specifically |
|---|---|
| Bare price display (`$3`, no unit) | This is the exact failure that breaks OfferUp and Marketplace (`RESEARCH.md` Findings 2). `Price.display` must always render unit + minimum, never a bare number |
| Manufactured urgency (fake countdowns, "3 left!" that isn't real) | FTC treats this as a deceptive dark pattern generally — but we're also an IFSI operating under active health-department attention (`PRD.md` §8). Any scarcity signal we show must be the *real* `remaining` count from the schema, never a synthetic one |
| Centralizing trust on one profile screen | Contradicts Airbnb's own finding that trust needs to be visible at every decision point, not gated behind a tap |
| A language toggle | Solves a problem this market doesn't have (translated content) instead of the one it does have (mixed-language content) — wastes a build cycle |
| Treating the map and the feed as sequenced features | Every direct comparable (Yelp, COOK Connect) ships both together; users move between spatial and temporal browsing depending on whether they know *where* or *when* they want food |
| Full-page navigation on pin tap | Breaks map context, which is the whole value of the Discover screen existing separately from the feed |

---

## 4. Honest scarcity — a note specific to this product

Drop-culture research surfaced something worth stating directly: countdown timers and low-stock badges measurably work, and a 2025 University of Wuppertal study found *aggressive* scarcity (very fast sellouts) can actually reduce long-term loyalty because buyers feel excluded. For us there's a sharper version of that tradeoff — the FTC's dark-pattern guidance on fake urgency isn't background risk, it's directly adjacent to a business we've already flagged as under real regulatory attention (`PRD.md` §8, §10).

Under the availability model we have *less* synthetic-urgency surface than a drop-based product would, which is a quiet advantage: there's no countdown to inflate and no capacity bar to manipulate. The only scarcity signals we show are `serving_status = 'sold_out'` and per-item availability — both set by the cook, both true by construction. Keep it that way.

## 5. Open item for `PRD.md`

COOK Connect is close enough to warrant a real look at the live product (not just the marketing page) and a positioning decision, not just a UX comparison — recommend adding to `PRD.md` §11's open questions if this hasn't been addressed elsewhere. Not doing that edit here since it wasn't asked for in this pass.

## 6. Native-only capabilities — what a web shell structurally can't do

A responsive web page can copy a card layout, a map, even a bottom tab bar. It cannot copy these, and each maps to something already central to our model:

- **Live Activity for an active Claim.** From the moment a buyer claims until pickup: cook name, items, address, one-tap into the contact handoff on the Lock Screen / Dynamic Island. A persistent handoff card rather than a countdown (no fixed window exists under the availability model). This is coordination UI, not transaction UI — it fits the discovery-and-handoff thesis (`PRD.md` §2) precisely, rather than being a bolt-on gimmick. No PWA can ship this; it's a native-only API.
- **Cook-side widget / Control Center control for the availability toggle.** Under the availability model this is no longer a nice-to-have — it's the highest-value native capability in the product. The toggle is the most-used control in the app and stale availability is the model's defining failure mode (`PRD.md` §5), so cutting it from ~6 taps to one is directly load-bearing. A web competitor cannot put a control on the Lock Screen at all.
- **A buyer-side home-screen widget** showing which followed cooks are open right now (WidgetKit timeline) — makes the retention loop ambient instead of requiring an app open, something a bookmarked site cannot offer.
- **Real APNs push**, not web push — iOS web push requires the user to add the site to their home screen first and is materially less reliable even then. The "Maria is cooking today" notification (`PRD.md` §6) depends on this actually landing.
- **Rich, deep-linked push** — an opening notification can carry a photo and deep-link straight into cook detail, which is Hotplate's SMS-link pattern (§1) done natively instead of bouncing through an outbound text.
- **Native camera/photo picker** for the cook-side menu builder — lower friction than a web file-upload dialog, and this app's whole hook is photo-first discovery (Yelp precedent, §2) starting on the supply side.
- **App Store discovery as a distinct channel** — Food & Drink category browse and App Store search reach an audience a web-only product structurally cannot appear in front of.
- **Native MapKit** rendering and gesture performance over a web map SDK embed, which matters more than usual here given the custom fuzzed-pin logic (`PRD.md` §7) already adds rendering complexity on top of a standard map.

The Live Activity is the standout: it's the one item on this list that's not just "faster/smoother than web" but a genuinely different interaction a web competitor cannot build at all, and it sits exactly on the seam between "discovery" and "handoff" that's already the spine of this product. Worth an early prototype, not a v1.5 nice-to-have.
