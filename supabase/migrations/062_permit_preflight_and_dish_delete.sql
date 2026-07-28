-- 062 — check a permit *before* the kitchen exists, and let a cook delete a dish
--
-- ## Preflight
--
-- `verify_permit` (030) reads the caller's kitchen to get the city and ZIP it
-- corroborates against, so it cannot run until registration has already
-- happened. That was fine when a failed check only withheld a badge. It is not
-- fine now that a cook who claims "I have my permit number" must clear the
-- check before they can finish: gating on `verify_permit` would mean creating
-- the kitchen, discovering the number is bogus, and having to unwind it.
--
-- `preflight_permit` takes the city and ZIP as arguments instead of reading
-- them, so the same check runs against the address still sitting in the form.
-- It is otherwise deliberately identical to `verify_permit` — same
-- normalisation, same four outcomes, same order of tests — because two checks
-- that disagree would be worse than one check that runs late.
--
-- What it does NOT do is write to `cooks`. There is no `cooks` row yet, and
-- the authoritative write stays with `verify_permit` after registration. This
-- is a read, plus an audit line.
--
-- Probing is not a new exposure: `permit_registry` is already world-readable
-- (`grant select ... to anon, authenticated`, policy `using (true)`), because
-- the county publishes it. Requiring auth here is about attributing attempts,
-- not about guarding the data.
--
-- ## Dish deletion
--
-- `menu_items` already permits deletes — `menu_owner_write` is an ALL policy
-- on `cook_id = auth.uid()` and `authenticated` holds DELETE. The only thing
-- stopping a cook removing a dish was `claim_items.menu_item_id`, a NO ACTION
-- foreign key from the retired claims subsystem. No client code has referenced
-- claims for some time, but nine rows remain, and a dish named in one of them
-- could not be deleted.
--
-- The intent was SET NULL, keeping the claim line and its quantity and merely
-- unlinking the dish. That is not available: `menu_item_id` is half of the
-- composite primary key `(claim_id, menu_item_id)`, so it cannot be nullable.
--
-- So CASCADE. Deleting a dish removes the retired claim lines that named it.
-- Nothing observable is lost — no client has read `claim_items` since the
-- subsystem was retired, and a claim line whose dish is gone has no meaning
-- left to preserve. Dropping the retired tables outright is probably where
-- this ends up, but that is a decision about deleting data, not a decision
-- about this feature.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Attribution for attempts made before a cooks row exists.
-- ---------------------------------------------------------------------------
alter table permit_checks add column if not exists attempted_by uuid;

comment on column permit_checks.attempted_by is
  'The auth user who made the attempt. Set by preflight_permit, where there is '
  'no cooks row yet to fill cook_id. No FK: this is an abuse log, and it must '
  'outlive the account it describes.';

-- ---------------------------------------------------------------------------
-- The pre-registration check.
-- ---------------------------------------------------------------------------
create or replace function preflight_permit(
  p_number      text,
  p_city        text,
  p_postal_code text
)
returns table (outcome text, registered_name text, agency_name text)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_user    uuid := auth.uid();
  v_norm    text := upper(regexp_replace(coalesce(p_number, ''), '[^A-Za-z0-9]', '', 'g'));
  v_city    text := trim(coalesce(p_city, ''));
  v_zip     text := nullif(trim(coalesce(p_postal_code, '')), '');
  v_agency  uuid;
  v_mehko   boolean;
  r         permit_registry%rowtype;
  v_outcome text;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if v_norm = ''  then raise exception 'permit number required'; end if;
  if v_city = ''  then raise exception 'city required'; end if;

  v_agency := agency_for_city(v_city);
  select a.mehko_opted_in into v_mehko
    from enforcement_agencies a where a.id = v_agency;

  select * into r from permit_registry where record_id = v_norm;

  if not found then
    -- An unknown city leaves v_mehko null, which lands here too. That is the
    -- lenient branch on purpose: we should not accuse a cook of a bad permit
    -- on the strength of a city we failed to recognise.
    v_outcome := case when v_mehko then 'not_found' else 'agency_not_covered' end;

  elsif exists (
    select 1 from cooks c
     where upper(regexp_replace(coalesce(c.permit_number, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
       and c.id <> v_user
       and c.permit_status = 'verified'
  ) then
    v_outcome := 'already_claimed';

  elsif upper(r.city) <> upper(v_city)
        and (r.postal_code is null or v_zip is null or r.postal_code <> v_zip) then
    v_outcome := 'wrong_area';

  else
    v_outcome := 'verified';
  end if;

  insert into permit_checks (cook_id, attempted_by, submitted, outcome)
  values (null, v_user, v_norm, v_outcome);

  return query
    select v_outcome,
           case when v_outcome = 'verified' then r.name else null end,
           (select a.name from enforcement_agencies a where a.id = v_agency);
end $$;

revoke all on function preflight_permit(text, text, text) from public, anon;
grant execute on function preflight_permit(text, text, text) to authenticated;

comment on function preflight_permit is
  'Same check as verify_permit, but against a city/ZIP passed in rather than '
  'read from the caller''s kitchen, so it can run before registration. Reads '
  'only; verify_permit remains the one that writes cooks.permit_status.';

-- ---------------------------------------------------------------------------
-- Unblock dish deletion.
-- ---------------------------------------------------------------------------
alter table claim_items drop constraint if exists claim_items_menu_item_id_fkey;
alter table claim_items
  add constraint claim_items_menu_item_id_fkey
  foreign key (menu_item_id) references menu_items(id) on delete cascade;

comment on column claim_items.menu_item_id is
  'CASCADE, not SET NULL: this column is half of the composite primary key and '
  'cannot be nullable. Deleting a dish drops the retired claim lines naming it.';
