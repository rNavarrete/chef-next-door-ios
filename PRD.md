# Lit Kitchen — Product Requirements

*Draft v0.1 · 2026-07-25 · grounded in [`RESEARCH.md`](RESEARCH.md)*

---

## 1. Problem

There is a large, real, growing home-kitchen food economy operating on general-purpose marketplaces that were never designed for it. The supply is excellent and the discovery is terrible.

A buyer who wants good home-cooked food near them this weekend has no way to find it. They must:

- guess dish names in the right language,
- wade through ~90% irrelevant equipment results (measured, OfferUp),
- decode prices that are deliberately fake (`$1` cards hiding `$110` packages),
- open each listing to find whether it's a $3 tamal or a $1,500 party package,
- and then leave the platform to Instagram or SMS to actually order.

A cook has the mirror problem: their listing is buried, their weekly menu doesn't fit the format, and their only lever for visibility is to spam duplicates or game the price field.

## 2. Thesis

**The marketplace listing is a lie, in four specific ways** — and each one is a product opportunity:

| The lie | The truth | What we build |
|---|---|---|
| A price | An ambiguous or fake number | Structured `(amount, unit, minimum)` |
| A standing listing | A cook who is serving *today*, or isn't | Explicit **availability** the cook controls |
| A transaction | An ad that funnels to DM | Discovery + clean handoff |
| A searchable index | Monolingual keyword soup | Bilingual, synonym-aware search |

**Lit Kitchen makes home-kitchen supply legible in space and time.** The two primary surfaces are a **map** ("who's cooking near me") and an **open-now feed** ("who's serving today"). That pairing *is* the product.

**On availability, not scheduled batches.** An earlier draft modeled supply as scheduled "drops" — a batch with a fixed pickup window and declared capacity, borrowed from Hotplate. That was wrong for this market. Hotplate's users are professionalized bakers who opted into a drop tool; the cooks we actually observed on Marketplace and OfferUp behave differently — they put a listing up, and take it down when they're done serving. The product must match that: **a cook posts a storefront once and toggles it on and off.** No scheduling UI, no capacity declaration, no batch object.

**We do not try to own the transaction.** The scene's payment layer already works. We own discovery and trust, and hand off cleanly.

## 3. Scope decision — MEHKO cooked meals primary, cottage food baked goods secondary

This reverses the earlier draft of this document, which recommended baked-goods-only on the assumption that savory home cooking sat in legal limbo. That assumption was wrong: Los Angeles County adopted AB 626 in May 2024 and actively issues MEHKO permits for hot, cooked-to-order meals sold direct from a home kitchen (`RESEARCH.md` Finding 10). The legal blocker that justified baking-first no longer exists in this county.

**Primary category — MEHKO-permitted cooked meals.** Tamales, birria, pupusas, plates, elote — the exact segment Finding 3 and Finding 7 show is the deepest and highest-volume part of this market. This is also the segment with the most acute discovery problem (the 6–12% signal-to-noise measured on OfferUp), so it's where the product does the most good.

**Secondary category — cottage food baked goods.** Cookies, bread, cakes without cream filling, jams — shelf-stable, no meal cap, different (lighter) permit path. The sourdough microbakery cluster in Covina/Glendora/Azusa sits in the same San Gabriel Valley geography as the tamale/pupusa supply, so one launch region serves both categories. Worth noting these bakers are the *one* segment that genuinely runs on scheduled windows — if a scheduling layer is ever justified, it's here, and it should be added as an option on top of availability rather than as the base model.

**What this changes structurally:**
- `menu_items.category_type` distinguishes `mehko_meal` from `cottage_food` — they carry different disclosure content, different verification paths (MEHKO permit number vs. cottage food registration), and different handling of same-day-service requirements
- MEHKO meals require same-day pickup (food must be served or delivered the day it's cooked) — the availability model fits this naturally, since "serving" means serving *now*, not taking orders for a future date
- Party/event catering (Finding 7) is explicitly **excluded** — a MEHKO permit does not cover catering, so that segment needs a different permit type entirely and stays out of v1 regardless of category
- The regulatory meal cap (30/day, 90/week, $100k/yr per cook) is real and enforced by the county against the cook, not by us — see §8 for how the app surfaces it

**Confirmed with the user:** primary/secondary split, no hard block on the meal cap (soft warning only, see §8), and both categories ship in v1 rather than sequencing baked goods out.

## 4. Users

**Primary — the buyer.** Lives in or near the launch cluster. Wants good food from a neighbor this weekend. Currently finds cooks by word of mouth and Instagram. Frustration is discovery, not payment.

**Primary — the cook.** Cooks 20–80 units when they decide to cook, sells out, takes orders by DM. Already semi-organized: has an Instagram, a rotating menu, a group chat of regulars. Frustration is reach and admin overhead, not payment. Will not plan a schedule in advance — the product must ask nothing of them beyond "I'm open now."

**Explicitly not v1:** party caterers ($150–1,500 packages), food-truck buyers, snack wholesalers. Different intent, different UI, different unit economics. They are in the research because they explain the market's shape, not because we serve them now.

## 5. Core domain model

Four objects. Getting these right is most of the product.

- **Cook** — identity and trust. Display name, story, photos, trust badges, links out (Instagram, SMS). *Not* "Seller."
- **Kitchen** — where they cook and where you pick up. Carries both an exact point (private) and a fuzzed public point (§7).
- **MenuItem** — a thing they make. Name (bilingual), description, photos, allergens, a **category type** (`mehko_meal` vs `cottage_food` — different permit path, different disclosure, MEHKO items are same-day-service only), and a **structured price**: `(amount_cents, unit, min_quantity)`. A bare price is never accepted.
- **ServingSession** — *the load-bearing object.* One row per period of service, created when a cook opens and closed when they stop: `opened_at`, `last_confirmed_at`, `closed_at`, `closed_by`, status. Individual MenuItems carry their own availability, so a cook can sell out of tamales while still selling champurrado.

  **Why this exists, given we removed the batch object:** an earlier draft put availability directly on the mutable Cook row. That erased history — the timestamps were overwritten on every open, so there was no record of *which* service period a claim, review, or complaint belonged to, and the freshness metrics in §9 were literally uncomputable. A session is **not** a return to scheduled drops: no future scheduling, no declared capacity, no pickup window. It records what happened, not what is planned.

Plus **Claim** (buyer signals intent against an open session → unlocks handoff + exact address) and **Review** (only creatable against a completed Claim).

**A claim is not a purchase, and the docs must not pretend otherwise.** It records that someone opened a text. The purchase — if it happens — occurs off-platform, in a DM, in cash. Anywhere this document previously implied claims constitute purchase records for regulatory purposes, that assertion is now marked open (§8) pending `COUNSEL_QUESTIONS.md` Q3.

**The cost of this model, stated honestly:** availability is only as good as the cook's diligence in flipping the toggle. Stale-open storefronts — a buyer arriving at a kitchen that stopped serving hours ago — are the single biggest failure mode here, and they did not exist under a scheduled-batch model.

**Mitigation: the decay ladder** (designed; see `DESIGN_BRIEF.md` §7a). Availability is not binary over time — it decays through four states, and the interface stops leading with the clock and starts leading with the question:

| Age since last confirmation | Presentation | Primary action |
|---|---|---|
| 0–4 h · **lit** | Full glow, pulsing dot | Claim |
| 4–6 h · **dimming** | Desaturated dot, no pulse, glow drops; adds "Last said something at 9:40 am" | Claim |
| 6 h+ · **unconfirmed** | Hollow ring, no glow, neutral-gray label `Lit at 9:40 am · unconfirmed since` | **Ask if he's still cooking** |
| Auto-off 8 pm | Dark card | Turn his light on for me |

Three rules make it work:

1. **Time is always an absolute clock time.** Elapsed durations ("15 min ago", "6h ago") never appear — they read as either ambiguous or accusatory. Always `Cooking · since 9:40 am`.
2. **Actions that assert current service reset the clock** — a sold-out flip, a note edit, answering a claim *from this session*, an explicit "still cooking." Diligence is rewarded automatically, with no "still open?" chore. Deliberately excluded: clearing an old claim, or editing prices and photos — bookkeeping is not cooking, and an earlier draft that counted it would have relit kitchens that went cold hours before.
3. **Unconfirmed cooks rank below confirmed ones** and are never the first row of the feed.

Plus a cook-side push at ~8h, answerable from the Lock Screen, honest about why it matters: *"Still cooking, Beto? Your light has been on since 9:40. Two people are looking at it right now."* → `Still going` / `I'm done`.

We never assert a cook is closed. We state what is known and give one tap that resolves it. Claiming an unconfirmed cook stays possible, demoted to a secondary `Claim anyway`.

## 6. v1 scope

### Must have

**Buyer**
- Map of cooks serving near me, clustered, with fuzzed pins; closed cooks dimmed or filtered
- "Open now" feed — cooks currently serving, sorted by proximity, with availability freshness visible
- Bilingual search across dish names, with a curated synonym layer (`tamal`↔`tamales`, `pan dulce`↔`sweet bread`, `elote`↔`corn`)
- Filters that are actually reliable because the data is structured: pickup day, distance, category, dietary/allergen
- Cook detail: photos, menu with real per-unit prices, what's still available, serving note, profile
- Claim → handoff to the cook's channel of choice (SMS / WhatsApp / Instagram). **Resolved: a claim is a warm intro, not a reservation** — it holds nothing. Stated plainly in the UI ("Doesn't hold anything — it opens a text with her"; cook side: "Nothing is reserved until you say sí"), which removes no-show risk rather than papering over it
- Follow a cook — surfaced as **"Turn her light on for me"** rather than a Follow button. Same action, correct warmth for this market, and it keeps the light metaphor intact on closed cards
- Live Activity for an active claim — cook, dish, live countdown to pickup-window close, one tap into the handoff channel (Lock Screen / Dynamic Island). The one interaction a web competitor structurally cannot build (`DESIGN_RESEARCH.md` §6) — in the v1 build, not deferred
- Push notification: "Maria is cooking today" when a followed cook opens

**Cook**
- Onboarding with Sign in with Apple + phone verification
- Menu builder that *forces* structured pricing — this is the single highest-leverage constraint in the app
- **A one-tap availability toggle** — the single most-used control in the app. Must be reachable without navigating: home screen widget, and ideally a Control Center / Lock Screen control. A cook with flour on their hands flips this while cooking
- Claim inbox with one-tap reply
- Sold-out / capacity management

**Trust**
- Permit upload (MEHKO permit number or cottage food registration) + manual verification → visible badge; permit number is public by design (IFSI requirement, §8), not private like location
- Annual permit-expiry reminder to the cook, surfaced again to buyers if it lapses
- Liability insurance disclosure screen (we carry it — state so plainly)
- Reviews tied to completed Claims only
- Report/flag flow, with an admin-visible complaint counter per cook (feeds the 3-complaints/calendar-year escalation duty, §8)

### Won't have in v1
Payments, delivery logistics, in-app chat, ratings without a claim, catering packages (also legally excluded — a MEHKO permit doesn't cover catering, §3), web app, Android.

### Deliberately not scraping
We will not seed by importing Marketplace or OfferUp listings. The price data is unreliable by construction (§Research 2), the sellers haven't consented, and the terms of service prohibit it. Seed by hand-recruiting cooks — 20 in three adjacent ZIPs.

## 7. Safety & privacy — hard requirements

These are not settings. They are constraints on the build.

- **Home addresses are never public, and are not merely policy-protected.** Cooks work out of their homes, and many are women running solo operations. Exact coordinates live in a table **no client role has any grant on**, reachable only through an authorization-checking function that logs every release (`IMPLEMENTATION_PLAN.md` §2.004, §2.009).
- **The map pin is coarsened to a ~400 m cell.** Scope of what this is for, stated plainly so nobody over-invests in it later: **a buyer who claims gets the exact address — that is the product working.** The coarsening exists so that someone can't scrape the map and harvest every cook's address *without ever claiming*. That's the whole threat model. Measured in `SPIKE_LOCATION_PRIVACY.md`; done, in CI, and needs no further work.
  - Describe it to cooks as an *area*, not as encryption or a secret. It isn't one.
  - *Noted, not a blocker:* the cell is geometric, so in a sparse area it may hold very few homes. Irrelevant at SGV density. Revisit only if expansion data says otherwise.
- **Address release is cook-controlled and rate-limited.** A buyer cannot promote their own claim; only the cook confirms. Claiming is deliberately near-frictionless, and frictionless plus home addresses is a harvesting pipeline unless bounded — so: phone-verified buyers only, a daily cap on distinct kitchens unlocked, every disclosure logged, and an alert when one account's rate spikes.
- **A cook can operate without their real name** — display name is independent of legal identity.
- **Allergen fields are mandatory** on every MenuItem. Not optional, not free-text-only.
- **No buyer→cook location exposure.** Buyers share nothing but a first name and a claim.
- Block and report on both sides, with a real human review path.

## 8. Trust & compliance — the wedge, and our own legal identity

The research is unambiguous: nobody displays a permit, trust is thin, and there's a visible cottage industry *selling food-handler certs* to these operators (Finding 6). Compliance is simultaneously our biggest liability and our best differentiator.

**We are not just building a trust feature — we are an Internet Food Service Intermediary (IFSI).** California Retail Food Code §114367(b) defines an IFSI as a platform through which a MEHKO may offer food for sale. That is a description of this app, not an analogy. A precedent operates today (COOK Connect) as a registered IFSI. This turns "verification" from a product choice into a set of specific, external obligations:

- **State registration with CDPH Food and Drug Branch** (not the county — a separate, state-level registration from the MEHKO permits our cooks hold). Process: mail-in paper application (Form CDPH 9144) to a Sacramento PO box, not an online portal — plan for real mail turnaround, not instant approval. **No registration fee is stated anywhere in the primary CDPH source**, unlike the heavily-documented cook-side MEHKO fee — likely free, but confirm before filing: 1-800-495-3232 / FDBfood@cdph.ca.gov.
- **Decision: fast follow, not a pre-launch gate.** Flagging plainly, with sharper language than before: CDPH's own requirements page states registration is required "**prior to** advertising or promoting MEHKOs" — that's less room than "fast follow" implies, not more. We're proceeding on the user's call; the registration should be filed as early as practically possible after launch, not treated as a someday item.
- **Dedicated, public permit-number field per cook**, showing the permit number *and* the name of the issuing county environmental health agency, with an annual-renewal notice to the cook. Unlike the cook's exact location, this field is meant to be *visible* — that's the compliance requirement, not a bug.
- **Our own service-fee disclosure** — separate from the insurance disclosure below, CDPH requires posting "any fees associated with the amount being charged for the services provided." Since v1 charges nothing, this is a one-line disclosure, but it's a required one, not optional copy.
- **Liability insurance disclosure** — we carry it, and the app must clearly and conspicuously state that (and, practically, what it covers) somewhere a buyer or regulator can find it. Needs a dedicated screen, not a footnote.
- **The word "catering" (or any variation) may not appear in any MEHKO listing or publication** — this is a direct statutory prohibition, not just a category-scoping choice (§3). Needs an actual content filter on `mehko_meal` titles/descriptions, not just a UI that omits a catering option.
- **Per-city jurisdiction check during permit verification** — the enabling ordinance has to exist in "the local governmental jurisdiction where the MEHKO resides," which is *why* Pasadena, Long Beach, and Vernon keep surfacing as carve-outs (they run independent health departments). Verification review checks the cook's specific city, not just "is this LA County."
- **Complaint escalation, two triggers:**
  - **IFSI-initiated:** 3+ unrelated food-safety complaints from *verified purchasers* → submit the cook's name and permit number to the local enforcement agency **within two weeks of the third complaint**. Needs a real complaint log and an admin workflow with a hard 2-week clock, not a report button that goes nowhere. **Open:** the statute says *purchasers*, and our claims record intent, not purchase (§5) — see `COUNSEL_QUESTIONS.md` Q3.
  - **LEA-initiated:** if the local enforcement agency notifies us of a significant complaint, we must supply the cook's name/permit **plus a list of every buyer who purchased from that cook the same day**. We can produce everyone who *claimed* that day, scoped to the serving session. Whether that satisfies the duty — and what we owe for buyers who never claimed but bought after finding the cook here — is Q3.
- **"Made in a Home Kitchen" + issuing agency name** must appear on every MEHKO listing's advertising surface — rendered automatically from `category_type` + the cook's **enforcement agency**, not left to the cook to remember.
- **Meal-cap awareness, not enforcement.** The county caps a MEHKO operator at 30 meals/day and 90/week; we surface a soft advisory as claims accumulate (**confirmed: no hard block**), because exceeding it is the cook's permit risk to manage. **This signal got weaker when we dropped the batch model** — without declared capacity or in-app checkout, we only count claims placed through us and cannot see DM orders. It must be labeled as a partial count ("at least N via Lit Kitchen"), never as a total, or it will mislead a cook into thinking they have headroom they don't.

**Standing position: be the app where the cooks are verified.** Cook uploads permit (MEHKO permit number, or cottage food registration for the secondary category) → human review → badge. Unverified cooks may still list, but rank lower and are visibly unverified.

> **⚠ The IFSI classification itself is now in question, which was not previously acknowledged here.** The statutory definition (§114367(b)) describes a platform "**from which the internet food service intermediary derives revenues**, including… advertising and fees for services." We charge $0 and sell no advertising. We may therefore fall *outside* the definition — which is not obviously good news, since an unclassified intermediary has unclear duties rather than none. This document previously asserted IFSI status flatly while ignoring a defining element of it, and the designed disclosure screen renders "Fees — $0" directly above "We operate as an Internet Food Service Intermediary under §114367." **That contradiction must be resolved by counsel before either statement ships.** See `COUNSEL_QUESTIONS.md` Q1.
>
> **Consequence for sequencing:** the "fast follow" registration decision was made on the assumption that we are an IFSI and simply hadn't registered yet. If classification is genuinely uncertain, the honest posture is a **gate on MEHKO-cook onboarding** (`IMPLEMENTATION_PLAN.md` M-1) rather than a fast follow — the build can proceed, the recruitment of real permitted cooks should not.

**Also still requires food-law counsel:** exact scope of platform liability for foodborne illness beyond the statutory duties; confirmation there is truly no IFSI registration fee; confirmation of current MEHKO cook-side fee status — checked directly with the county (2026-07-25) and genuinely unresolved: the primary DPH source blocks automated access, a sister county page still shows the stated June 30, 2026 subsidy deadline unedited, and the subsidy is a 1,000-slot first-come-first-served pool that could be exhausted independent of the date. Confirm by phone before this figure reaches any cook-facing material: (626) 430-9855 or homebasedfoods@ph.lacounty.gov; insurance policy adequacy against the specific disclosure duty. Flagging these because they change what we ship or when — not resolving them here.

## 9. Success metrics

**Measurement honesty first.** These targets were set by judgment, not derived from comparables, and several things we care about are only partly observable because the transaction happens off-platform. Each metric below is labeled with what it can actually see. **Define the analytics event dictionary before instrumenting** (`IMPLEMENTATION_PLAN.md` M5.5) — otherwise these are vibes with decimal points.

**The one that matters:** **repeat claim rate** — % of buyers who claim from the same cook again within 60 days. This market runs on relationships, and a buyer who returns is the strongest evidence we created value. *Known blind spot: a buyer who loved the food and now texts the cook directly is a success we will record as churn.* That failure mode is real and it biases the number **down**, so treat it as a floor, never a true retention rate.

| Metric | Target (90 days) | What it can actually see |
|---|---|---|
| Verified cooks in launch cluster | 20 | Exact |
| **Median concurrently-open kitchens** in the launch radius, during peak hours | **≥ 4** | Exact — and this, not cook count, is whether "open now" works (§11.9) |
| Cook-days served / week | 40 | Exact |
| Search → cook-detail rate | > 35% | Exact |
| Share of serving-hours in `unconfirmed` (6h+) | < 15% | Exact, from `serving_sessions` — the decay ladder's own report card |
| Claim → reported pickup | > 70% | **Self-reported by cook.** Not ground truth; cooks who don't do bookkeeping look identical to no-shows |
| **Stale-open rate** — claims against a cook who had already stopped | **< 5%** | **No ground truth.** We only learn of it when someone reports it, so measured stale-open is a floor. Pair with a periodic sampled callback to a handful of cooks |
| Time from app open → first claimable result | < 10s | Exact once "claimable" is defined: a lit cook, in range, with an available item |

## 10. Key risks

| Risk | Severity | Mitigation |
|---|---|---|
| Legal exposure from unpermitted sellers | **High** | Category gating + verification + counsel (§8) |
| Operating the core listing loop before IFSI state registration completes | **High** | File registration as early as practically possible post-launch; keep the exposure window short; counsel review of the interim period (§8) |
| Cold start — empty map kills it | **High** | Hand-recruit 20 cooks in 3 ZIPs before any buyer launch |
| Cooks won't leave Instagram | **High** | Don't ask them to. Handoff *to* Instagram is a feature |
| A foodborne illness incident | **High** | Verification, allergens, incident response plan, insurance (carried, see §8) |
| **Stale availability** — cooks forget to close, buyers arrive at a cold kitchen | **High** | **The decay ladder** (§5): four-state decay, absolute clock times only, activity resets the clock, unconfirmed ranks below confirmed, cook nudge at ~8h, auto-off at 8pm. The defining risk of the availability model |
| A cook exceeds the 30/day–90/week MEHKO cap and jeopardizes their permit | Medium | Soft advisory as claims accumulate (§8) — awareness only, and explicitly a partial count |
| Cooks graduate to trucks and leave | Medium | Expected — the capital ladder is real (Research 7). Serve the rung well |
| Apple review friction on food sales | Low-Med | No in-app payments in v1 materially reduces this |

## 11. Open questions

1. Do we verify permits ourselves, or partner with an existing service? COOK Connect is a live, registered IFSI — worth a scan as either prior art or a potential partner before building verification tooling from scratch.
2. ~~Does claiming reserve inventory, or is it just a warm intro?~~ **Resolved — warm intro, holds nothing**, stated plainly in the UI on both sides (§6).
3. Launch cluster — commit to Covina/Glendora/Azusa, or run a supply survey first? Worth confirming it has real MEHKO-permitted meal density, not just the sourdough cluster the original recommendation was built around.
4. What's the cook-side pricing model when we eventually monetize, given we've forgone take rate?
5. Exact filing timeline for IFSI state registration post-launch — days? weeks? Needs an owner and a date, not just "fast follow."
6. Positioning against COOK Connect (COOK Alliance's MEHKO marketplace, successor to Foodnome, launched from adjacent Riverside County) — resolved in part: user-confirmed by direct testing that it's a responsive web/PWA product, not a native app, corroborated independently (no App Store listing found). See `DESIGN_RESEARCH.md` §0 and §6 for the native-only capabilities (Live Activities, widgets, real APNs push) this opens up. Still open: whether to position explicitly against them in marketing, or let the product speak for itself.
7. **What the IFSI disclosure screen says on launch day.** Now compounded by Q1 — the screen asserts IFSI status *and* $0 fees, and those two statements are in tension (§8). The designed screen (`DESIGN_BRIEF.md` §6) surfaces "CDPH registration · status" — but registration is a fast follow (§8), so at v1 it cannot truthfully read "registered." Options: "registration pending" with a target date, or the field ships hidden until filed. Must be answered before build, not at App Store submission. Blocking for that screen only.
8. ~~Product name~~ — **Resolved: Lit Kitchen** (confirmed 2026-07-25, renamed throughout). Formerly "Bake Mapper," a name inherited from the original baked-goods-first scope that §3 later reversed. The new name earns the light metaphor and survives the scope it's now attached to. Two things to keep an eye on, neither blocking: "lit" as slang may age, and it lands differently for a Spanish-first buyer — where the literal "the kitchen light is on" reading is what does the work, which is the reading the product actually leans on.
9. **Launch density, not cook count.** The current target — 20 cooks, 40 cook-days/week, three ZIPs — averages under six openings a day spread across geography and hours, so an app whose entire thesis is "who's cooking *right now*" would routinely show zero or one result. Cook count is a vanity metric here; **concurrent open kitchens per buyer during peak hours** is the real constraint. Needs a rethink: a tighter radius, a coordinated launch time block, or recruiting for overlapping serving hours rather than headcount. Strategy call, not a design one.
10. **Is the COOK Connect differentiation durable?** Open-vs-invite-only is a reversible policy decision, and native iOS is an execution advantage rather than a moat. The sharper worry: by handing the transaction to DMs we forgo the data that makes reviews, complaint duties, and retention measurable at all (§9, §8) — the incumbent's weakest-looking choice may be load-bearing. Worth testing one narrow wedge manually before building, and worth evaluating partnership rather than assuming a second marketplace is needed.
