-- Post-deploy safety check. Run against any environment; raises on the first
-- violation rather than reporting, so it can gate a deploy.
--
--   supabase db push && psql "$DATABASE_URL" -f supabase/verify_invariants.sql
--
-- Every check here corresponds to a defect that was actually found and fixed
-- (SPIKE_LOCATION_PRIVACY.md), not a hypothetical.

set search_path = public, extensions;

do $$
begin
  -- Home addresses must be unreachable by any client role.
  if has_table_privilege('authenticated','kitchen_locations','select')
     or has_table_privilege('anon','kitchen_locations','select') then
    raise exception 'FAIL: kitchen_locations is client-readable';
  end if;

  if exists (select 1 from pg_policies where tablename = 'kitchen_locations') then
    raise exception 'FAIL: a policy exists on kitchen_locations — it is protected by absent grants, not RLS';
  end if;

  if exists (select 1 from information_schema.columns
              where table_name = 'kitchens' and column_name = 'exact_point') then
    raise exception 'FAIL: kitchens.exact_point exists';
  end if;

  -- The geo secret must not be readable, and the fuzz must not be reproducible.
  if has_table_privilege('authenticated','app_secrets','select')
     or has_table_privilege('anon','app_secrets','select') then
    raise exception 'FAIL: app_secrets is client-readable';
  end if;

  if has_function_privilege('authenticated','public_point_for(geography,text,double precision)','execute')
     or has_function_privilege('anon','public_point_for(geography,text,double precision)','execute') then
    raise exception 'FAIL: public_point_for is client-executable';
  end if;

  -- The discovery surface must actually be reachable, or the app 403s on
  -- every read. This is the failure mode of turning auto-expose off.
  --
  -- `has_any_column_privilege` for `cooks`, not `has_table_privilege`: 055
  -- moved it to column-level grants so the phone number stays private, and a
  -- table-level test reports that correct change as a broken feed.
  if not has_table_privilege('authenticated','kitchens','select')
     or not has_table_privilege('authenticated','menu_items','select')
     or not has_any_column_privilege('authenticated','cooks','select') then
    raise exception 'FAIL: the discovery tables are not granted — see 011_grants.sql';
  end if;

  -- And the column that must NOT be readable. Asserting the positive alone
  -- would pass just as happily if someone re-granted the whole table.
  if has_column_privilege('anon','cooks','contact_value','select')
     or has_column_privilege('authenticated','cooks','contact_value','select') then
    raise exception 'FAIL: cooks.contact_value is client-readable — see 055';
  end if;

  if not has_function_privilege('authenticated','reveal_address(uuid)','execute') then
    raise exception 'FAIL: reveal_address is not executable by authenticated';
  end if;

  -- RLS must be on wherever a policy is doing the work.
  if exists (
    select 1 from pg_tables t
     where t.schemaname = 'public'
       and t.tablename in ('kitchens','cooks','menu_items','serving_sessions',
                           'claims','claim_items','address_disclosures','complaints','reviews')
       and not exists (
         select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where c.relname = t.tablename and n.nspname = 'public' and c.relrowsecurity
       )
  ) then
    raise exception 'FAIL: a client-facing table has RLS disabled';
  end if;

  raise notice 'OK: all location-privacy and grant invariants hold';
end $$;

-- Fuzzing behaviour, on this database's actual PostGIS build.
do $$
declare v_ratio numeric; v_max numeric;
begin
  if public_point_for(ST_MakePoint(-117.89,34.09)::geography,'probe')::text
   <> public_point_for(ST_MakePoint(-117.89,34.09)::geography,'probe')::text then
    raise exception 'FAIL: fuzzing is not deterministic';
  end if;

  select count(*)::numeric / nullif(count(distinct public_point_for(p,'probe')::text),0) into v_ratio
    from (select ST_MakePoint(-117.8903+(i%50)*0.00035, 34.0900+(i/50)*0.0003)::geography p
          from generate_series(0,2499) i) pts;
  if v_ratio < 20 then
    raise exception 'FAIL: homes no longer collapse onto shared points (ratio %)', round(v_ratio,1);
  end if;

  select max(ST_Distance(p, public_point_for(p,'probe'))) into v_max
    from (select ST_MakePoint(-117.89+(i%30)*0.0006, 34.09+(i/30)*0.0005)::geography p
          from generate_series(0,899) i) pts;
  if v_max > 320 then
    raise exception 'FAIL: displacement % m exceeds the cell half-diagonal', round(v_max,1);
  end if;

  raise notice 'OK: fuzzing deterministic, % homes per published point, max displacement % m',
    round(v_ratio,1), round(v_max,1);
end $$;
