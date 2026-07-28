17:## Finding 1 — The listing is an ad, not a transaction
18-
19-**The single most important structural fact.** Marketplace food listings are cheap storefront advertisements. The actual ordering happens in DMs, over text, or on Instagram. Descriptions carry weekly rotating menus; a large share of sellers funnel buyers to an Instagram handle for the real process.
20-
21-**Product consequence:** an app that tries to own checkout is fighting the grain of the market. The scene's transaction layer already exists and works (cash, Venmo, Zelle, DM). What does *not* exist is a discovery layer.
22-
23:## Finding 2 — Displayed price is frequently not the price
24-
25-Two independent failure modes, both confirmed:
26-
27-**Unit ambiguity** (OfferUp, observed):
28-```
29-Pupusas          $3      Pupusas 4x1     $1      Pupusa       $90
30-Tamales De Elote $75     Tamal           $30     Tamales      $3
31-```
32-Per-piece, per-dozen, and per-party-tray all share one `price` field.
33-
34-**Deliberate visibility hacks** (Marketplace, reported): `$1`, `Free`, and absurd values (`$444`, `$111,111`, `$222,222`) used to game sort and thumbnail attention, with the real menu buried in the description. One Pasadena meal-prep listing shows `$1` on the card and sells packages at `$55 / $90 / $110` inside.
35-
--
38:## Finding 3 — Discovery is broken
39-
40-Measured on OfferUp — share of results that were actually food for sale:
41-
42-| Query | Results | Actual food | Signal |
43-|---|---:|---:|---:|
44-| `pupusas` | 48 | 5 | **10%** |
45-| `tamales` | 50 | 6 | **12%** |
46-| `meal prep` | 48 | 3 | **6%** |
47-| `comida casera` | 10 | 7 (one caterer) | — |
48-
49-The other ~90% is *equipment*: ollas, vaporeras, planchas, comals, steamers, tamale carts. Searching `pupusas` in the largest pupusa market in America returns 43 griddles and 5 pupusas.
50-
--
53:## Finding 4 — Bilingual is the default, not an edge case
54-
55-Titles mix Spanish and English mid-string, freely, on both platforms:
56-```
57-Tamales a Domicilio · Comida a Domicilio · Vendo una holla grande para tamales
58-Meal Prep/Food Delivery/ Comida a Domicilio
59-```
60-Marketplace listings are additionally reported as heavily Spanish-first and emoji-loaded for thumbnail attention.
61-
62-**Product consequence:** an English-only search index misses half the market, including the half with the deepest supply. Bilingual search is a day-one architectural requirement, not an i18n phase.
63-
64-Note also that delivery is encoded *in prose* — `a Domicilio` **is** the delivery flag. There is no structured field, so it cannot be filtered.
65-
66:## Finding 5 — It's intermittent availability, not standing inventory
67-
68-Weekly rotating menus. `Tís The Season For Tamales`. Sourdough microbakeries with farmers-market tie-ins. This food is cooked in quantity, sold, and then gone until the cook decides to cook again.
69-
70-Every general marketplace models a listing as a durable good sitting at a fixed price until sold. That is the wrong primitive for supply that appears and disappears.
71-
72-**Product consequence:** the core state is **availability the cook controls** — serving / sold out / closed — not a durable listing.
73-
74-> **Revised 2026-07-25.** This finding originally concluded that the core object should be a scheduled **Drop** (batch + pickup window + declared capacity), modeled on Hotplate. That was an over-read. Hotplate's users are professionalized bakers who *adopted a drop tool*; the cooks actually observed in this research post a listing and take it down when they're done. The behavioral evidence here supports **intermittence**, not **scheduling** — those are different claims, and the original wording conflated them. The scheduled-window pattern is real but confined to the sourdough/cottage-food segment (Finding 7), not the savory MEHKO majority.
75-
76:## Finding 6 — Trust is thin, and compliance is the gap
77-
78-- Few sellers carry platform rating badges; many accounts created 2025–2026
79-- Photos frequently generic or stock-looking
80-- **Almost nobody mentions a cottage food permit or health registration**
81-- Searching cottage-food licensing surfaces people *selling food-handler certification services* for $40–50
82-
83-That last detail is the market telling you where the gap is. This is an unregulated gray-market food supply, and trust is its scarcest resource.
84-
85-**Product consequence:** verification is the most defensible wedge available. See `PRD.md` § Trust & Compliance.
86-
87:## Finding 7 — Supply segments by capital, not just cuisine
88-
89-| Segment | Price band | Character |
90-|---|---|---|
91-| Home cooks, by the piece | $1–5 | Tamales, pupusas, cookies, chamoy snacks |
92-| Bulk / dozens | $24–40 | Tamale dozens, cookie boxes |
93-| Microbakery | $10–21/loaf | Sourdough; scheduled Saturday windows, farmers-market tie-ins |
94-| Fitness meal prep | $8–16/meal, $45–130/wk | Most professionalized — macros and calories in descriptions |
95-| Event & party catering | $40–500+ | Aguas frescas, esquite bars, taco catering, charcuterie |
96-| Private chef | $13 → custom | Westside-concentrated |
97-| Snack wholesale arbitrage | by the case | Baldwin Park hub |
98-| Food trailers & trucks | $8k–69k | Fontana/Rialto dealer corridor |
