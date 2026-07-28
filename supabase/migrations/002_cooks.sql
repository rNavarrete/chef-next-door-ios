-- 002 — cooks
--
-- Note what is NOT here: serving_opened_at / last_confirmed_at live on
-- serving_sessions (005), and complaint counts live in a real event log (008).
-- Both were previously mutable fields on this row, which is overwritten every
-- time a cook opens — so there was no history, and the freshness metrics in
-- PRD.md §9 were literally uncomputable.

set search_path = public, extensions;

create table cooks (
  id               uuid primary key references auth.users(id) on delete cascade,
  display_name     text not null,
  bio              text,
  avatar_path      text,
  instagram        text,

  contact_method   contact_method not null default 'sms',
  contact_value    text not null,          -- never exposed pre-confirmed-claim
  phone_verified   boolean not null default false,

  permit_status    permit_status not null default 'none',
  permit_kind      text,                   -- 'mehko' | 'cfo_class_a' | 'cfo_class_b' | 'food_handler'
  permit_number    text,                   -- PUBLIC BY LAW. Deliberately not restricted
                                           -- the way location is (PRD §8).
  permit_agency_id uuid,                   -- FK added in 003
  permit_expires   date,

  serving_status   serving_status not null default 'closed',
  serving_note     text,
  typical_hours    jsonb,                  -- advisory only: "usually Sat mornings"

  created_at       timestamptz not null default now()
);

comment on column cooks.permit_number is
  'Public by law. Unlike the address, which never is.';
comment on column cooks.contact_value is
  'Released only through the confirmed-claim handoff path. Never in a list payload.';
