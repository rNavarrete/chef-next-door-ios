-- 027 — claim completion, and the reviews that depend on it
--
-- `reviews_by_claimant` (010) requires `claims.status = 'completed'`. Nothing
-- ever set that: `answer_claim` is cook-only and offers confirm/decline, and no
-- surface offered "completed" at all. So the reviews table has existed since
-- 008 and has been unreachable the entire time.
--
-- **Either party may mark it done, and we record which.** Not symmetry for its
-- own sake: `PRD.md` §8 and `COUNSEL_QUESTIONS.md` Q3 turn on the fact that a
-- claim records "opened a text", not "bought food". A handoff confirmed by both
-- sides is the strongest evidence this model can produce that anything actually
-- changed hands, and knowing *who* said so is part of that evidence. A single
-- boolean would throw it away.

set search_path = public, extensions;

alter table claims add column if not exists completed_at timestamptz;
alter table claims add column if not exists completed_by uuid references auth.users(id);

comment on column claims.completed_by is
  'Which party marked the handoff done. Deliberately not a boolean — see '
  'COUNSEL_QUESTIONS.md Q3 on what evidence a claim can and cannot carry.';

-- ---------------------------------------------------------------------------
-- Completion.
--
-- Only from `confirmed`: a pending claim the cook never answered did not
-- happen, and letting it jump straight to completed would manufacture exactly
-- the "purchase" evidence we are careful not to overstate.
-- ---------------------------------------------------------------------------
create or replace function complete_claim(p_claim uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_buyer uuid; v_cook uuid; v_status claim_status;
begin
  select buyer_id, cook_id, status into v_buyer, v_cook, v_status
    from claims where id = p_claim;

  if v_buyer is null then
    raise exception 'no such claim';
  end if;
  if auth.uid() not in (v_buyer, v_cook) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'confirmed' then
    raise exception 'only a confirmed claim can be completed';
  end if;

  update claims
     set status       = 'completed',
         completed_at = now(),
         completed_by = auth.uid()
   where id = p_claim;
end $$;

revoke all on function complete_claim(uuid) from public, anon;
grant execute on function complete_claim(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reviews gain the cook they are about.
--
-- Denormalised so a cook's reviews are readable without reading `claims`,
-- which is restricted to the two parties — the reason this table was public to
-- read but impossible to query usefully.
-- ---------------------------------------------------------------------------
alter table reviews add column if not exists cook_id uuid references cooks(id);

update reviews r
   set cook_id = c.cook_id
  from claims c
 where c.id = r.claim_id
   and r.cook_id is null;

alter table reviews alter column cook_id set not null;
create index if not exists reviews_cook_idx on reviews (cook_id, created_at desc);

-- The client supplies cook_id, so the policy pins it to the claim's actual
-- cook. Otherwise a buyer could attach a genuine review of one kitchen to a
-- competitor — an insert they are fully authorised to make, aimed at the wrong
-- row.
drop policy if exists reviews_by_claimant on reviews;
create policy reviews_by_claimant on reviews for insert
  with check (exists (
    select 1 from claims c
     where c.id = claim_id
       and c.buyer_id = auth.uid()
       and c.status = 'completed'
       and c.cook_id = reviews.cook_id
  ));

-- A buyer may correct their own wording; the cook it points at is fixed.
drop policy if exists reviews_own_update on reviews;
create policy reviews_own_update on reviews for update
  using (exists (
    select 1 from claims c
     where c.id = reviews.claim_id and c.buyer_id = auth.uid()
  ))
  with check (exists (
    select 1 from claims c
     where c.id = reviews.claim_id
       and c.buyer_id = auth.uid()
       and c.cook_id = reviews.cook_id
  ));

grant update on reviews to authenticated;

-- ---------------------------------------------------------------------------
-- Aggregate, for the kitchen page. Counts only, no ranking: with a handful of
-- reviews per cook an average is noise, and sorting discovery by it would
-- entrench whoever happened to start first.
-- ---------------------------------------------------------------------------
create or replace function cook_rating(p_cook uuid)
returns table (review_count integer, average numeric)
language sql stable set search_path = public, extensions as $$
  select count(*)::int, round(avg(rating)::numeric, 1)
    from reviews where cook_id = p_cook;
$$;

grant execute on function cook_rating(uuid) to anon, authenticated;
