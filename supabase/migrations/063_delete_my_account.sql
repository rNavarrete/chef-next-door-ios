-- 063 — let someone delete their account, because the App Store requires it
--
-- Guideline 5.1.1(v): an app that lets you create an account must let you
-- delete it from inside the app. Not by emailing support, not by a web form.
-- There was no way to do it here at all, client or server.
--
-- ## Why this cannot be one DELETE
--
-- `cooks.id` and most buyer-side tables cascade from `auth.users`, so the bulk
-- of it takes care of itself. Seven foreign keys do not — they are NO ACTION,
-- and any one of them turns `delete from auth.users` into a constraint
-- violation. They split into two groups, and the split is a judgement about
-- what a deletion should mean rather than a technicality.
--
-- ### Anonymised, because it has to outlive the account
--
--   complaints.reporter_id
--     A report about a cook must not evaporate because the person who filed it
--     later deleted their account. Nullable, so the report survives with the
--     reporter's identity removed — which is what a deletion should do to it.
--
--   claims.completed_by, serving_sessions.opened_by_user
--     Historical bookkeeping. Nulled rather than deleted so the row's other
--     facts stay intact.
--
-- ### Deleted, because the subject is gone
--
--   complaints.cook_id, reviews.cook_id
--     NOT NULL, so anonymising is not available. A complaint or review about a
--     cook who no longer exists has no subject left to be about.
--
--     This is the uncomfortable one, and worth naming plainly: it means a cook
--     can shed complaints by deleting and re-registering. The alternative is
--     retaining a shadow record of someone who asked to be deleted, which is
--     the thing 5.1.1(v) exists to prevent. Deletion wins here, but if abuse
--     ever shows up in practice the answer is a hashed, non-reversible marker
--     rather than keeping the account.
--
--   address_disclosures.buyer_id, claims.buyer_id
--     NOT NULL. A record that this buyer was given an address is *about* the
--     buyer; keeping it would be keeping their data.
--
-- ## Storage is the client's job
--
-- Photos are not reachable from here: Supabase's protect_delete() trigger
-- refuses direct deletion from storage tables and points at the Storage API.
-- Two policies already let a user remove their own files ("avatars delete by
-- owner", "cooks delete their own photos"), so the client clears its buckets
-- with its own JWT *before* calling this. If that fails the account still goes
-- and the bytes are orphaned — worse tidiness, not worse privacy, since
-- nothing references them once the rows are gone.

set search_path = public, extensions;

create or replace function delete_my_account()
returns void
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Survives, minus the person.
  update complaints        set reporter_id    = null where reporter_id    = v_user;
  update claims            set completed_by   = null where completed_by   = v_user;
  update serving_sessions  set opened_by_user = null where opened_by_user = v_user;

  -- Cannot be anonymised; the subject is being deleted.
  delete from address_disclosures where buyer_id = v_user;
  delete from claims             where buyer_id = v_user;
  delete from complaints         where cook_id  = v_user;
  delete from reviews            where cook_id  = v_user;

  -- Everything else — cooks, kitchens, menu_items, conversations, messages,
  -- follows, device_tokens, profiles — cascades from here.
  delete from auth.users where id = v_user;
end $$;

revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;

comment on function delete_my_account is
  'Deletes the caller''s own account and everything cascading from it. Reports '
  'filed by the caller survive with the reporter anonymised; reports about them '
  'do not survive, because the subject is gone. Callers must clear their own '
  'storage objects first — SQL cannot touch them.';
