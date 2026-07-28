-- 010 — RLS on everything client-facing
--
-- kitchen_locations is absent from this file ON PURPOSE: it has no policies
-- because it has no grants (004). If you find yourself adding a policy for it,
-- the design has been misunderstood.
--
-- Reminder on why the previous draft leaked: PERMISSIVE policies compose with
-- OR. A `USING (true)` read policy unions with a restrictive-looking one and
-- wins. Assume every policy below is wrong until the test matrix passes.

set search_path = public, extensions;

alter table kitchens            enable row level security;
alter table cooks               enable row level security;
alter table menu_items          enable row level security;
alter table serving_sessions    enable row level security;
alter table claims              enable row level security;
alter table claim_items         enable row level security;
alter table address_disclosures enable row level security;
alter table complaints          enable row level security;
alter table reviews             enable row level security;

-- Kitchens carry only publishable geometry, so a broad read is safe here in a
-- way it explicitly was NOT when exact_point lived on this table.
create policy kitchens_read on kitchens for select using (true);

create policy cooks_read on cooks for select using (true);
create policy cooks_self_update on cooks for update using (id = auth.uid());

create policy menu_read on menu_items for select using (true);
create policy menu_owner_write on menu_items for all
  using (cook_id = auth.uid()) with check (cook_id = auth.uid());

create policy sessions_read on serving_sessions for select using (true);
-- Open/close go through open_kitchen()/close_kitchen(); no direct writes.

-- Claims are visible to the two parties only.
create policy claims_parties_read on claims for select
  using (buyer_id = auth.uid() or cook_id = auth.uid());

-- A buyer may CREATE a claim but may never set or change its status. A buyer
-- who could confirm their own claim could unlock a home address at will.
create policy claims_buyer_insert on claims for insert
  with check (buyer_id = auth.uid() and status = 'pending');
create policy claims_cook_update on claims for update
  using (cook_id = auth.uid()) with check (cook_id = auth.uid());

create policy claim_items_parties on claim_items for select
  using (exists (
    select 1 from claims c where c.id = claim_id
      and (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
  ));

create policy disclosures_own on address_disclosures for select
  using (buyer_id = auth.uid());

create policy complaints_reporter on complaints for select
  using (reporter_id = auth.uid());
create policy complaints_insert on complaints for insert
  with check (reporter_id = auth.uid());

create policy reviews_read on reviews for select using (true);
create policy reviews_by_claimant on reviews for insert
  with check (exists (
    select 1 from claims c
     where c.id = claim_id
       and c.buyer_id = auth.uid()
       and c.status = 'completed'
  ));
