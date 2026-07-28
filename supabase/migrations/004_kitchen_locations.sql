-- 004 — exact locations: a table no client can reach
--
-- WHY THIS IS A SEPARATE TABLE, not a column with a policy:
--
-- The previous design kept exact_point on `kitchens` and relied on RLS plus a
-- view that omitted the column. That does not work, for two independent
-- reasons:
--   1. Postgres combines PERMISSIVE policies with OR. A `USING (true)` read
--      policy unions with the claim-gated policy and wins.
--   2. RLS is row-level. It would not have hidden the column even if the
--      policies had been written correctly, and a view protects nothing while
--      the client can still select the base table.
--
-- The fix is structural: exact coordinates live here, NO client role holds any
-- grant on this table, and the only path in is reveal_address() (009), which
-- checks authorization and writes an audit row.

set search_path = public, extensions;

create table kitchen_locations (
  kitchen_id  uuid primary key references kitchens(id) on delete cascade,
  exact_point geography(Point,4326) not null,
  street      text not null,
  city        text not null,
  postal_code text not null,
  updated_at  timestamptz not null default now()
);

-- The security model, in two statements. Not a policy — an absence of grants.
revoke all on kitchen_locations from public;
revoke all on kitchen_locations from anon, authenticated;
alter table kitchen_locations enable row level security;
-- No policy is ever added here. If you are about to add one, stop.

comment on table kitchen_locations is
  'Home addresses. No client grants. Reachable only via reveal_address(). '
  'Cooks are frequently women working alone; a leak here is a physical-safety '
  'incident, not a bug.';

-- ---------------------------------------------------------------------------
-- Grid-snapped fuzzing
--
-- History, because the mistakes are instructive:
--
--   v1  derived the offset from hashtext(kitchen.id). The kitchen id is
--       public, so anyone could recompute the offset and project BACKWARDS to
--       the front door. Determinism defeated averaging attacks and handed over
--       exact inversion instead.
--
--   v2  keyed the offset with a server secret and snapped to a 500-unit grid.
--       The location-privacy spike then measured three problems:
--         (a) the secret sat in a GUC that `authenticated` could simply read
--             via current_setting('app.geo_secret') — verified, it returned
--             the value;
--         (b) public_point_for was EXECUTE-able by PUBLIC (Postgres default),
--             so with (a) an attacker could reproduce the whole scheme;
--         (c) it snapped in EPSG:3857, where a "500m" cell is 500m only at the
--             equator — 414m at Covina, 337m in Seattle. The cell was never
--             the size the comment claimed.
--
--   v3  (this one) fixes all three. Read the honest security claim below.
--
-- WHAT ACTUALLY PROTECTS THE ADDRESS: lossiness, not secrecy.
-- Published points lie on a lattice, so the grid PHASE is recoverable from any
-- single published point — measured in the spike, all points shared one
-- residue mod cell size. The secret only stops someone precomputing against a
-- globally fixed grid; it is not what keeps the address safe. The address is
-- safe because every home in a ~400m cell publishes the identical point, so
-- the best possible recovery is "somewhere in this cell."
-- ---------------------------------------------------------------------------

-- Secrets live in a table with no grants, not in a GUC any role can read.
create table app_secrets (
  key   text primary key,
  value text not null
);
revoke all on app_secrets from public;
revoke all on app_secrets from anon, authenticated;
alter table app_secrets enable row level security;

comment on table app_secrets is
  'No client grants. A GUC was used here previously and `authenticated` could '
  'read it with current_setting() — verified in the location-privacy spike.';

-- Snapping happens in UTM, which is metric: one unit is one metre on the
-- ground, so a `cell_m` grid is genuinely `cell_m` wide.
--
-- NOT Web Mercator. Two attempts failed there, and the second is the
-- instructive one:
--   * snapping with a fixed 500-unit cell gave a cell that shrank with
--     latitude (414 m at Covina, 337 m in Seattle);
--   * dividing the cell by cos(latitude) to compensate made the cell size vary
--     *continuously per point*, so no two homes shared a grid to snap to and
--     collisions collapsed — 2500 homes in 1.6 km² produced 248 distinct
--     points instead of ~16. The privacy guarantee had silently evaporated
--     while the "constant cell size" test passed.
--
-- Collisions are the guarantee, so the grid must be shared. UTM gives both.
create or replace function public_point_for(
  p geography,
  secret text,
  cell_m double precision default 400
)
-- The function-level search_path matters as much as the session one: a SQL
-- function body is re-resolved at execution using the *caller's* path, and the
-- caller here is a trigger that may run under any role.
returns geography language sql immutable
set search_path = public, extensions as $$
  with base as (
    select p::geometry as g,
           -- UTM zone from longitude; north/south from latitude.
           (case when ST_Y(p::geometry) >= 0 then 32600 else 32700 end)
             + least(greatest(floor((ST_X(p::geometry) + 180) / 6)::int + 1, 1), 60) as srid
  ), proj as (
    select ST_Transform(g, srid) as m, srid,
           ('x' || substr(encode(hmac('grid-x', secret, 'sha256'), 'hex'), 1, 7))::bit(28)::int
             % cell_m::int as jx,
           ('x' || substr(encode(hmac('grid-y', secret, 'sha256'), 'hex'), 1, 7))::bit(28)::int
             % cell_m::int as jy
    from base
  )
  select ST_Transform(
           ST_SetSRID(ST_MakePoint(
             round((ST_X(m) + jx) / cell_m) * cell_m - jx,
             round((ST_Y(m) + jy) / cell_m) * cell_m - jy
           ), srid),
         4326)::geography
  from proj;
$$;

-- Not callable by clients. Combined with app_secrets this removes the
-- reproduce-the-scheme path entirely.
revoke all on function public_point_for(geography, text, double precision) from public;
revoke all on function public_point_for(geography, text, double precision) from anon, authenticated;

comment on function public_point_for is
  'Deterministic AND lossy. Every home in a cell publishes the same point — '
  'that collision, not the secret, is the privacy guarantee.';

create or replace function sync_public_point() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_secret text;
begin
  select value into v_secret from app_secrets where key = 'geo_secret';
  if v_secret is null then
    raise exception 'geo_secret is not configured; refusing to publish a location';
  end if;

  update kitchens
     set public_point = public_point_for(new.exact_point, v_secret)
   where id = new.kitchen_id;
  return new;
end $$;

create trigger kitchen_location_sync
  after insert or update of exact_point on kitchen_locations
  for each row execute function sync_public_point();
