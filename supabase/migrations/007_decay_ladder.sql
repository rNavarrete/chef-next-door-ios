-- 007 — the decay ladder
--
-- Mitigation for the highest-severity risk in the product: a lit kitchen that
-- stopped cooking hours ago (PRD §10). Must stay in step with
-- Sources/LitKitchen/Core/Availability/FreshnessTier.swift.

-- STABLE, not IMMUTABLE: it reads now(). IMMUTABLE would let the planner
-- cache or inline it wrongly — a previous draft had exactly this bug.
set search_path = public, extensions;

create or replace function freshness_of(last_confirmed timestamptz, closed timestamptz)
returns freshness_tier language sql stable as $$
  select case
    when closed is not null                          then 'out'::freshness_tier
    when now() - last_confirmed < interval '4 hours' then 'lit'
    when now() - last_confirmed < interval '6 hours' then 'dimming'
    else 'unconfirmed'
  end;
$$;

-- ---------------------------------------------------------------------------
-- WHAT COUNTS AS CONFIRMATION
--
-- An earlier draft bumped the clock on ANY cook activity, which meant marking
-- a three-day-old claim "picked up" at 9pm would relight a kitchen that went
-- cold at noon — the exact failure this ladder exists to prevent, wired in
-- backwards.
--
-- Confirms:      explicit "still cooking", sold-out flip, note edit,
--                answering a claim FROM THE CURRENT SESSION
-- Does not:      answering a prior-session claim, editing prices/photos/permit
-- ---------------------------------------------------------------------------

create or replace function confirm_session(p_cook uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update serving_sessions
     set last_confirmed_at = now()
   where cook_id = p_cook and closed_at is null;
$$;

create or replace function touch_on_item_availability() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform confirm_session(new.cook_id);
  return new;
end $$;

create trigger menu_availability_confirms
  after update of is_available on menu_items
  for each row when (old.is_available is distinct from new.is_available)
  execute function touch_on_item_availability();

create or replace function touch_on_note_edit() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform confirm_session(new.id);
  return new;
end $$;

create trigger serving_note_confirms
  after update of serving_note on cooks
  for each row when (old.serving_note is distinct from new.serving_note)
  execute function touch_on_note_edit();

-- Deliberately absent: a trigger on claims. Whether answering a claim confirms
-- depends on which session it belongs to, so it is decided in the claim-answer
-- procedure (008) rather than blanket-applied here.
