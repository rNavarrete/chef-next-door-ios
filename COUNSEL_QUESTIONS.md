# Questions for California Food-Law Counsel

*Prepared 2026-07-25 · Lit Kitchen · pre-build*

**Read alongside:** [`PRD.md`](PRD.md) §8 (compliance position), [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) §2 (data model).

---

## What we are building

A native iOS app for discovering home-cooked food from permitted home kitchens in Los Angeles County — primarily **MEHKO**-permitted cooked meals (Cal. HSC §113825 et seq., LA County opted in May 2024), secondarily cottage-food baked goods.

Mechanics that matter to the legal analysis:

- A cook creates a storefront with a menu and prices, and toggles it visible when they are cooking.
- Buyers browse and tap "tell her you're coming." **The app then hands off to the cook's own SMS, WhatsApp, or Instagram.**
- **No payment is processed, held, or facilitated by us.** No cart, no checkout, no escrow, no payout.
- **We charge nothing.** No buyer fee, no cook fee, no subscription, no commission, no advertising sold, no sponsored placement. Revenue today is zero, from any source.
- We display each cook's permit number and issuing agency, and "Made in a Home Kitchen," on every MEHKO listing.
- We do not offer, arrange, or advertise third-party delivery.

## Why we are asking rather than proceeding

Our planning docs asserted that we are an **Internet Food Service Intermediary (IFSI)** and treated CDPH registration as a post-launch task. Reviewing the statute more carefully surfaced a definitional problem we cannot resolve ourselves, and we would rather fix the classification than the consequences.

---

## Q1 — Are we an IFSI at all, given we derive no revenue? *(highest priority)*

Cal. HSC §114367(b) defines an internet food service intermediary as an entity providing a platform through which a MEHKO may offer food for sale **"and from which the internet food service intermediary derives revenues, including, but not limited to, revenues from advertising and fees for services."**

We derive no revenue of any kind — not from fees, not from advertising, not from data, not from placement.

1. Does the revenue clause operate as a **necessary element** of the definition, such that a genuinely zero-revenue platform falls outside it?
2. If we are outside the definition, what obligations attach to us instead? We assume "not an IFSI" means *unclear* duties rather than *no* duties, and we would rather know than infer.
3. Does an intent to monetize later (we have no model yet, and no take rate is planned) change the analysis at the moment we launch?
4. Is voluntary registration available and advisable even if not required — as a good-faith posture with the enforcement agencies whose cooks we list?

**Why it's urgent:** CDPH states registration is required **prior to** advertising or promoting MEHKOs. If we are an IFSI, our current plan to onboard cooks before registering is a violation. If we are not, we may be building compliance machinery for a regime that does not apply — and, more importantly, **missing the one that does**.

**Concrete artifact at stake:** a designed in-app screen currently renders "Fees — $0" directly above "We operate as an Internet Food Service Intermediary under California Retail Food Code §114367." We will not ship that pair of sentences until you tell us which is right.

---

## Q2 — What is the correct jurisdictional unit for verifying a cook's permit?

We verify each cook's permit before badging them, and we must not list a cook operating where MEHKOs are not authorized.

CDPH materials say the *local governmental jurisdiction where the MEHKO resides* must have an authorizing ordinance. LA County has opted in, but Pasadena, Long Beach, and Vernon operate independent health departments and appear as carve-outs in county materials.

1. Is the operative unit the **county**, the **city**, or the **enforcement agency with jurisdiction over that address**?
2. Where a city runs its own health department inside an opted-in county, does the county's authorization reach that city's residents?
3. Is there an authoritative, maintained list of authorizing jurisdictions and their agencies we should be reading from — or must we track it ourselves?
4. What is our exposure if we list a cook holding a facially valid permit that later proves improperly issued, or issued by an agency lacking authority?

We have modeled this as an **enforcement-agency** table rather than a city string, on the theory that the carve-outs track agencies rather than municipal boundaries. Please confirm or correct that model — it is cheap to change now and expensive after launch.

---

## Q3 — Our records show *intent to buy*, not purchases. Does that satisfy the duties that assume purchases?

The statutory duties reference consumers who have **made a purchase through** the platform:

- Escalation on 3+ unrelated food-safety complaints from verified purchasers.
- On an agency's request, producing the cook's name and permit number **plus a list of consumers who purchased food from that cook on the same day.**

**What we actually record** is a "claim": a buyer pressed a button, we opened a text message, and we revealed the pickup address to that buyer. Whether food was ever bought, and for how much, happens off-platform and is invisible to us. Conversely, a buyer may discover a cook here and buy without ever claiming.

1. Do our claim records constitute purchases "through" the platform for these purposes — or do we simply have no purchasers, and therefore no duty?
2. If we have no qualifying purchasers, are we nonetheless expected to produce what we do have on an agency request?
3. What should we retain, and for how long, to be able to answer an agency in good faith? We currently plan to log every address disclosure with buyer, kitchen, and timestamp.
4. Should we add explicit two-sided pickup confirmation to create better evidence, or does building purchase-adjacent records *increase* our exposure by making us look more like a transaction platform than we are?

Question 4 is the one we would most like your instinct on, because it cuts in both directions and we can build it either way.

---

## Q4 — Liability exposure and required insurance

1. What is our realistic exposure if a buyer is harmed by food they found through us, given we take no payment and do not handle food?
2. Does **verifying** permits and displaying a badge increase our duty of care by implying endorsement, relative to listing cooks without verification? *(If so, say plainly whether the safer product is the less trustworthy one — we would rather hear that than discover it.)*
3. What coverage should we carry, at what limits, before a single real cook is listed?
4. If an IFSI must "clearly and conspicuously post" whether it carries liability insurance, what exactly must that statement say, and what should it disclose about coverage limits and exclusions?
5. Does our handoff model — where the entire transaction is off-platform — meaningfully reduce exposure, or is it immaterial once we are the discovery layer that caused the meeting?

---

## Q5 — Address disclosure and cook safety

Cooks operate from their homes; many are women working alone. We show only a coarse, non-invertible approximation publicly, and release the exact address only after the cook confirms a specific buyer's claim, with per-buyer daily caps and a full disclosure log.

1. Any legal constraint on how precisely we may display a permitted home kitchen's location? Are permitted MEHKO addresses public records via the county, and does that change our obligations?
2. Do we incur liability if a buyer misuses a disclosed address?
3. Does logging every disclosure create discovery or privacy obligations we should plan for?
4. Any obligation to disclose to cooks how their address is handled, beyond ordinary privacy-policy practice?

---

## Q6 — Content and advertising rules

1. We block the word "catering" and its variants from MEHKO listings. Does that obligation extend to cook-authored free text, buyer-visible messages, and our own marketing?
2. "Made in a Home Kitchen" plus the issuing agency must appear on advertising. Does an in-app listing card count as advertising for this purpose? A push notification? A share sheet?
3. We show no third-party delivery. Does the prohibition extend to *displaying* that a cook independently offers delivery, or to a cook mentioning it in their own note?
4. Are there disclosure requirements for the secondary cottage-food category that differ from MEHKO, and can both appear in one feed?

---

## Q7 — Sequencing

Our build is roughly four months. We want the legal position settled before real permitted cooks are onboarded, not before code is written.

1. Is there a defensible way to test with a small number of real cooks before classification is settled — a closed beta, synthetic listings, cottage-food only — or is any real MEHKO listing gated on Q1?
2. If registration is required, what is realistic turnaround on the mailed CDPH Form 9144, and is there any expedited path?
3. What should exist in writing before launch: terms of service, cook agreement, buyer disclosures, an incident-response plan, a records-retention policy?
4. Anything material we have not asked about? We are aware we do not know the shape of what we do not know here.

---

## Our current assumptions, stated so you can correct them

We would rather have these contradicted early than discover them wrong later.

| # | Assumption | Confidence |
|---|---|---|
| 1 | We are an IFSI and must register with CDPH before promoting MEHKOs | **Low** — Q1 is precisely this |
| 2 | Enforcement-agency jurisdiction, not city, governs permit verification | Medium |
| 3 | Claims are not purchases, so purchaser-based duties may not attach | Low |
| 4 | Taking no payment materially reduces our liability | **Low** — assumed, never tested |
| 5 | Verifying permits reduces net risk despite implying endorsement | Medium |
| 6 | Cottage-food listings carry a lighter burden than MEHKO | Medium |
| 7 | Coarse public location + gated release satisfies any location obligation | Medium |

## Documents we can provide

Full PRD, data model and retention design, the disclosure-screen copy, permit-verification workflow, and complaint/escalation admin flow. All are still drafts and all are cheap to change **now** — which is why we are asking before building rather than after.
