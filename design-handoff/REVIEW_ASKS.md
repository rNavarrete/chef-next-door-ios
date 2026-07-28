# What a review would be worth most on

Ordered by how much a good answer would change. Disagreeing with the framing of
any of these is a valid answer.

## 1. Did the whimsy pass go too far, or not far enough?

The brief was "friendly and whimsical — we want to meet and care for our
neighbours". The execution was: SF Pro Rounded, 28pt radii, 2pt warm borders,
amber price pills, a Polaroid-framed cook portrait, a kawaii dumpling splash.

The risk on one side is that a product asking you to eat a stranger's food now
looks like a game, and cuteness undercuts the trust the research says is
scarcest. The risk on the other is that restraint reads as institutional, which
is what prompted the change.

**Screens:** `01`, `04`, `08`.

## 2. Is the amber-means-heat rule actually holding?

It is stated absolutely (see `DESIGN_APPROACH.md`) but there are now many amber
things on one screen: the availability line, the price pill, the card's glow
ring, the lamp dot, the "Cooking" chip, the header wash. If amber is everywhere,
it no longer marks anything.

**Screens:** `01`, `04`, `06`.

## 3. The cook profile has three stacked "notice" blocks

On `04-cook-profile.png`: an amber serving-note card, a story card, and a blue
permit card — three tinted rounded rectangles in a column, each with a small
caps header. They are different *kinds* of thing (a quote, a bio, a legal
disclosure) rendered nearly identically. Is the hierarchy legible, and is the
permit card carrying enough weight given it is the main trust signal?

## 4. Menu row density

Three attempts in a day (see `DESIGN_APPROACH.md` § Density). Current: 66pt
thumbnail, name, description, allergen chips, price pill, `min N`, photo count.
That is seven pieces of information per row. Too much? And is a photo-count
badge the right cue that a row opens a detail page, or should that be explicit?

**Screens:** `04`.

## 5. The map's warmth is applied as a multiply wash

Apple's daylight tiles run cool and green and fight amber, so a warm gradient is
multiplied over the whole map. It was too strong at first and got pulled back.
It may still be wrong in kind — a colour cast over someone else's cartography
rather than a designed surface. Is there a better move given MapKit's very
limited styling API?

**Screens:** `03`.

## 6. Two type families, no scale discipline

`Tokens.swift` defines roles (`screenTitle`, `dishNameCard`, `priceFigure`…) but
a lot of the feature code calls `.system(size: 13, weight: .semibold)` inline
instead. There are probably a dozen one-off sizes. Worth naming the real scale
and enforcing it — and if so, what should the scale be?

## 7. Dark mode is unverified

Tokens define dark variants. Almost nothing has been checked in dark mode, and
one bug already shipped from exactly this (an adaptive colour on a surface with
a hardcoded colour scheme, producing dark-on-dark text). Assume it is broken;
a pass would be valuable.

## 8. Accessibility beyond labels

VoiceOver labels are reasonably thorough. What has *not* been checked: Dynamic
Type at large sizes (several fixed-height controls will clip), contrast ratios
on amber-on-cream — the `$3 each` pill is `#5A3900` on `#FFF3DF`, which passes,
but the small-caps `COOKING · SINCE 11:51 AM` in `lampInk` is less certain — and
reduce-motion (the splash, the pin bob, and the burner all animate
unconditionally).

---

## Not looking for feedback on

- **Copy tone.** It is deliberate and has been worked over.
- **The no-logo decision.** Grounded in the research; happy to defend it.
- **Tab structure.** Recently settled from five tabs to four.
