# Screens

iPhone 17 Pro simulator, light mode, live production data.

| File | Screen | What to look at |
|---|---|---|
| `01-feed-cooking-now.png` | **Cooking feed** — the landing tab | The whole visual language in one place: amber count, sticker-squircle photos, 28pt cards with amber glow rings, price pills. Search is inline here rather than its own tab. |
| `02-search-bilingual-expansion.png` | Search, query `pork tamale` | The `también:` row — synonym expansion made visible, so a buyer sees *why* a Spanish listing matched an English query. The one piece of the old Search tab worth keeping. |
| `03-map-daylight-pins.png` | **Map** | Food-photo pins with cream rings and stems. The soft amber circles are ~400m privacy cells, not decoration — published coordinates are grid-snapped, and the halo is drawn at the fuzz radius so it can't imply an address. |
| `04-cook-profile.png` | **Cook profile** | The Polaroid portrait, the three stacked notice cards (see REVIEW_ASKS §3), and the menu rows (§4). Hero is a cook-chosen cover photo, falling back to the headline dish. |
| `05-dish-detail-gallery.png` | **Dish page** | Where the buying decision happens. Paged gallery, all four thumbnails visible, `1/4` counter. Both dish names shown. Minimum stated in words. Allergens never collapsed. |
| `06-kitchen-cook-side.png` | **Kitchen tab** (cook's own) | The burner dial — one tap on, one tap off. Everything here is warm because the kitchen is lit; the whole background cools when it's off. |
| `07-menu-builder-new-dish.png` | **New dish** (cook) | Four photo slots shown up front so capacity is visible. Allergens are *required* — Save stays disabled until they're answered. Live "Buyers see —" price preview. |
| `08-splash.png` | **Launch** | Kawaii dumpling, drawn entirely in SwiftUI shapes (`code/screens/SplashView.swift`) — no raster assets. |

## Not captured

- **Dark mode** — defined but unverified, see REVIEW_ASKS §7
- **Unconfirmed / dark kitchen states** — the decay ladder's later stages
- **Thread and order composer** — code included (`ThreadView`, `OrderSheet`)
- **Registration gate** — code included (`MessagingGateSheet`)
- **Live Activity** — Lock Screen card, device-only
