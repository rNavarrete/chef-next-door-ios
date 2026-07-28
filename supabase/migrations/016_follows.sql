-- 016 — follows
--
-- "Turn her light on for me" — the follow relationship, plus a per-cook push
-- preference. Following quietly is allowed on purpose: a buyer may want a cook
-- in their list without a notification every time that kitchen opens, and
-- forcing the two together is how notification fatigue starts.
--
-- Buyer-owned rows: RLS restricts every operation to the follower. A cook
-- cannot enumerate who follows them from the client — that is an aggregate the
-- server can expose later ("34 neighbours are watching for your light") without
-- handing over the list.

set search_path = public, extensions;

create table follows (
  buyer_id   uuid not null references auth.users(id) on delete cascade,
  cook_id    uuid not null references cooks(id) on delete cascade,
  notify     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (buyer_id, cook_id)
);

create index follows_cook_idx on follows (cook_id) where notify;

alter table follows enable row level security;

create policy follows_own on follows for select using (buyer_id = auth.uid());
create policy follows_insert on follows for insert with check (buyer_id = auth.uid());
create policy follows_update on follows for update using (buyer_id = auth.uid());
create policy follows_delete on follows for delete using (buyer_id = auth.uid());

grant select, insert, update, delete on follows to authenticated;

-- ---------------------------------------------------------------------------
-- Discovery rows for a specific set of cooks.
--
-- Saved needs the same shape as the feed and the map, so it reuses
-- discovery_row rather than inventing a parallel one. Takes ids explicitly so
-- it works both for server-side follows and for the local list used before
-- auth lands.
-- ---------------------------------------------------------------------------
create or replace function cooks_by_ids(
  ids uuid[],
  lat double precision,
  lon double precision
)
returns setof discovery_row
language sql stable
set search_path = public, extensions as $$
  select r.* from cooking_now(lat, lon, 1000000, true) r
   where r.cook_id = any(ids);
$$;

grant execute on function cooks_by_ids(uuid[], double precision, double precision)
  to anon, authenticated;

-- How many people are watching a cook's light. An aggregate, never the list —
-- the cook-side "34 neighbours got the light" copy needs a count and nothing
-- more.
create or replace function follower_count(p_cook uuid)
returns integer
language sql stable security definer
set search_path = public, extensions as $$
  select count(*)::int from follows where cook_id = p_cook;
$$;

grant execute on function follower_count(uuid) to anon, authenticated;
