-- 008 — claims, disclosure audit, complaints, reviews
--
-- A claim is a WARM INTRO, not a purchase and not a reservation. It records
-- that someone pressed a button and we opened a text message. Whether food was
-- bought happens off-platform and is invisible to us.
--
-- That matters beyond copy: statutory duties referencing consumers who "made a
-- purchase through" the platform may not be satisfiable from these records.
-- See COUNSEL_QUESTIONS.md Q3 before treating a claim as transaction evidence.

set search_path = public, extensions;

create table claims (
  id                 uuid primary key default gen_random_uuid(),
  cook_id            uuid not null references cooks(id) on delete cascade,
  serving_session_id uuid not null references serving_sessions(id),
  buyer_id           uuid not null references auth.users(id),
  status             claim_status not null default 'pending',
  note               text,
  created_at         timestamptz not null default now()
);

create index claims_cook_time_idx on claims (cook_id, created_at desc);
create index claims_session_idx on claims (serving_session_id);
create index claims_buyer_idx on claims (buyer_id, created_at desc);

create table claim_items (
  claim_id     uuid references claims(id) on delete cascade,
  menu_item_id uuid references menu_items(id),
  quantity     integer not null check (quantity > 0),
  primary key (claim_id, menu_item_id)
);

-- Answering a claim confirms the session ONLY if the claim belongs to the
-- session that is currently open (007).
create or replace function answer_claim(p_claim uuid, p_status claim_status)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_cook uuid; v_session uuid; v_open uuid;
begin
  select cook_id, serving_session_id into v_cook, v_session
    from claims where id = p_claim;

  if v_cook is null or v_cook <> auth.uid() then
    raise exception 'not authorized';
  end if;

  update claims set status = p_status where id = p_claim;

  select id into v_open
    from serving_sessions where cook_id = v_cook and closed_at is null;

  if v_open is not null and v_open = v_session then
    perform confirm_session(v_cook);   -- responding to live demand
  end if;                              -- else: bookkeeping, not cooking
end $$;

-- ---------------------------------------------------------------------------
-- Every address disclosure is logged. This is the audit trail for the
-- harvesting vector described in PRD §7.
-- ---------------------------------------------------------------------------

create table address_disclosures (
  id           uuid primary key default gen_random_uuid(),
  claim_id     uuid not null references claims(id),
  kitchen_id   uuid not null references kitchens(id),
  buyer_id     uuid not null references auth.users(id),
  disclosed_at timestamptz not null default now()
);

create index address_disclosures_buyer_idx
  on address_disclosures (buyer_id, disclosed_at desc);
create index address_disclosures_kitchen_idx
  on address_disclosures (kitchen_id, disclosed_at desc);

-- A real event log, not a counter on the cook row. The escalation duty runs on
-- a 2-week clock from the third complaint, which a counter cannot express.
create table complaints (
  id           uuid primary key default gen_random_uuid(),
  cook_id      uuid not null references cooks(id),
  claim_id     uuid references claims(id),
  reporter_id  uuid references auth.users(id),
  kind         text not null,          -- 'food_safety' | 'hygiene' | 'other'
  body         text,
  created_at   timestamptz not null default now(),
  escalated_at timestamptz             -- set when submitted to the agency
);

create index complaints_cook_idx on complaints (cook_id, created_at desc);

-- Cooks with 3+ unrelated food-safety complaints in the calendar year and an
-- un-escalated third. Drives the admin queue and the 2-week clock.
create or replace view complaints_requiring_escalation as
  select cook_id,
         count(*) as complaint_count,
         min(created_at) filter (where escalated_at is null) as oldest_unescalated,
         max(created_at) as latest
    from complaints
   where kind in ('food_safety','hygiene')
     and created_at >= date_trunc('year', now())
   group by cook_id
  having count(*) >= 3
     and count(*) filter (where escalated_at is null) > 0;

create table reviews (
  id         uuid primary key default gen_random_uuid(),
  claim_id   uuid not null unique references claims(id),
  rating     smallint not null check (rating between 1 and 5),
  body       text,
  created_at timestamptz not null default now()
);
