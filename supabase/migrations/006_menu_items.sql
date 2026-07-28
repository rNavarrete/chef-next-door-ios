-- 006 — menu items
--
-- The structured price is the single most important constraint in the schema.
-- A bare amount cannot be stored: amount, unit and minimum are one unit of
-- meaning. This is the direct inversion of the failure that makes the
-- incumbent marketplaces unusable (RESEARCH.md Finding 2).

set search_path = public, extensions;

create table menu_items (
  id            uuid primary key default gen_random_uuid(),
  cook_id       uuid not null references cooks(id) on delete cascade,
  name_en       text,
  name_es       text,
  description   text,
  category      text not null,
  category_type food_category_type not null,
  allergens     text[] not null default '{}',
  is_available  boolean not null default true,

  amount_cents  integer not null check (amount_cents > 0),
  unit          price_unit not null,
  min_quantity  integer not null default 1 check (min_quantity > 0),

  -- immutable_unaccent (001), not unaccent — a generated column requires an
  -- immutable expression. Both language configs are indexed so a mixed-language
  -- title matches either way (RESEARCH.md Finding 4).
  search_doc    tsvector generated always as (
      setweight(to_tsvector('english', immutable_unaccent(coalesce(name_en,''))), 'A')
   || setweight(to_tsvector('spanish', immutable_unaccent(coalesce(name_es,''))), 'A')
   || setweight(to_tsvector('simple',  immutable_unaccent(coalesce(description,''))), 'C')
  ) stored,

  -- Titles in this market mix languages mid-string. Both names are
  -- first-class; at least one must exist.
  constraint has_a_name check (name_en is not null or name_es is not null)
);

create index menu_items_search_idx on menu_items using gin (search_doc);
create index menu_items_cook_idx on menu_items (cook_id) where is_available;

comment on column menu_items.allergens is
  'Mandatory, dish-level, always visible. A safety surface, not decoration.';

-- Curated bilingual synonyms — a content asset, not just code.
-- tamal↔tamales↔tamalito, pan dulce↔sweet bread, elote↔corn, biria→birria
create table dish_synonyms (
  term      text not null,
  canonical text not null,
  primary key (term, canonical)
);

-- Seeded from vocabulary observed in real listings (RESEARCH.md Findings 3-4).
insert into dish_synonyms (term, canonical) values
  ('tamal','tamales'), ('tamalito','tamales'), ('tamales','tamales'),
  ('pork tamale','tamales'), ('nacatamal','tamales'),
  ('biria','birria'), ('birria','birria'),
  ('pupusa','pupusas'), ('pupusas','pupusas'),
  ('elote','elote'), ('corn','elote'), ('esquite','elote'),
  ('pan dulce','pan dulce'), ('sweet bread','pan dulce'), ('concha','pan dulce'),
  ('champurrado','champurrado'), ('atole','champurrado'),
  ('sourdough','sourdough'), ('masa madre','sourdough')
on conflict do nothing;
