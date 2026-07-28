-- 055 — a cook's phone number was world-readable
--
-- `cooks` is granted SELECT to `anon` so the feed can render, and that grant
-- covers **every column** — including `contact_value`, the cook's personal
-- phone number. One HTTP request with the anonymous key, which ships inside the
-- app binary, returns the phone number of every cook on the platform.
--
-- ## This contradicts the schema's own reasoning
--
-- 039 built in-app messaging specifically to avoid disclosing phone numbers,
-- and said why:
--
--   > This schema puts a rate-limited, audited RPC in front of home addresses
--   > precisely because a cook's location is not ours to hand out; a phone
--   > number is the same class of thing, and handing it out freely while
--   > guarding the address would be incoherent.
--
-- The whole messaging feature exists so a buyer never sees the number — while
-- the raw column was public to people who had never opened the app. The address
-- is protected structurally (`kitchen_locations`, no grants at all); the phone
-- number sat one column over in a table anyone can read.
--
-- `Cook.swift` even documents the intent — "contactValue is absent by design —
-- the cook's phone/handle is not exposed" — which was true of the Swift model
-- and false of the database.
--
-- ## Column grants, the same instrument 032 used
--
-- 032 hit this shape once already: `authenticated` had UPDATE on the whole row,
-- so a cook could PATCH themselves a verified permit badge. It fixed the write
-- side with column-level grants and left the read side alone. This is the read
-- side.
--
-- Nothing legitimate breaks. The client's only direct read of this table is
-- `select("id")` in `refreshCookStatus`; every other path is a SECURITY DEFINER
-- RPC, which bypasses grants entirely.

set search_path = public, extensions;

revoke select on cooks from anon, authenticated;

-- Everything a buyer is meant to see, and nothing else.
grant select (
  id,
  display_name,
  bio,
  avatar_path,
  avatar_url,
  instagram,
  -- Public on purpose: the permit number is a trust signal a buyer can check
  -- against the county register themselves (`PRD.md` §7).
  permit_status,
  permit_number,
  permit_kind,
  permit_agency_id,
  permit_expires,
  serving_status,
  serving_note,
  typical_hours,
  created_at
) on cooks to anon, authenticated;

-- Withheld:
--
--   contact_value   the phone number. The reason this migration exists.
--   contact_method  reveals the channel, which narrows the number's format and
--                   is of no use to anyone who cannot message it anyway.
--   phone_verified  a fact about a person rather than about their food. Nothing
--                   renders it today; if a badge ever wants it, expose it
--                   through a function that returns a boolean and not the row.

comment on column cooks.contact_value is
  'NOT readable by clients — see migration 055. Messaging goes through '
  'send_message so the number is never disclosed; a grant that leaked it made '
  'that whole design pointless.';
