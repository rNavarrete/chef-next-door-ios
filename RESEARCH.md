# Research: The Home-Kitchen Food Scene

*Compiled 2026-07-25. Two independent reads of the same market.*

## Sources & confidence

| Source | Method | Confidence |
|---|---|---|
| **OfferUp** (this session) | ~150 listings across 4 queries, LA / ZIP 90011, 30mi | **High** — directly observed, quoted below |
| **Facebook Marketplace** | ~15 searches, several hundred listings, West Covina 40mi, via separate agent report | **Medium** — secondhand, not independently verified |
| **CA legal/regulatory** (this session) | WebSearch across county, legal-aid, and IFSI-reference sources; primary LA County DPH page redirect-looped and could not be fetched directly | **Medium-High** — corroborated across multiple independent secondary sources, but not read from the primary county page itself |

Where the two agree, confidence is high — they used different platforms, different query sets, and overlapping-but-distinct geographies (Central/South LA vs. San Gabriel Valley / Inland Empire).

---

## Finding 1 — The listing is an ad, not a transaction

**The single most important structural fact.** Marketplace food listings are cheap storefront advertisements. The actual ordering happens in DMs, over text, or on Instagram. Descriptions carry weekly rotating menus; a large share of sellers funnel buyers to an Instagram handle for the real process.

**Product consequence:** an app that tries to own checkout is fighting the grain of the market. The scene's transaction layer already exists and works (cash, Venmo, Zelle, DM). What does *not* exist is a discovery layer.

## Finding 2 — Displayed price is frequently not the price

Two independent failure modes, both confirmed:

**Unit ambiguity** (OfferUp, observed):
```
Pupusas          $3      Pupusas 4x1     $1      Pupusa       $90
Tamales De Elote $75     Tamal           $30     Tamales      $3
```
Per-piece, per-dozen, and per-party-tray all share one `price` field.

**Deliberate visibility hacks** (Marketplace, reported): `$1`, `Free`, and absurd values (`$444`, `$111,111`, `$222,222`) used to game sort and thumbnail attention, with the real menu buried in the description. One Pasadena meal-prep listing shows `$1` on the card and sells packages at `$55 / $90 / $110` inside.

**Product consequence:** price sort and price filter are *structurally unbuildable* on scraped data. Any quantitative model built off card prices is garbage. Price must be captured as `(amount, unit, minimum)` at entry time or not at all.

## Finding 3 — Discovery is broken

Measured on OfferUp — share of results that were actually food for sale:

| Query | Results | Actual food | Signal |
|---|---:|---:|---:|
| `pupusas` | 48 | 5 | **10%** |
| `tamales` | 50 | 6 | **12%** |
| `meal prep` | 48 | 3 | **6%** |
| `comida casera` | 10 | 7 (one caterer) | — |

The other ~90% is *equipment*: ollas, vaporeras, planchas, comals, steamers, tamale carts. Searching `pupusas` in the largest pupusa market in America returns 43 griddles and 5 pupusas.

This specific ratio is an OfferUp artifact and should **not** be assumed to transfer to Marketplace, which has no comparable wall of restaurant equipment. The general problem — food supply is hard to find — is confirmed on both.

## Finding 4 — Bilingual is the default, not an edge case

Titles mix Spanish and English mid-string, freely, on both platforms:
```
Tamales a Domicilio · Comida a Domicilio · Vendo una holla grande para tamales
Meal Prep/Food Delivery/ Comida a Domicilio
```
Marketplace listings are additionally reported as heavily Spanish-first and emoji-loaded for thumbnail attention.

**Product consequence:** an English-only search index misses half the market, including the half with the deepest supply. Bilingual search is a day-one architectural requirement, not an i18n phase.

Note also that delivery is encoded *in prose* — `a Domicilio` **is** the delivery flag. There is no structured field, so it cannot be filtered.

## Finding 5 — It's intermittent availability, not standing inventory

Weekly rotating menus. `Tís The Season For Tamales`. Sourdough microbakeries with farmers-market tie-ins. This food is cooked in quantity, sold, and then gone until the cook decides to cook again.

Every general marketplace models a listing as a durable good sitting at a fixed price until sold. That is the wrong primitive for supply that appears and disappears.

**Product consequence:** the core state is **availability the cook controls** — serving / sold out / closed — not a durable listing.

> **Revised 2026-07-25.** This finding originally concluded that the core object should be a scheduled **Drop** (batch + pickup window + declared capacity), modeled on Hotplate. That was an over-read. Hotplate's users are professionalized bakers who *adopted a drop tool*; the cooks actually observed in this research post a listing and take it down when they're done. The behavioral evidence here supports **intermittence**, not **scheduling** — those are different claims, and the original wording conflated them. The scheduled-window pattern is real but confined to the sourdough/cottage-food segment (Finding 7), not the savory MEHKO majority.

## Finding 6 — Trust is thin, and compliance is the gap

- Few sellers carry platform rating badges; many accounts created 2025–2026
- Photos frequently generic or stock-looking
- **Almost nobody mentions a cottage food permit or health registration**
- Searching cottage-food licensing surfaces people *selling food-handler certification services* for $40–50

That last detail is the market telling you where the gap is. This is an unregulated gray-market food supply, and trust is its scarcest resource.

**Product consequence:** verification is the most defensible wedge available. See `PRD.md` § Trust & Compliance.

## Finding 7 — Supply segments by capital, not just cuisine

| Segment | Price band | Character |
|---|---|---|
| Home cooks, by the piece | $1–5 | Tamales, pupusas, cookies, chamoy snacks |
| Bulk / dozens | $24–40 | Tamale dozens, cookie boxes |
| Microbakery | $10–21/loaf | Sourdough; scheduled Saturday windows, farmers-market tie-ins |
| Fitness meal prep | $8–16/meal, $45–130/wk | Most professionalized — macros and calories in descriptions |
| Event & party catering | $40–500+ | Aguas frescas, esquite bars, taco catering, charcuterie |
| Private chef | $13 → custom | Westside-concentrated |
| Snack wholesale arbitrage | by the case | Baldwin Park hub |
| Food trailers & trucks | $8k–69k | Fontana/Rialto dealer corridor |

The same platform serves a $3 cookie seller and a $25,000 lonchera buyer. That capital ladder is a real part of why it functions as a business incubator — and a reason to expect cooks to graduate off any app that only serves the bottom rung.

## Finding 8 — Sharp geographic specialization

- **Tamales & sourdough** — San Gabriel Valley (sourdough clustered in Covina, Glendora, Azusa)
- **Meal prep** — Ontario, Riverside, Downey
- **Premium private chefs** — Westside
- **Snack wholesale** — Baldwin Park
- **Food trailers** — Fontana, Rialto

**Product consequence:** clustering means a single-neighborhood launch can reach real density. It also means national rollout is really N local rollouts.

## Finding 9 — Spam and duplication defeat ranking

One Paramount seller posted 20+ near-identical plancha listings. The `comida casera` caterer posted 7 identical $1,500 listings. Observed directly on OfferUp; ranking has no visible defense.

## Finding 10 — the legal framework already exists, and it points at cooked meals, not baking

The prior draft of this research (and the PRD it fed) assumed savory, refrigeration-dependent home cooking sat in legal limbo. That assumption was wrong. Los Angeles County adopted AB 626 in May 2024 and actively issues **Microenterprise Home Kitchen Operation (MEHKO)** permits — a real, opted-in category for hot, cooked-to-order meals sold directly from a home kitchen. Over 100 permits were issued within a year of adoption.

**MEHKO, in brief:**
- Covers hot, made-to-order meals — the exact segment (tamales, birria, pupusas, plates) that Findings 3 and 7 show is the deepest and highest-volume part of this market
- Capped at **30 meals/day, 90/week, $100,000 gross/year** per operator
- Food must be prepared, cooked, and served or delivered **the same day** it's made
- **Direct sale only** — no third-party delivery (DoorDash, UberEats, etc. explicitly prohibited)
- **No catering** — a MEHKO permit does not cover the event/catering segment described in Finding 7
- Up to 1 FTE-equivalent employee beyond family/household
- Application fee $597 + $347 annual. A county subsidy covering the $597 fee for the first 1,000 applicants (first-come-first-served, and only for operators with net revenue under $50k, not previously subsidized, outside Pasadena/Long Beach/Vernon) is advertised "through June 30, 2026." That date has passed as of this writing (2026-07-25), yet a live LA County page (`opportunity.lacounty.gov`, checked 2026-07-25) still displays the identical unedited text. This is genuinely unresolved, not just uncautiously stated: the primary source, `publichealth.lacounty.gov`, blocks direct fetching outright (bot detection, confirmed across three separate paths), and a first-come-first-served pool of 1,000 slots could be exhausted by volume independent of the date, with nobody obligated to update the marketing copy either way. **Do not state a subsidy status to a cook without calling first** — (626) 430-9855 or homebasedfoods@ph.lacounty.gov.
- Advertisements must display **"Made in a Home Kitchen"** plus the name of the issuing enforcement agency

This is a materially different legal picture than cottage food (which only ever covered shelf-stable baked goods), and it means the deepest supply in the research — savory home cooking — has a legitimate compliance path in the exact county this research covers.

## Finding 11 — a platform that lists MEHKOs has its own legal identity

California Retail Food Code §114367(b) defines an **"Internet Food Service Intermediary" (IFSI)**: a platform through which a MEHKO may offer food for sale. That definition describes exactly the product under discussion, not a neighboring concern. A precedent already exists — COOK Connect operates today as a registered IFSI.

Confirmed by a direct, current read of CDPH's own requirements page (`cdph.ca.gov`, last updated 2024-12-03 — primary source, fetched this session via browser after the state's PDF-download link and the redirect-blocked county domain both failed as direct fetches):

- **Register with CDPH Food and Drug Branch** — state-level, separate from the county DPH that issues MEHKO permits to cooks. Mail-in paper application (Form CDPH 9144) to Sacramento, not an online portal. No fee is stated anywhere in the primary source, unlike the heavily-documented $597/$347 cook-side MEHKO fee — likely free, unconfirmed. FDB contact: 1-800-495-3232 / FDBfood@cdph.ca.gov.
- Registration is required "**prior to** advertising or promoting MEHKOs" — CDPH's own wording, stricter than earlier secondary sources suggested.
- Clearly and conspicuously post, before any listing publishes: MEHKO permitting requirements; any fees the platform itself charges; whether the platform carries liability insurance; a dedicated field for the MEHKO's permit number *and* the issuing county agency's name; notice that the permit must be renewed annually; how a consumer reports a food-safety complaint.
- **The word "catering" (or any variation) is barred from any MEHKO listing or publication** — a direct statutory prohibition, not implied.
- The enabling ordinance must exist in "the local governmental jurisdiction where the MEHKO resides." Pasadena, Long Beach, and Vernon recur as carve-outs in county materials, and each runs an independent health department. **Whether the operative unit is the city or the enforcement agency is unresolved** — an external review argued county authorization reaches cities within it, which appears to conflict with the CDPH wording above. We model it as enforcement agency (the carve-outs track agencies, not municipal boundaries), but this is a live legal question, not a settled finding: `COUNSEL_QUESTIONS.md` Q2.
- **Two distinct escalation duties:** (1) 3+ unrelated food-safety complaints from *verified purchasers* → submit the cook's name and permit number to local enforcement within **two weeks of the third complaint**; (2) if local enforcement itself flags a significant complaint, the IFSI must supply the cook's info plus a list of every buyer who purchased from that cook the same day.
- Third-party delivery ads for MEHKO food are barred except under a narrow statutory carve-out (Cal Code §114367.5(2)(b)) not yet researched in detail.
- No renewal requirement is mentioned for the IFSI registration itself (unlike the cook's annual MEHKO permit).

This reframes Finding 6 (trust is thin, compliance is unaddressed): the compliance gap in this market isn't just a differentiator to build toward, it's a specific, external, already-defined checklist for anyone operating a platform in this space.

**Sources:** CDPH "General Requirements for Internet Food Service Intermediaries" (cdph.ca.gov, primary, fetched directly, last updated 2024-12-03); LA County DPH MEHKO page (redirect-looped, not directly fetchable this session); LA County press release (100 permits issued, May 2025); Cook Alliance MEHKO FAQ and County Technical FAQ; Chefry and Arc & Ledger MEHKO LA guides; internetfoodserviceintermediary.com; mehko.org.

---

## Contested / unverified

- **`birria` returned zero Marketplace results within 40 miles.** The source agent read this as keyword-level moderation or an indexing quirk. My OfferUp data shows birria demand indirectly, through equipment listings (`Pot for Tamales, Posole, Birria`; `Parrilla Para Pupusas, Tacos, Enchilas, Biria`), so supply and demand plainly exist in the region. **Treat the cause as unknown.** Do not build on a moderation theory.
- All Marketplace figures are secondhand and were not reproducible in this session — `facebook.com` is blocked at the domain level in the browser extension used here.
- Both reads are Southern California only. Nothing here establishes the scene's shape in Houston, Phoenix, Chicago, or the Bay.
