-- 070 — you cannot open a kitchen anonymously
--
-- Found by attacking the API with an extracted anon key, which is the correct
-- way to think about it: the key ships inside the app and anybody can read it
-- out of the binary, so every grant to `authenticated` is a grant to anyone
-- willing to call `/auth/v1/signup` with an empty body.
--
-- `register_cook` only checked that `auth.uid()` was not null. An anonymous
-- session satisfies that — Supabase issues a real `authenticated` user with
-- `is_anonymous = true`. So a stranger could, in two HTTP requests and with no
-- email address, create a cook with a display name, a street address and a
-- kitchen that appears on the map to everyone.
--
-- ## Why this is the one that mattered
--
-- Every other check held. Phone numbers, exact addresses, buyer names, message
-- contents, push tokens and reports were all refused — to an unauthenticated
-- caller and to a signed-in stranger alike. Nothing could be read that should
-- not have been.
--
-- This was the opposite: not a read leak, a *write*. Registration is the most
-- consequential act in the app — it puts a name and an address on the map,
-- where the whole premise is that the pin means a real person is cooking. And
-- an anonymous account has no email, so there is nobody to contact, nothing to
-- ban, and no cost at all to doing it again.
--
-- ## The inconsistency it fixes
--
-- Sending a *message* has required a permanent account since 040, on the
-- reasoning that a cook should know who is writing to them. Opening a kitchen —
-- which every buyer then sees, and drives to — required less. That was
-- backwards, and it was not a decision anyone made; the messaging gate was
-- added later and registration was never revisited.
--
-- `sender_can_message()` already encodes exactly this test, so it is reused
-- rather than reimplemented: one definition of "has a real account", in one
-- place, for both doors.

set search_path = public, extensions;

create or replace function assert_permanent_account() returns void
language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce((select u.is_anonymous from auth.users u where u.id = v_me), true) then
    -- Same errcode the messaging gate uses, so the app can open the same
    -- "you need an account" sheet rather than showing a raw failure.
    raise exception 'sign in to open a kitchen' using errcode = 'P0002';
  end if;
end $$;

revoke all on function assert_permanent_account() from public, anon;
grant execute on function assert_permanent_account() to authenticated;

comment on function assert_permanent_account() is
  'Raises P0002 for an anonymous session. The write-side twin of '
  'sender_can_message — anything that creates public, attributable content '
  'should call this first.';

-- ---------------------------------------------------------------------------
-- The gate, on the door it was missing from.
-- ---------------------------------------------------------------------------
--
-- Patched by re-issuing the function body with one call added after the
-- existing null check, so the rest of `register_cook` is untouched — the
-- idempotency guard, the validation, the fuzzed point and the agency lookup all
-- stay exactly as they were.

do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'register_cook';

  if v_def is null then
    raise exception 'register_cook not found';
  end if;
  if position('assert_permanent_account' in v_def) > 0 then
    raise notice 'already gated, nothing to do';
    return;
  end if;

  v_def := replace(
    v_def,
    E'  if v_user is null then\n    raise exception \'not authenticated\';\n  end if;',
    E'  if v_user is null then\n    raise exception \'not authenticated\';\n  end if;\n\n'
    '  -- Opening a kitchen puts a name and an address on the map. An anonymous\n'
    '  -- session has no email behind it, so there is nobody to contact and\n'
    '  -- nothing to ban. See 070.\n'
    '  perform assert_permanent_account();'
  );

  if position('assert_permanent_account' in v_def) = 0 then
    raise exception 'anchor not found — register_cook body has changed, patch by hand';
  end if;

  execute v_def;
end $$;
