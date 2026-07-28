-- 022 — reveal_address returns plain coordinates, not a geography
--
-- THE BUG, found on the first successful address reveal:
--
--   typeMismatch: expected Dictionary<String, Any> but found a string
--   at codingPath [Index 0, "point"]
--
-- PostgREST serialises `geography` as a WKB hex string (`0101000020E6…`), not
-- as GeoJSON, so a client expecting `{latitude, longitude}` cannot decode it.
-- The claim looked confirmed and the address silently failed to arrive — the
-- worst shape of failure for this particular screen, because the buyer is
-- standing there waiting for it.
--
-- Returning two doubles instead. Directions need real coordinates rather than
-- a geocoded string: a home kitchen is a house, and geocoding "1148 N Puente
-- Ave" can land a buyer on the wrong side of the street.

set search_path = public, extensions;

drop function if exists reveal_address(uuid);

create or replace function reveal_address(p_claim uuid)
returns table (
  street      text,
  city        text,
  postal_code text,
  latitude    double precision,
  longitude   double precision
)
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_kitchen uuid;
  v_recent  int;
begin
  -- The caller must own the claim, and the COOK must have confirmed it.
  select ss.kitchen_id into v_kitchen
    from claims c
    join serving_sessions ss on ss.id = c.serving_session_id
   where c.id = p_claim
     and c.buyer_id = auth.uid()
     and c.status in ('confirmed','completed');

  if v_kitchen is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- Rate limit: distinct kitchens unlocked per buyer per rolling day.
  select count(distinct kitchen_id) into v_recent
    from address_disclosures
   where buyer_id = auth.uid()
     and disclosed_at > now() - interval '24 hours'
     and kitchen_id <> v_kitchen;

  if v_recent >= 5 then
    raise exception 'daily address limit reached' using errcode = 'P0001';
  end if;

  -- Log first, then release. If the insert fails, nothing is disclosed.
  insert into address_disclosures (claim_id, kitchen_id, buyer_id)
  values (p_claim, v_kitchen, auth.uid());

  return query
    select kl.street, kl.city, kl.postal_code,
           ST_Y(kl.exact_point::geometry),
           ST_X(kl.exact_point::geometry)
      from kitchen_locations kl
     where kl.kitchen_id = v_kitchen;
end $$;

revoke all on function reveal_address(uuid) from public, anon;
grant execute on function reveal_address(uuid) to authenticated;

comment on function reveal_address is
  'The ONLY path to a home address. Cook-confirmed claims only, rate-limited, '
  'and every call writes an address_disclosures row.';
