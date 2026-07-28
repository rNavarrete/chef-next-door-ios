# Lit Kitchen — design review handoff

An iOS app for finding home cooks who are cooking **right now** in the San
Gabriel Valley. Native SwiftUI, iOS 18 floor, Supabase backend.

This directory is self-contained. Nothing here needs the repo to be readable.

```
screens/      8 screenshots, iPhone 17 Pro, live data
code/
  design-system/   tokens, shared components
  screens/         the feature views, as shipped
reference/    the brief and market research the design is accountable to
DESIGN_APPROACH.md   what the design is trying to do and why
REVIEW_ASKS.md       where a critique would be worth most
```

## What this is

A two-sided marketplace with an unusual constraint: it is asking someone to
**walk to a stranger's house and eat their food**. Almost every design decision
below is downstream of that, and of one market finding — trust is the scarcest
resource in this category, and polish reads as *less* trustworthy, not more.

## Read in this order

1. `DESIGN_APPROACH.md` — the thesis and the rules that follow from it
2. `screens/` — start with `01-feed-cooking-now.png`, the landing surface
3. `code/design-system/Tokens.swift` — the entire palette and type scale
4. `REVIEW_ASKS.md` — the specific questions

## Honest state of things

This is a working app against a live database, not a prototype. Everything in
the screenshots is real data flowing through real queries.

The visual language changed **significantly and recently**. It began as a
restrained editorial design — near-white cards, hairline borders, a dark "dusk"
map — and was deliberately pushed toward something warmer and more playful
("think Animal Crossing", "friendly and whimsical, we want to meet and care for
our neighbours"). Several surfaces were converted; some were not. Where you find
inconsistency, that is usually why, and saying so plainly is more useful than
guessing which was intended.

Screenshots are light mode. Dark mode is defined in the tokens and is
**substantially less exercised** — treat any dark-mode reasoning as unverified.
