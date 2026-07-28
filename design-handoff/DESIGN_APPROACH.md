# The design approach

## The thesis

Every other app in this space answers *what can I order*. This one answers
**who is cooking right now**. Availability is the product; the food is the
detail. That ordering shows up everywhere — on a feed card the availability line
sits *above* the dish name, and the dish name above the cook's name. Competitors
lead with cook and rating.

## The one hard colour rule

**Amber means heat. Blue means you can tap it.** Nothing else is amber.

A lit burner, a lamp dot, a price pill, a glow around a card — all amber, all
meaning "this is live". Every control is blue. There is no amber button anywhere
in the app, and that is deliberate: the moment a button is amber, amber stops
meaning heat.

This has been enforced against real pressure — a "Cooking" chip on a dish stayed
amber only while the kitchen was actually open, and goes neutral grey the moment
the burner is off (`code/screens/KitchenView.swift`, `badgeLabel`/`isHot`).

## Trust is the scarcest resource, and polish is suspicious

From the market research (`reference/RESEARCH-findings.md`): sellers in this
category have thin trust signals, and **stock-looking photos measured as a
distrust signal**. So:

- Cook photos are unretouched phone photos. The card is designed so a mediocre
  photo still looks fine in it — consistent crop, generous radius.
- There is deliberately **no logo slot** for cooks. A logo is the strongest
  available "this is a business" signal, in a product whose entire wedge is that
  this is a neighbour with a county permit number. Cooks get a *cover photo*
  instead — same camera, no branding.
- The permit card is prominent and cites the actual issuing agency.

## Honesty about state, as a design constraint

A kitchen's light decays: `lit` → `dimming` (3h) → `unconfirmed` (6h) → closed
(10h). The UI never asserts more than it knows. An unconfirmed kitchen gets a
full paragraph explaining that the cook may be busy or may be done, and telling
you to ask before you drive — the longest piece of copy on the screen, given the
most space (`04-cook-profile.png` shows the lit case; the unconfirmed case
replaces the note with that paragraph, full width).

Same instinct elsewhere: "we take no payment and charge no fees, you pay the
cook directly" appears on every profile. A dish with no allergens listed says so
explicitly rather than showing an empty space that could read as "none".

## Safety surfaces are never collapsed

Allergens are always visible — never a tooltip, never an accordion, on the row
and on the dish page. This is the one place where a UI shortcut is a safety bug.

## What changed recently, and why

The original brief specified a restrained editorial look and a **dark dusk map**
where lamps were the only warm thing on screen. That was coherent but read as
institutional. The direction shifted to warm and playful. Concretely:

| Was | Now | Reason |
|---|---|---|
| Dark map, forced `.colorScheme(.dark)` | Daylight map, warm multiply wash | Read as a city at night, not a neighbourhood |
| Small dot pins | Food-photo pins, cream ring, stem, bob | A pin should read as a *place*, not a data point |
| Hairline borders, 22pt radius | 2pt warm borders, 28pt radius | Cards should feel like objects you could pick up |
| SF Pro | SF Pro **Rounded** | See below — this was an accident |
| Circular avatar | Polaroid frame, tilted | "This is the face of the kitchen" |

### The typography was an accident worth knowing about

`LK.Typography.displayFamily` names `BricolageGrotesque`, but **no font file
ever shipped** and there is no `UIAppFonts` entry. Every "display" role — screen
titles, dish names, prices — had been silently falling back to stock SF Pro
since the tokens were written. The fallback is now explicitly SF Pro Rounded,
guarded by a `UIFont(name:)` check so dropping the real font in reverts it
automatically (`code/design-system/Tokens.swift`).

So the current rounded look is a *decision made after discovering an accident*,
not an original intent. It is very open to challenge.

## Density is contested

The dish rows on a cook profile have been through three passes in one day:
a full horizontal photo strip (~340pt per row, three dishes filled a screen),
then nothing at all (dishes without descriptions read as bare text), then a
single 66pt thumbnail with a photo-count badge. The current state is the third
attempt and has not settled.

## Component inventory

| Component | File | Notes |
|---|---|---|
| Palette, type, metrics | `design-system/Tokens.swift` | The whole system is one file |
| `GroupedCard`, `SectionHeader`, `FlowLayout` | `design-system/Components.swift` | |
| `DishPhoto` | `design-system/DishPhoto.swift` | Every food image; handles the no-photo case |
| `DishImageCache` | `design-system/DishImageCache.swift` | Decoded-image cache; `AsyncImage` flickered on map pins |
| `ProfileAvatar` | `Messages/ProfileAvatar.swift`* | Circle by default, squared for the Polaroid |
| `PhotoPickerTile` | `design-system/PhotoPickerTile.swift` | Cook-side upload |
| `BurnerDial` | `screens/BurnerDial.swift` | The cook's primary control |

\* not copied here — it is small and lives under Features/Messages.
