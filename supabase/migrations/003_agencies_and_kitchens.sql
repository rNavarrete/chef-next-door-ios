-- 003 — enforcement agencies and kitchens (public geometry only)
--
-- Jurisdiction is modeled as the enforcement AGENCY, not a city string.
-- Pasadena, Long Beach and Vernon are MEHKO carve-outs because they run
-- independent health departments, not because they are cities — a city column
-- encodes the coincidence instead of the rule.
--
-- UNRESOLVED: whether county authorization reaches cities inside it is
-- COUNSEL_QUESTIONS.md Q2. This is our current best reading, not settled law.

set search_path = public, extensions;

create table enforcement_agencies (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  county          text not null,
  mehko_opted_in  boolean not null default false,
  cottage_food_ok boolean not null default true,
  notes           text
);

alter table cooks
  add constraint cooks_agency_fk
  foreign key (permit_agency_id) references enforcement_agencies(id);

-- Kitchens hold ONLY publishable geometry. The exact point is not in this
-- table, and must never be added to it — see 004.
create table kitchens (
  id           uuid primary key default gen_random_uuid(),
  cook_id      uuid not null references cooks(id) on delete cascade,
  public_point geography(Point,4326) not null,   -- grid-snapped, see 004
  neighborhood text not null,
  city         text not null,
  agency_id    uuid not null references enforcement_agencies(id)
);

create index kitchens_public_point_idx on kitchens using gist (public_point);
create index kitchens_cook_idx on kitchens (cook_id);

comment on column kitchens.public_point is
  'Grid-snapped ~500m, secret-keyed. Non-invertible. Safe to plot and to rank by.';

-- Seed the launch region's agency.
insert into enforcement_agencies (name, county, mehko_opted_in) values
  ('LA County Dept. of Public Health, Environmental Health', 'Los Angeles', true),
  ('City of Pasadena Public Health Department', 'Los Angeles', false),
  ('City of Long Beach Health & Human Services', 'Los Angeles', false),
  ('City of Vernon Health Department', 'Los Angeles', false);
