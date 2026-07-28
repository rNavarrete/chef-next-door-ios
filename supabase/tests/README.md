# Database tests

| file | status |
|---|---|
| `messaging_gate.sql` | **runs, 40 assertions, green** |
| `authorization_matrix.sql` | never run — a specification, not coverage |

## `messaging_gate.sql`

Covers the 040 registration gate, the 041 profile it implies, and who may see a
buyer's identity. Needs no pgTAP and no external fixtures — it carries its own,
resets them on entry, and is re-runnable:

```sh
psql -d lk_test -f <the stub in .github/workflows/ci.yml>
for f in supabase/migrations/*.sql; do psql -d lk_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d lk_test -v ON_ERROR_STOP=1 -f supabase/tests/messaging_gate.sql
```

Every assertion runs as the `authenticated` or `anon` role — see *The failure
mode these exist to catch* below, which is the reason it is written that way.

## Status: `authorization_matrix.sql` has never been run

It is a **specification, not passing coverage.** It needs pgTAP installed and a fixtures file that does not exist yet, and it must not be counted as verification until both are true and it runs green in CI.

Written down because a test file that looks like coverage and isn't is worse than no file — it makes an unverified area look checked.

## What *is* verified today

`.github/workflows/ci.yml` runs these on every PR, against a real PostGIS database, and they pass:

- All migrations apply in order to an **empty** database
- `kitchens.exact_point` does not exist
- `kitchen_locations` has zero policies (protected by absent grants)
- `app_secrets` is not readable by `anon` or `authenticated`
- `public_point_for` is not executable by `anon` or `authenticated`
- Fuzzing is deterministic
- Homes collapse onto shared published points (aggregate ratio ≥ 20:1; measures ~100:1)
- No published point moves further than the cell half-diagonal, at any latitude

That covers the location-privacy invariants. It does **not** cover the role × claim-status authorization matrix, which is what `authorization_matrix.sql` is for.

## Finishing it

1. `create extension pgtap;` in the test database
2. Write `fixtures.sql` — a cook, kitchen, open session, and claims in each status, with the ids exported as `test.*` settings
3. Add a CI step running `pg_prove` against `supabase/tests/`
4. Only then treat the matrix as coverage

## One lesson worth keeping

The collision assertion was originally a two-point comparison: take two homes ~14 m apart, assert they publish the same point. **It is flaky by construction** — adjacent points straddle a cell boundary depending on the secret-derived grid phase, so it failed under one secret and passed under another during the spike.

Aggregate properties over many points are stable; single-pair geometric assertions are not. The same trap applies to any future test asserting "these two things land in the same bucket."


## The failure mode these exist to catch

Grants and RLS are invisible to the owner. Any test that connects as `postgres`
— which is what `psql -U postgres` and every migration run does — bypasses both
and will happily report success on a permission that nobody actually has, or
miss one that everybody has.

Both permission bugs found in this schema so far were of that kind, and both
were found by a human poking at the live API rather than by a test:

| bug | what the owner-run test said |
|---|---|
| `refresh_permit_registry` executable by nobody | passed |
| a cook could set their own `permit_status = 'verified'` | passed |

Any assertion of the form "role X cannot do Y" has to run as X:

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '...';
  -- assert the refusal
commit;
```

And `set local` outside a transaction silently does nothing.
