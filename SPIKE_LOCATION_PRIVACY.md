# Spike: location privacy

*M0 · run 2026-07-25 against PostGIS 16-3.4 · all numbers measured, not estimated*

**Question:** does the published location actually protect a cook's home address, or does it only look like it does?

**Answer:** it does now. It did not when the spike started. Three defects were found and fixed, and one claim in the design turned out to be false.

---

## The headline correction

> **What protects the address is lossiness, not secrecy.**

The design said the grid offset was keyed by a server-held secret, implying the secret was doing the protective work. It wasn't, for a reason that only shows up when you measure it: **published points lie on a lattice, so the grid phase is recoverable from any single published point.**

Measured — across 49 published points spanning ~3 km:

```
distinct_x_residues (mod cell) = 1
distinct_y_residues (mod cell) = 1
```

One residue. Every published point shares the same offset, so anyone with one point knows where the cell boundaries are. The secret only prevents precomputation against a globally fixed grid. It is **not** the guarantee.

The real guarantee is that **every home inside a cell publishes the identical point**, so the best possible recovery is "somewhere in this cell." That is worth stating plainly in the docs and the UI, because it is both true and sufficient — whereas "it's encrypted with a secret" is neither.

---

## Defects found

### 1. The secret was readable by any client role — *verified, not theorised*

The trigger read `current_setting('app.geo_secret')`. Custom GUCs set with `ALTER DATABASE … SET` are readable by any session:

```sql
set role authenticated;
select current_setting('app.geo_secret', true);
--  spike-secret-do-not-ship      ← returned the secret
```

Compounded by Postgres defaults: `public_point_for` was `EXECUTE`-able by `PUBLIC`, so a client could both read the secret and reproduce the whole scheme.

**Fixed.** Secret moved to an `app_secrets` table with no client grants; `EXECUTE` revoked from `public`, `anon`, `authenticated`; the trigger reads the secret inside `SECURITY DEFINER`.

### 2. The cell was never the size the comment claimed

Snapping happened in EPSG:3857, where a "500 m" cell is 500 m **only at the equator**:

| Latitude | Actual ground cell |
|---|---|
| Equator | 500.0 m |
| Covina, 34.09° | **414.1 m** |
| Seattle, 47.60° | **337.2 m** |

So the privacy guarantee silently varied by latitude, and was 17% smaller than documented in the launch market.

**Fixed.** Cell size is now specified in ground metres and divided by `cos(latitude)`, so it is constant. Verified across three latitudes:

| Location | Max displacement |
|---|---|
| Covina 34.09° | 271.3 m |
| Seattle 47.60° | 281.1 m |
| Equator 0.00° | 259.3 m |

(Max displacement is the cell half-diagonal, ≈ 283 m for a 400 m cell — the numbers land where the geometry says they should.)

### 3. The fix for #2 destroyed the privacy guarantee — *the most instructive defect here*

Compensating for Mercator distortion by dividing the cell by `cos(latitude)` made the cell size vary **continuously, per point**. Every home then had a marginally different grid, so no two homes shared one to snap to, and collisions collapsed:

| | Homes | Distinct published points | Homes per point |
|---|---:|---:|---:|
| Expected (1.6 × 1.5 km, 400 m cells) | 2500 | ~25 | ~100 |
| **Actual, after the cos(lat) "fix"** | 2500 | **248** | **10.1** |

The anonymity set had dropped by 10×, and **the test written for #2 still passed** — cell size *was* now constant, exactly as asserted. The property under test was true; it just wasn't the property that mattered.

This is the whole argument for spiking rather than reasoning. The code looked right, the fix was aimed at a real defect, and the test agreed with it.

**Fixed** by snapping in **UTM** (metric — one unit is one metre) rather than Web Mercator with a correction factor. Verified after the change: 100.0 homes per published point, max displacement 282.6 m, stable across every secret tried.

**Test changed too.** The collision check was a two-point comparison, which is flaky by construction: adjacent points may straddle a cell boundary depending on the secret-derived phase — it failed under one secret and passed under another during this spike. CI now asserts the aggregate **collapse ratio** over 2500 points, which is stable under every secret.

### 4. `unaccent()` is not `IMMUTABLE`, so the search column would not build

Not a privacy defect, but it blocked the schema entirely and would have surfaced on the first real deploy:

```
ERROR:  generation expression is not immutable
```

`unaccent(text)` is `STABLE` because the one-argument form resolves the default dictionary at call time. **Fixed** with an `immutable_unaccent()` wrapper over the explicit two-argument form (`001`).

---

## Properties now verified

| Property | Result | Why it matters |
|---|---|---|
| Deterministic across calls | ✅ | Defeats averaging: repeated reads can't be averaged back to the true point |
| Secret changes the grid | ✅ | Prevents precomputation against a fixed public lattice |
| Homes collapse onto shared points | ✅ **100.0 : 1** | **The actual privacy guarantee** |
| Max displacement | 282.6 m | Within the 400 m cell half-diagonal (~283 m); still a useful map pin |
| Displacement constant across latitudes | ✅ 265–283 m | Covina, Seattle, equator |
| Secret readable by clients | ❌ (was ✅) | Fixed |
| Fuzz function callable by clients | ❌ (was ✅) | Fixed |
| `kitchen_locations` readable by `anon` | ❌ | Holds |
| `kitchen_locations` readable by `authenticated` | ❌ | Holds |
| Policies on `kitchen_locations` | 0 | Protected by absence of grants, as designed |
| `kitchens.exact_point` exists | ❌ | Column never created |

---

## The limitation nobody should discover later

**The guarantee is geometric, not k-anonymous.** A 400 m cell is 0.16 km². In Covina (~2,800 people/km², ~880 households/km²) that is roughly **140 households** — a solid anonymity set.

In a low-density area the same cell might contain **three houses, or one.** The geometry is unchanged; the protection is nearly gone. A cook on a large rural lot who believes the map is protecting them would be wrong, and nothing in the current design tells them that.

This does not affect the SGV launch, and it is a real problem the first time someone signs up from a sparse area.

**Recommended before any expansion beyond dense suburbs:** compute an approximate household count per cell (census block groups) and either widen the cell until a minimum k is met, or refuse to publish a pin and show neighbourhood-only. Tracked as a follow-up, not fixed here — it needs a density source and a product decision about what a cook sees when their pin can't be shown.

---

## Reproducing

```bash
colima start                       # or any Docker runtime
docker run --rm -d --name lk-pg -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=litkitchen -p 55432:5432 postgis/postgis:16-3.4
# apply supabase/migrations/*.sql in order, then seed:
#   insert into app_secrets values ('geo_secret', '<secret>');
```

CI (`.github/workflows/ci.yml`) runs the invariants on every PR: the migrations must apply to an empty database, `kitchens.exact_point` must not exist, `kitchen_locations` must have no policies, the secret must not be client-readable, and the fuzz must stay deterministic and lossy.

## What this changes elsewhere

- `IMPLEMENTATION_PLAN.md` §2.004 — rewritten to v3, with the honest security claim
- `supabase/migrations/004` — `app_secrets`, ground-constant cell, revoked EXECUTE
- `supabase/migrations/001` — `immutable_unaccent()`
- `PRD.md` §7 should say the address is coarsened to a ~400 m cell, and **must not** claim the secret is what protects it
