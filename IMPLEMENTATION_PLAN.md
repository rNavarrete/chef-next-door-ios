# Lit Kitchen — Implementation Plan

*Companion to [`PRD.md`](PRD.md) · iOS, Swift 6 / SwiftUI*

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Client | **SwiftUI, iOS 18+** | Native `Map` with annotations + clustering; `Observable` macro. **The floor is 18, not 17:** WidgetKit Controls — the Control Center / Lock Screen burner toggle that `PRD.md` §6 makes the cook's most-used affordance — are iOS 18 (WWDC24). An iOS 17 floor would have silently cut the single strongest native-vs-web argument. If 18 proves too aggressive for reach, the control must come out of the thesis, not ship broken |
| Concurrency | **Swift 6 strict** | New project — no legacy to migrate. Cheap now, expensive later |
| Backend | **Supabase** (Postgres + PostGIS + Auth + Storage + Realtime) | PostGIS is the deciding factor — radius/bbox queries are first-class. One vendor covers auth, DB, files, push triggers |
| Auth | **Sign in with Apple** + phone OTP | SIWA required by App Store when any social login is present; phone verification is the real trust signal for cooks |
| Maps | **MapKit** | Free, native, no key management. Mapbox only if we later need custom styling |
| Search | **Postgres FTS** (`tsvector`, `unaccent`, `pg_trgm`) + synonym table | Bilingual is a schema requirement, not a library choice (§3) |
| Images | Supabase Storage + on-the-fly transform | Photo-first UI; must not ship full-res over cellular |
| Push | APNs via Supabase Edge Function on `serving_status` → `serving` | "Maria is cooking today" is the retention loop |
| Live Activity | **ActivityKit**, updated via the ActivityKit APNs push type (distinct from standard remote push) | Active-claim card on Lock Screen/Dynamic Island — cook, items, address, tap-to-contact. Reframed from a countdown (no fixed window exists now) to a persistent handoff card; still the interaction a web-shell competitor can't build (`DESIGN_RESEARCH.md` §6) |

**Not chosen:** Firebase (weak geo querying — geohash workarounds vs. real PostGIS); SwiftData (still rough for server-backed sync; we cache with a thin repository layer instead).

## 2. Data model

The schema encodes the research findings. Three constraints do most of the work: **price is never a bare number**, **availability is explicit state a cook controls**, and **exact locations are not reachable by any client role, ever**.

> **Ordered migrations, not a sketch.** Everything below is numbered in dependency order because an earlier draft of this section did not run: enums were used before creation, triggers referenced tables that did not exist yet, and a function was marked `IMMUTABLE` while calling `now()`. Each block is one migration file. **CI must apply them in order against an empty database on every PR** — that is the test that would have caught all of it.

### 001 — extensions and enums

Enums first. Nothing references a type before it exists.

```sql
create extension if not exists postgis;
create extension if not exists unaccent;
create extension if not exists pg_trgm;
create extension if not exists pgcrypto;   -- hmac() for location fuzzing

create type contact_method      as enum ('sms','whatsapp','instagram');
create type permit_status       as enum ('none','pending','verified','rejected','expired');
create type price_unit          as enum ('each','half_dozen','dozen','loaf','jar','tray','weekly_package','per_person');
create type food_category_type  as enum ('mehko_meal','cottage_food');
create type serving_status      as enum ('closed','serving','sold_out');
create type freshness_tier      as enum ('lit','dimming','unconfirmed','out');
create type claim_status        as enum ('pending','confirmed','completed','no_show','cancelled');
```

### 002 — cooks

```sql
create table cooks (
  id              uuid primary key references auth.users(id) on delete cascade,
  display_name    text not null,              -- independent of legal name (PRD §7)
  bio             text,
  avatar_path     text,
  instagram       text,
  contact_method  contact_method not null default 'sms',
  contact_value   text not null,              -- never exposed pre-claim
  phone_verified  boolean not null default false,

  permit_status   permit_status not null default 'none',
  permit_kind     text,                       -- 'mehko' | 'cfo_class_a' | 'cfo_class_b' | 'food_handler'
  permit_number   text,                       -- PUBLIC by design — the platform must expose a dedicated
                                               -- permit-number field per cook (PRD §8). Deliberately NOT
                                               -- restricted the way location is.
  permit_agency_id uuid,                      -- FK added in 003. Enforcement agency, NOT city (PRD §8)
  permit_expires  date,

  serving_status  serving_status not null default 'closed',
  serving_note    text,                       -- "til 6pm", "last batch"
  typical_hours   jsonb,                      -- advisory only: "usually Sat mornings"

  created_at      timestamptz not null default now()
);
```

Note what is **not** here anymore: `serving_opened_at` and `last_confirmed_at` moved to `serving_sessions` (005), and `complaint_count_calendar_year` moved to a real event log (008). Both were mutable counters on a row that gets overwritten every time a cook opens — no history, so the freshness metrics in `PRD.md` §9 were literally uncomputable.

### 003 — enforcement agencies and kitchens (public geometry only)

Jurisdiction is modeled as the **enforcement agency**, not a city string. Pasadena, Long Beach, and Vernon are carve-outs because they run their own health departments, not because they are cities — a city column encodes the coincidence instead of the rule.

```sql
create table enforcement_agencies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,       -- "LA County Dept. of Public Health, Environmental Health"
  county        text not null,
  mehko_opted_in boolean not null default false,
  cottage_food_ok boolean not null default true,
  notes         text
);

alter table cooks
  add constraint cooks_agency_fk
  foreign key (permit_agency_id) references enforcement_agencies(id);

-- Kitchens hold ONLY publishable geometry. No exact point lives here.
create table kitchens (
  id            uuid primary key default gen_random_uuid(),
  cook_id       uuid not null references cooks(id) on delete cascade,
  public_point  geography(Point,4326) not null,  -- grid-snapped, see 004
  neighborhood  text not null,
  city          text not null,
  agency_id     uuid not null references enforcement_agencies(id)
);
create index on kitchens using gist (public_point);
```

### 004 — exact locations: a separate table no client can reach

The previous design kept `exact_point` on `kitchens` and relied on RLS plus a view. **That does not work.** Postgres combines permissive policies with `OR`, so a `USING (true)` read policy unions with the claim-gated policy and wins; and RLS is row-level, so it would not have hidden the column even if the policies had been written correctly. A view protects nothing while the client can still select the base table.

The fix is structural, not policy-shaped: exact coordinates live in their own table, **no client role is granted any privilege on it**, and the only path in is a `SECURITY DEFINER` function that checks authorization and writes an audit row.

```sql
create table kitchen_locations (
  kitchen_id   uuid primary key references kitchens(id) on delete cascade,
  exact_point  geography(Point,4326) not null,
  street       text not null,
  city         text not null,
  postal_code  text not null,
  updated_at   timestamptz not null default now()
);

-- The whole security model in two statements. Not a policy — an absence of grants.
revoke all on kitchen_locations from public, authenticated, anon;
alter table kitchen_locations enable row level security;   -- belt and braces; no policy is ever added
```

**Grid-snapped fuzzing.** → **Implemented in [`supabase/migrations/004_kitchen_locations.sql`](supabase/migrations/004_kitchen_locations.sql). That file is the source of truth; results in [`SPIKE_LOCATION_PRIVACY.md`](SPIKE_LOCATION_PRIVACY.md).**

*The SQL that used to be duplicated here has been removed on purpose.* It drifted from the migration within a day — the plan still described Web Mercator and a GUC-held secret after both had been replaced — and a plan that contradicts the code is worse than one that points at it.

**What the design commits to** (intent belongs here; implementation belongs in the migration):

- Exact coordinates are **unreachable by any client role**, protected by an absence of grants rather than by policy wording.
- The published point is **deterministic** (no averaging attack) and **lossy** (every home in a cell publishes the same point). The lossiness is the guarantee; the secret only prevents precomputation against a fixed public grid.
- Snapping happens in a **metric projection (UTM)**, so the cell is the size it claims to be at every latitude.
- The secret lives in a table with no client grants, and the fuzz function is not client-executable.
- Every pre-claim distance, radius filter, and ranking calculation uses `public_point` **only** — a distance computed from the exact point leaks it through result ordering even when the coordinate is never returned.

**Scope, settled:** a claiming buyer receives the exact address. That is the product working. The coarsening exists to prevent bulk harvesting by people who never claim. No further privacy work is planned.

> Verified, not assumed — see the spike. Four defects were found here, including one introduced *by the fix for another one*, which passed its own test while silently collapsing the anonymity set 10×. The regression checks now live in CI.

### 005 — serving sessions

An append-only record of *a period of service*. This is not the batch/drop object we removed: **no future scheduling, no declared capacity, no pickup window**. It records what happened, not what is planned. Without it there is no history — claims, reviews, the same-day purchaser list, and every freshness metric had nothing durable to attach to.

```sql
create table serving_sessions (
  id                uuid primary key default gen_random_uuid(),
  cook_id           uuid not null references cooks(id) on delete cascade,
  kitchen_id        uuid not null references kitchens(id),
  opened_at         timestamptz not null default now(),   -- DISPLAYED: "Cooking · since 9:40 am"
  last_confirmed_at timestamptz not null default now(),   -- DRIVES the decay tier
  closed_at         timestamptz,
  closed_by         text,                                  -- 'cook' | 'auto_8pm' | 'admin'
  status            serving_status not null default 'serving'
);

-- At most one open session per cook.
create unique index on serving_sessions (cook_id) where closed_at is null;
create index on serving_sessions (last_confirmed_at) where closed_at is null;
create index on serving_sessions (cook_id, opened_at);
```

Opening and closing are atomic procedures, never client-side field writes:

```sql
create or replace function open_kitchen(p_kitchen uuid, p_note text default null)
returns uuid language plpgsql security definer as $$ ... $$;

create or replace function close_kitchen(p_reason text default 'cook')
returns void language plpgsql security definer as $$ ... $$;
```

### 006 — menu items

```sql
create table menu_items (
  id             uuid primary key default gen_random_uuid(),
  cook_id        uuid not null references cooks(id) on delete cascade,
  name_en        text,
  name_es        text,
  description    text,
  category       text not null,
  category_type  food_category_type not null,
  allergens      text[] not null default '{}',   -- mandatory (PRD §7)
  is_available   boolean not null default true,

  amount_cents   integer not null check (amount_cents > 0),
  unit           price_unit not null,
  min_quantity   integer not null default 1 check (min_quantity > 0),

  search_doc     tsvector generated always as (
      setweight(to_tsvector('english', unaccent(coalesce(name_en,''))), 'A')
   || setweight(to_tsvector('spanish', unaccent(coalesce(name_es,''))), 'A')
   || setweight(to_tsvector('simple',  unaccent(coalesce(description,''))), 'C')
  ) stored,

  check (name_en is not null or name_es is not null)
);
create index on menu_items using gin (search_doc);

create table dish_synonyms (
  term      text not null,
  canonical text not null,
  primary key (term, canonical)
);
```

### 007 — the decay ladder

```sql
-- STABLE, not IMMUTABLE: it reads now(). IMMUTABLE would let the planner
-- cache or inline it wrongly.
create or replace function freshness_of(last_confirmed timestamptz, closed timestamptz)
returns freshness_tier language sql stable as $$
  select case
    when closed is not null                          then 'out'::freshness_tier
    when now() - last_confirmed < interval '4 hours' then 'lit'
    when now() - last_confirmed < interval '6 hours' then 'dimming'
    else 'unconfirmed'
  end;
$$;
```

**Which actions count as confirmation — narrowed deliberately.** The earlier rule bumped the clock on *any* cook activity, which meant marking a three-day-old claim "picked up" at 9pm would relight a kitchen that went cold at noon. That is the exact failure the decay ladder exists to prevent, wired in backwards.

Only actions that **necessarily assert service right now** confirm a session:

| Action | Confirms? | Why |
|---|---|---|
| Explicit "still serving" (nudge reply, app open on the cook tab) | **Yes** | Direct assertion |
| Flipping a menu item sold out / back on | **Yes** | Only meaningful about today's cooking |
| Answering a claim created **during this session** | **Yes** | Responding to live demand |
| Editing the serving note | **Yes** | A statement about today |
| Answering or completing a claim from a **prior** session | **No** | Bookkeeping, not cooking |
| Editing menu prices, photos, bio, permit docs | **No** | Admin, often done while closed |

```sql
create or replace function confirm_session(p_cook uuid) returns void
language sql security definer as $$
  update serving_sessions set last_confirmed_at = now()
   where cook_id = p_cook and closed_at is null;
$$;

create or replace function touch_on_availability() returns trigger as $$
begin
  perform confirm_session(new.cook_id);
  return new;
end $$ language plpgsql;

create trigger menu_availability_confirms
  after update of is_available on menu_items
  for each row when (old.is_available is distinct from new.is_available)
  execute function touch_on_availability();
```

Ranking, everywhere: `order by freshness_of(...), distance` — `unconfirmed` never outranks a confirmed cook and is never the first feed row (`PRD.md` §5).

### 008 — claims, disclosure audit, complaints, reviews

A claim is a **warm intro, not a purchase** (`PRD.md` §6). The naming reflects that, and `PRD.md` §8 no longer claims these records alone satisfy the statutory purchaser-list duty — see `COUNSEL_QUESTIONS.md` Q3.

```sql
create table claims (
  id                 uuid primary key default gen_random_uuid(),
  cook_id            uuid not null references cooks(id) on delete cascade,
  serving_session_id uuid not null references serving_sessions(id),  -- WHICH service period
  buyer_id           uuid not null references auth.users(id),
  status             claim_status not null default 'pending',
  note               text,
  created_at         timestamptz not null default now()
);
create index on claims (cook_id, created_at);
create index on claims (serving_session_id);

create table claim_items (
  claim_id      uuid references claims(id) on delete cascade,
  menu_item_id  uuid references menu_items(id),
  quantity      integer not null check (quantity > 0),
  primary key (claim_id, menu_item_id)
);

-- Every address disclosure is logged. This is the audit trail for the
-- harvesting vector described in PRD §7.
create table address_disclosures (
  id           uuid primary key default gen_random_uuid(),
  claim_id     uuid not null references claims(id),
  kitchen_id   uuid not null references kitchens(id),
  buyer_id     uuid not null references auth.users(id),
  disclosed_at timestamptz not null default now()
);
create index on address_disclosures (buyer_id, disclosed_at);

create table complaints (
  id           uuid primary key default gen_random_uuid(),
  cook_id      uuid not null references cooks(id),
  claim_id     uuid references claims(id),
  reporter_id  uuid references auth.users(id),
  kind         text not null,          -- 'food_safety' | 'hygiene' | 'other'
  body         text,
  created_at   timestamptz not null default now(),
  escalated_at timestamptz             -- set when submitted to the enforcement agency
);
create index on complaints (cook_id, created_at);

create table reviews (
  id         uuid primary key default gen_random_uuid(),
  claim_id   uuid not null unique references claims(id),
  rating     smallint not null check (rating between 1 and 5),
  body       text,
  created_at timestamptz not null default now()
);
```

### 009 — address disclosure: the only way out of `kitchen_locations`

Authorization is **cook-controlled**. A buyer cannot promote their own claim to `confirmed`; only the cook (or an admin) can. Rate limits and the audit row are inside the function, so there is no path that skips them.

```sql
create or replace function reveal_address(p_claim uuid)
returns table (street text, city text, postal_code text, point geography)
language plpgsql security definer as $$
declare v_kitchen uuid; v_recent int;
begin
  -- 1. The caller must own the claim, and the COOK must have confirmed it.
  select ss.kitchen_id into v_kitchen
    from claims c
    join serving_sessions ss on ss.id = c.serving_session_id
   where c.id = p_claim
     and c.buyer_id = auth.uid()
     and c.status in ('confirmed','completed');
  if v_kitchen is null then
    raise exception 'not authorized';
  end if;

  -- 2. Rate limit: cap distinct kitchens a buyer can unlock per day.
  select count(distinct kitchen_id) into v_recent
    from address_disclosures
   where buyer_id = auth.uid() and disclosed_at > now() - interval '24 hours';
  if v_recent >= 5 then
    raise exception 'daily address limit reached';
  end if;

  -- 3. Log, then release.
  insert into address_disclosures (claim_id, kitchen_id, buyer_id)
  values (p_claim, v_kitchen, auth.uid());

  return query
    select kl.street, kl.city, kl.postal_code, kl.exact_point
      from kitchen_locations kl where kl.kitchen_id = v_kitchen;
end $$;

revoke all on function reveal_address(uuid) from public, anon;
grant execute on function reveal_address(uuid) to authenticated;
```

Additional gates, enforced above the database: **phone-verified buyers only** may claim; a per-buyer claim rate limit independent of disclosures; and an admin alert when any buyer's disclosure count spikes. Claiming is deliberately low-friction, and low-friction plus home addresses is a harvesting pipeline unless it is bounded.

### 010 — RLS on everything client-facing

`kitchen_locations` is absent from this list on purpose: it has no policies because it has no grants.

```sql
alter table kitchens             enable row level security;
alter table claims               enable row level security;
alter table address_disclosures  enable row level security;
alter table serving_sessions     enable row level security;

-- kitchens carries only publishable geometry, so a broad read is safe here
-- in a way it explicitly was not when exact_point lived on this table.
create policy kitchens_read on kitchens for select using (true);

create policy claims_own on claims for select
  using (buyer_id = auth.uid() or cook_id = auth.uid());

-- Buyers may create a claim but may NEVER set or change its status.
create policy claims_insert on claims for insert
  with check (buyer_id = auth.uid() and status = 'pending');
create policy claims_cook_updates on claims for update
  using (cook_id = auth.uid());

create policy disclosures_own on address_disclosures for select
  using (buyer_id = auth.uid());
```

**Test matrix, written before the feature.** Every combination of {anon, buyer-no-claim, buyer-pending-claim, buyer-confirmed-claim, other cook, owning cook, admin} × {`kitchens`, `kitchen_locations`, `reveal_address`, `claims` update}. A single passing case is not evidence; the leak we already shipped in draft was a policy that looked correct in isolation and was defeated by `OR` composition.
## 3. Bilingual search

The research finding that titles mix languages mid-string means we cannot pick a language per query. Approach:

1. Normalize query with `unaccent`
2. Expand through `dish_synonyms` (bidirectional)
3. Query `search_doc` with both `english` and `spanish` configs OR'd
4. Fall back to `pg_trgm` similarity for misspellings (`biria` → `birria`, observed in real listings)

Exposed as one RPC so the client stays dumb:

```sql
create function search_cooks(
  q text, lat float8, lon float8, radius_m int, open_only boolean default true
) returns setof cook_result ...
-- Joins serving_sessions for the open session (closed_at is null).
-- ORDER BY freshness_of(ss.last_confirmed_at, ss.closed_at), then distance.
-- Results group as "COOKING RIGHT NOW · n" then "DARK RIGHT NOW · n"; the synonym
-- expansion that produced the match is returned alongside, so the UI can show
-- buyers *why* a result matched ("también: tamales · tamalito · pork tamale").
```

> **Distance must be computed from `kitchens.public_point` only.** Sorting or filtering by a distance derived from the exact point leaks that point through result ordering, even though the coordinate itself is never returned. This is a correctness requirement of the privacy model (§2.004), not an optimization.

## 4. iOS app structure

```
LitKitchen/
├── App/                  LitKitchenApp.swift, AppRouter, DI container
├── Core/
│   ├── Network/          SupabaseClient wrapper, typed endpoints
│   ├── Models/           Cook, Kitchen, MenuItem, ServingSession, Claim  (Codable, Sendable)
│   ├── Money/            Price.swift — amount + unit + minimum, formatting
│   └── Location/         LocationService, geo helpers
├── Features/
│   ├── Discover/         MapView, CookAnnotation, clustering
│   ├── OpenNow/          Serving-now feed, sorted by proximity
│   ├── Search/           Query UI, filters
│   ├── CookDetail/       Menu, photos, price, availability, claim CTA
│   ├── CookProfile/      Story, badges, follow
│   ├── Kitchen/          Cook-side: menu builder, availability toggle, claim inbox
│   └── Trust/            Permit upload, review flow
└── DesignSystem/         Typography, color, components
```

**Pattern:** MVVM with `@Observable` view models, a repository per feature, protocol-backed for testing. No third-party architecture framework.

### The Price type — enforce the core constraint in Swift too

```swift
struct Price: Codable, Sendable, Equatable {
    let amountCents: Int
    let unit: PriceUnit
    let minQuantity: Int

    /// Comparable per-piece price where the unit permits it. `nil` for
    /// trays and packages, which are genuinely not per-piece comparable.
    var perPieceCents: Int? {
        switch unit {
        case .each:           amountCents
        case .halfDozen:      amountCents / 6
        case .dozen:          amountCents / 12
        case .loaf, .jar:     amountCents
        case .tray, .weeklyPackage, .perPerson: nil
        }
    }

    var display: String {  // "$3 each" · "$36/dozen ($3 ea)" · "$110/week"
        ...
    }
}
```

There is no `init(amountCents:)` without a unit. The type system refuses to represent the ambiguity that broke both marketplaces.

### Map surface

`Map` with `MapCircle`-backed clustering at low zoom, `Annotation` per serving cook above the cluster threshold. Pins render the fuzzed `public_point` only — the exact point is not present in the decoded model at all pre-claim, so it cannot leak through a UI mistake. Closed cooks are either filtered out or rendered visibly dimmed, never as equal-weight pins.

```swift
struct KitchenPublic: Decodable, Sendable {
    let id: UUID
    let publicPoint: Coordinate
    let neighborhood: String
    // no exactPoint — deliberately absent from this type
}
```

## 5. Milestones

| # | Milestone | Scope | Est. |
|---|---|---|---|
| **M-1** | **Legal gate** | Written counsel answers to `COUNSEL_QUESTIONS.md` — IFSI classification given $0 revenue, agency-jurisdiction rule, claim-vs-purchase evidence. **Blocks any MEHKO-cook onboarding**, not the build | 2–6 wk elapsed, mostly waiting |
| **M0** | Foundations | Xcode project, Swift 6 strict, Supabase project, **ordered migrations run from empty DB in CI**, the RLS/authorization test matrix (§2.010), SIWA, Live Activity spike (ActivityKit push tokens, physical device), **location-privacy spike** (grid-snap properties, inversion attempt, secret handling) | 2.5 wk |
| **M1** | Cook side | Onboarding, menu builder w/ structured price, open/close procedures + per-item sold-out | 1.5 wk |
| **M2** | Discovery | Map, open-now feed, bilingual search RPC + synonym seed, filters | 2.5 wk |
| **M3** | Claim & handoff | Claim flow, cook-controlled confirmation, `reveal_address` with rate limits + audit, contact handoff, claim inbox, Live Activity for the active claim. **Not done until a server-sent `apns-push-type: liveactivity` payload is verified updating a running activity on a physical device** — the simulator cannot test it (`SPIKE_LIVE_ACTIVITY.md`) | 2 wk |
| **M4** | Trust | Permit upload + admin review (**enforcement-agency** check, not city), public permit-number field, badges, renewal reminders at 60/30/7, reviews, report/block, complaint log + escalation admin view, "Made in a Home Kitchen" auto-render, insurance & fees disclosure screen | 2 wk |
| **M5** | Push & decay ladder | APNs on cook-opens, follow-a-cook, four-tier decay presentation, ~8h nudge with Lock Screen actions, 8pm auto-off, empty states, Dark Mode, accessibility, Spanish localization | 2 wk |
| **M5.5** | **Operational floor** | Abuse controls (claim/disclosure rate limits, block lists), analytics event dictionary + instrumentation, support/admin tooling, incident runbook, security review of the location path | 2 wk |
| **M6** | Closed beta | Hand-recruited cooks, launched at a density that produces a usable "open now" — see `PRD.md` §11.9 | 2 wk |
| **M7** | IFSI registration (**if classified as one**) | Mail CDPH Form 9144 (plan mail turnaround); insurance + service-fee disclosure; both complaint-escalation paths wired to real admin actions; "catering" content filter on `mehko_meal` | Gated by M-1 |

**~16.5 weeks to closed beta** for one experienced iOS engineer plus part-time backend — revised up from ~12.5 after review. The additions are not scope creep: M0 grew for migrations-in-CI and the location spike, M5.5 is the operational floor the original plan omitted entirely (abuse controls, analytics, support tooling, security review), and M-1 is elapsed calendar time that can overlap the build but **cannot overlap onboarding real MEHKO cooks**.

M6 is recruiting, not building; start it during M2.

### Sequencing note

M1 before M2 is deliberate and worth defending: we need real cooks entering real menus before we design discovery around them. Building the buyer surface first means designing against imagined data — which, given how badly both marketplaces model this domain, is exactly the failure mode to avoid.

## 6. Technical risks

| Risk | Mitigation |
|---|---|
| **Exact-location leak** | Structural, not policy-shaped: exact coordinates live in `kitchen_locations` with **no client grants at all**, reachable only via `reveal_address()` (§2.004, §2.009). Grid-snapped public points are non-invertible. Full role × table test matrix written before the feature; pen-test before beta. *A draft of this plan shipped a policy that looked correct in isolation and was defeated by permissive-policy `OR` composition — assume the next one is wrong too until the matrix passes* |
| **Location inversion via the fuzz function** | The public point must not be derivable from public data. Offset is keyed by a server-held secret and snapped to a ~500 m grid, so the best recovery is a cell. All pre-claim distance/ranking uses `public_point` only — ordering by true distance leaks the point without ever returning it |
| **Address harvesting via cheap claims** | Claims are deliberately zero-friction and each one discloses a home address. Bounded by: cook-controlled confirmation (buyers cannot promote their own claim), phone-verified buyers only, ≤5 distinct kitchens unlocked per buyer per day, every disclosure logged to `address_disclosures`, admin alert on spikes |
| Cooks abandon the structured menu builder as too much work | Aggressive defaults, photo-first entry; menu is entered **once** and reused indefinitely — the recurring action is a single availability toggle |
| **Stale availability** — a cook forgets to flip to closed, buyers arrive at a cold kitchen. The single biggest failure mode of this model, and it did not exist under scheduled batches | **The decay ladder** (PRD §5) over `serving_sessions`. Only actions that *assert current service* confirm a session (§2.007) — an earlier draft bumped on any cook activity, so clearing an old claim at 9pm would have relit a kitchen cold since noon. `unconfirmed` never outranks confirmed; ~8h nudge; 8pm auto-off. **Absolute clock times only** |
| Bilingual search quality is mediocre at launch | Synonym table is hand-seeded from real listing vocabulary in `RESEARCH.md`; instrument zero-result queries from day one |
| PostGIS + Supabase RPC performance at zoom-out | Bbox queries with a cap; server-side clustering if pin count exceeds ~500 |
| Swift 6 strict concurrency slows early velocity | Accepted — cheaper now than a migration later |
| Push notification fatigue | Only followed cooks, only on publish, hard daily cap |
| A cook silently exceeds the MEHKO 30/day–90/week cap | Advisory count over `claim_items` joined to the session (no hard block, per confirmed decision). **Structurally a partial count** — no in-app checkout, no declared capacity, and DM orders are invisible to us. Present as "at least N claimed via Lit Kitchen," never as a total |
| Live Activity push updates require a **signing team** (`aps-environment` entitlement) — without one `Activity.request(pushType:.token)` fails outright and *nothing renders* | Confirmed in the M0 spike. Mitigated by falling back to `pushType: nil` so the card still works locally, with the degraded mode recorded rather than silent. **Real fix is a signing team**; the push path stays unverified until then |
| A cook's decay-ladder change won't reach a buyer already walking to the door without push | This is what push updates are *for*. Local-only is a genuine degradation, not an equivalent — call it out in M3 acceptance |
| First Live Activity triggers a system consent prompt; `areActivitiesEnabled` returning true is **not** consent | Fire the first activity attached to a real claim (good context to be asked in), and handle a decline without breaking the claim flow |
| Control Center toggle cannot express the designed hold-to-close | Open decision (`SPIKE_LIVE_ACTIVITY.md` Finding 4). Leaning open-only from the control, since accidental opens are harmless and accidental closes cost a cook their afternoon |
| **Claims are not purchases, but compliance workflows assume they are** | Reviews, complaint counting, and the same-day purchaser list all read from `claims`, which records "opened a text," not "bought food." Mitigation is honesty plus evidence: explicit handoff confirmation from both sides where we can get it, and `COUNSEL_QUESTIONS.md` Q3 to establish what actually satisfies "purchase through the platform." Until answered, `PRD.md` §8 must not assert these duties are satisfiable from `claims` alone |

## 7. Immediate next steps

1. **Send `COUNSEL_QUESTIONS.md` to a California food-law attorney.** This is now M-1 and it gates MEHKO-cook onboarding, not the build. Longest lead time of anything here — start it first, today
2. ~~Location-privacy spike~~ — **done and closed**, see `SPIKE_LOCATION_PRIVACY.md`. Four defects found and fixed; invariants enforced in CI at no ongoing cost. **Scope is settled: no further privacy work.** A claiming buyer gets the exact address by design; the coarsening exists only to stop bulk harvesting by non-claimants. Density-aware cells and similar refinements are explicitly out of scope
3. ~~Migrations into CI~~ — **done**; all ten apply to an empty PostGIS database, verified locally. This immediately caught `unaccent()` not being `IMMUTABLE`, which would have blocked M1
4. Use `public_point` for pre-claim distance and ranking — one line in the search RPC when M2 writes it, not a separate task
4. Supply survey: confirm Covina/Glendora/Azusa has real density in *both* categories — MEHKO meal cooks, not just the sourdough cluster the original recommendation was built around — **and enough concurrent openings to make "open now" non-empty** (`PRD.md` §11.9)
5. Scan COOK Connect as prior art / potential verification partner (`PRD.md` §11.1) before building permit-review tooling from scratch
6. Decide the iOS floor: 18 (keeps the Control Center burner) or 17 (drops it from the thesis) — §1
7. `M0` — scaffold, ordered migrations, and the authorization test matrix
