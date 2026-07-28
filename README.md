# Lit Kitchen

Native iOS app for finding home-cooked food from permitted home kitchens in the San Gabriel Valley. Cooks post a storefront once and flip it **on when they're cooking, off when they're done**. Buyers browse an open-now feed and a map, then get handed off to the cook's own channel. **The app takes no payment.**

**Status: M0 (scaffold).** The project builds and tests pass; no feature surfaces are implemented yet.

## Documents

| File | What it is |
|---|---|
| [`PRD.md`](PRD.md) | Problem, thesis, scope, domain model, v1 cut, risks, open questions |
| [`DESIGN_BRIEF.md`](DESIGN_BRIEF.md) | Design direction and the decay ladder spec |
| [`RESEARCH.md`](RESEARCH.md) | Market + regulatory research, with confidence levels |
| [`DESIGN_RESEARCH.md`](DESIGN_RESEARCH.md) | Competitive and UX patterns |
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | Stack, schema, iOS structure, milestones |
| [`COUNSEL_QUESTIONS.md`](COUNSEL_QUESTIONS.md) | **Open legal questions — M-1 gates cook onboarding** |

## Getting started

```bash
brew install xcodegen
xcodegen generate
open LitKitchen.xcodeproj
```

`project.yml` is the source of truth; `LitKitchen.xcodeproj` is generated and gitignored. Re-run `xcodegen generate` after adding files.

Build and test from the command line:

```bash
xcodebuild test -project LitKitchen.xcodeproj -scheme LitKitchen -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Layout

```
Sources/LitKitchen/
  App/          — entry point, root tab shell
  Core/
    Models/     — Cook, Kitchen, MenuItem, ServingSession, Claim
    Money/      — Price: the type that makes ambiguity unrepresentable
    Availability/ — FreshnessTier: the decay ladder
  DesignSystem/ — colour, type, metrics, glow tokens
Tests/LitKitchenTests/
supabase/
  migrations/   — ordered, numbered, applied in sequence by CI
  tests/        — pgTAP authorization matrix
```

## Three invariants that are not style preferences

**1. A price cannot exist without a unit.** `Price` has no initializer that omits it, and `perPieceCents` returns `nil` for trays and packages rather than fabricating a comparison. Both marketplaces we researched break on exactly this — a bare number with the unit missing, buried, or faked. See `PriceTests`.

**2. Exact addresses are unreachable, not merely policy-protected.** Coordinates live in `kitchen_locations`, which **no client role holds any grant on**. The only path in is `reveal_address()`, gated on a *cook-confirmed* claim, rate-limited per buyer, and audited on every call. `Kitchen` has no `exactPoint` property, so a UI mistake cannot leak a coordinate that was never decoded.

> A draft of this schema kept `exact_point` on `kitchens` behind an RLS policy that looked correct in isolation and was defeated by permissive-policy `OR` composition. CI now fails if that column reappears or if a policy is added to `kitchen_locations`.

**3. "Open" decays.** A kitchen lit at 9:40am is not the same offer at 4pm. `FreshnessTier` mirrors `freshness_of()` in SQL — **keep them in step**. Only activity that asserts *current service* resets the clock; clearing an old claim is bookkeeping, not cooking. Labels are always absolute clock times, never elapsed durations.

## Signing and entitlements

Team `HCEA5N57HT`. The App ID `com.litkitchen.app` carries **Push Notifications**
and **Sign In with Apple**; the signed device binary is expected to contain
`aps-environment` and `com.apple.developer.applesignin`.

> **Entitlements live in `project.yml`, never in `LitKitchen.entitlements`.**
> XcodeGen's `entitlements:` key *generates* that file from `properties` — it
> does not reference a hand-written one. Add a capability by editing the
> `.entitlements` file and the next `xcodegen generate` silently rewrites it as
> an empty `<dict/>`, and **the build still succeeds**, producing a binary with
> no entitlements at all. This cost an afternoon once; it will cost another.

A green build proves nothing here. The check that does:

```bash
codesign -d --entitlements :- \
  ~/Library/Developer/Xcode/DerivedData/LitKitchen-*/Build/Products/Debug-iphoneos/LitKitchen.app
```

The **simulator cannot verify either capability**. Simulator builds are ad-hoc
signed with empty entitlements (`codesign -dv` reports `TeamIdentifier=not
set`), so `Activity.request(pushType: .token)` fails there with the same
`PermissionsError Code=3` it gives on a completely unconfigured project. Only a
device build distinguishes the two.

## Validating the migrations

Requires Docker.

```bash
docker run --rm -d --name lk-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=litkitchen -p 5432:5432 postgis/postgis:16-3.4
for f in supabase/migrations/*.sql; do psql -h localhost -U postgres -d litkitchen -v ON_ERROR_STOP=1 -f "$f"; done
```

CI does this on every PR, plus the location invariants. See `.github/workflows/ci.yml`.

### Test permissions from the role, never as the owner

Applying the migrations and calling the functions proves the *logic*. It proves
nothing at all about who is allowed to call them, because **the database owner
bypasses both grants and RLS**. A test that connects as `postgres` and gets the
right answer has demonstrated that `postgres` can do it — which was never in
question.

Two real bugs hid behind exactly this, on the same afternoon:

- `refresh_permit_registry` was revoked from `public` and granted to nobody, so
  `service_role` — which was relying on the PUBLIC default — could not execute
  the one function it exists to run. Every owner-run test passed.
- `cooks` had `grant update … to authenticated` with owner-only RLS. Correct
  about *which row*, silent about *which columns*, so any cook could `PATCH`
  themselves to `permit_status = 'verified'` with an invented permit number.
  The entire permit check was optional and nothing in the suite noticed.

So: wrap permission assertions in a transaction and switch role.

```sql
begin;
set local role authenticated;
set local request.jwt.claim.sub = '<some uuid>';
-- ... the thing that should be refused ...
commit;
```

`set local` **outside a transaction is a no-op** — psql prints a warning that is
easy to scroll past, and the statements then run as the owner and "pass". If a
negative test has never actually failed, assume it is vacuous until you have
watched it fail.

The CI stub creates `anon`, `authenticated` and `service_role` for this reason.

## Before real cooks are onboarded

`COUNSEL_QUESTIONS.md` **M-1 is a gate.** The IFSI classification is genuinely unsettled — the statutory definition describes a platform that *derives revenue*, and we charge nothing — so the compliance regime that applies is an open question, not a formality. The build can proceed; recruiting permitted cooks should not.
