-- 032 — a cook cannot award themselves a badge
--
-- 011 granted UPDATE on the whole `cooks` row to `authenticated`, with RLS
-- restricting it to the owner. That is correct about *which row* and silent
-- about *which columns* — so a cook could PATCH their own row and set
-- `permit_status = 'verified'` with any permit number they liked.
--
-- Demonstrated against the live project: one HTTP call set a seeded cook to
-- verified with the permit number "TOTALLY-MADE-UP". Every check in
-- `verify_permit` (030) — register match, city corroboration, one-cook-per-
-- permit, the audit trail — was simply optional, because nothing required
-- going through it.
--
-- Same shape as the location leak this schema already carries a warning about:
-- a rule that is right about rows and never asked about columns.
--
-- The fix is column-level grants. Anything that represents a *claim about the
-- outside world* — permit state, phone verification, which agency covers the
-- kitchen — is writable only by a SECURITY DEFINER function that checks it.
-- What is left is what a cook genuinely owns: their name, their bio, how to
-- reach them.

set search_path = public, extensions;

revoke update on cooks from authenticated;

grant update (
  display_name,
  bio,
  avatar_path,
  avatar_url,
  instagram,
  contact_method,
  contact_value,
  serving_note,
  typical_hours
) on cooks to authenticated;

-- Deliberately absent, and each for a different reason:
--
--   permit_status, permit_number, permit_kind, permit_expires
--       set only by verify_permit() and refresh_permit_registry(), which
--       check against the county register.
--   permit_agency_id
--       derived from the kitchen's city by register_cook(); a cook choosing
--       their own regulator defeats agency_for_city().
--   phone_verified
--       a claim about a verification we have not built yet. It should never
--       have been client-writable, and a cook setting it true would be
--       asserting something nobody checked.
--   serving_status
--       open_kitchen() / close_kitchen() own this, because the decay ladder
--       depends on *why* it changed, not just that it did.
--   id, created_at
--       identity and history.

-- Repair anything already self-asserted. Only permits that actually appear in
-- the county register keep the badge; the rest fall back to pending, which is
-- the honest state for "told us a number, could not confirm it".
update cooks c
   set permit_status = case
         when c.permit_number is null then 'none'::permit_status
         when exists (
           select 1 from permit_registry r
            where r.record_id = upper(regexp_replace(c.permit_number, '[^A-Za-z0-9]', '', 'g'))
         ) then 'verified'::permit_status
         else 'pending'::permit_status
       end
 where c.permit_status in ('verified', 'expired');
