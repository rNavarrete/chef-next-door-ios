-- 031 — let the register actually be refreshed
--
-- 030 revoked `refresh_permit_registry` from `public, anon, authenticated` so
-- no client could mint badges, and then granted it to nobody. Postgres makes
-- new functions EXECUTE-able by PUBLIC, and `service_role` was relying on that
-- default — revoking it from PUBLIC took it away from service_role too.
--
-- Result: the only thing that can write the register couldn't, and the refresh
-- script failed with 42501 `permission denied for function
-- refresh_permit_registry`.
--
-- This was not caught by the migration tests because they run as the database
-- owner, and an owner bypasses grant checks. A grant is only really tested
-- from the role that has to use it.

set search_path = public, extensions;

grant execute on function refresh_permit_registry(jsonb) to service_role;

-- Belt and braces: the revoke in 030 stands, so this stays a service-role-only
-- operation. Restated here so the intent survives someone reading 031 alone.
revoke all on function refresh_permit_registry(jsonb) from public, anon, authenticated;

comment on function refresh_permit_registry is
  'Service role only. Anything that can write the register can mint permit '
  'badges, so this is deliberately unreachable from the app.';
