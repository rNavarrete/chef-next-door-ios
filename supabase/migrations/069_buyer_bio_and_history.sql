-- 069 — a buyer gets a sentence, and a record of who they've bought from
--
-- Cooks have had `bio` since the beginning — the kitchen "story", the only part
-- of a listing that isn't a permit number. Buyers had a name and a photo, which
-- makes the profile a cook now sees a page of counts about a person with no
-- voice in it.
--
-- The useful version of this is not a personality. It is "I work nights, I
-- usually collect after ten" — the one thing a buyer knows that a cook cannot
-- work out from history. So: short, and public to the cooks who can already see
-- the rest of that page.
--
-- ## Public, and bounded
--
-- No new policy. `profiles_self` (041) already governs this row — you, or a
-- cook you have a conversation with — so the bio inherits exactly the audience
-- the display name has. Nobody who could not already see the person can see it.
--
-- 280 characters, enforced in the column rather than the client. A limit that
-- lives only in a text field is a limit until someone writes to the API.

set search_path = public, extensions;

alter table profiles add column if not exists bio text;

alter table profiles drop constraint if exists profiles_bio_length;
alter table profiles add constraint profiles_bio_length
  check (bio is null or char_length(bio) <= 280);

comment on column profiles.bio is
  'Buyer''s own sentence. Same audience as display_name — see profiles_self.';

-- ---------------------------------------------------------------------------
-- The bio joins the buyer profile a cook reads.
-- ---------------------------------------------------------------------------

drop function if exists buyer_profile(uuid);

create or replace function buyer_profile(p_buyer uuid)
returns table (
  display_name        text,
  avatar_path         text,
  bio                 text,
  member_since        timestamptz,
  orders_with_me      integer,
  pickups_with_me     integer,
  first_order_with_me timestamptz,
  last_order_with_me  timestamptz,
  orders_total        integer,
  pickups_total       integer,
  reviews_written     integer,
  review_for_me       text,
  review_for_me_stars smallint
)
language plpgsql stable security definer
set search_path = public, extensions as $$
declare
  v_me     uuid := auth.uid();
  v_thread uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  select c.id into v_thread
    from conversations c
   where c.cook_id = v_me and c.buyer_id = p_buyer
   order by c.last_message_at desc
   limit 1;

  if v_thread is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  select
    p.display_name, p.avatar_path, p.bio, p.created_at,
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'pickup'),
    (select min(m.created_at) from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),
    (select max(m.created_at) from messages m
       join conversations c on c.id = m.conversation_id
      where c.cook_id = v_me and c.buyer_id = p_buyer and m.kind = 'order'),
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.buyer_id = p_buyer and m.kind = 'order'),
    (select count(*)::int from messages m
       join conversations c on c.id = m.conversation_id
      where c.buyer_id = p_buyer and m.kind = 'pickup'),
    (select count(*)::int from reviews r
       join conversations c on c.id = r.conversation_id
      where c.buyer_id = p_buyer),
    (select r.body from reviews r where r.conversation_id = v_thread limit 1),
    (select r.rating from reviews r where r.conversation_id = v_thread limit 1)
  from profiles p
  where p.id = p_buyer;
end $$;

revoke all on function buyer_profile(uuid) from public, anon;
grant execute on function buyer_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reading and writing your own bio.
-- ---------------------------------------------------------------------------

drop function if exists my_profile();

create or replace function my_profile()
returns table (display_name text, avatar_path text, bio text, created_at timestamptz)
language sql stable security definer
set search_path = public, extensions as $$
  select p.display_name, p.avatar_path, p.bio, p.created_at
    from profiles p where p.id = auth.uid();
$$;

grant execute on function my_profile() to authenticated;

-- `p_bio` is a three-state argument and the distinction matters. Null leaves
-- the existing bio alone, the same rule `p_avatar` already follows — renaming
-- yourself must not silently wipe a sentence you wrote last month. An empty
-- string is a deliberate clear.
create or replace function upsert_my_profile(
  p_name text, p_avatar text default null, p_bio text default null
) returns void
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me   uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_bio  text := trim(coalesce(p_bio, ''));
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if v_name = '' then raise exception 'a name is required'; end if;
  if length(v_name) > 50 then raise exception 'name too long'; end if;
  if length(v_bio) > 280 then raise exception 'bio too long'; end if;

  insert into profiles (id, display_name, avatar_path, bio)
  values (v_me, v_name,
          nullif(trim(coalesce(p_avatar, '')), ''),
          nullif(v_bio, ''))
  on conflict (id) do update
    set display_name = excluded.display_name,
        -- Passing null leaves the existing photo alone; clearing it is a
        -- separate deliberate act, not a side effect of a rename.
        avatar_path  = coalesce(excluded.avatar_path, profiles.avatar_path),
        bio          = case when p_bio is null then profiles.bio
                            else nullif(v_bio, '') end,
        updated_at   = now();
end $$;

grant execute on function upsert_my_profile(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Your own side of the marketplace.
-- ---------------------------------------------------------------------------
--
-- Every kitchen you have bought from, with the review you left it. One list
-- rather than two, because "the cooks I've bought from" and "the reviews I've
-- written" are the same rows read twice — and a review with no kitchen attached
-- is a sentence with nowhere to go.
--
-- Your own history, so nothing here needs guarding beyond `auth.uid()`: it
-- returns rows you are already party to. `SECURITY DEFINER` only so the cook's
-- name and photo come along without a second round trip.

create or replace function my_buying_history()
returns table (
  cook_id      uuid,
  cook_name    text,
  avatar_url   text,
  neighborhood text,
  pickups      integer,
  orders       integer,
  last_at      timestamptz,
  my_rating    smallint,
  my_review    text,
  reviewed_at  timestamptz
)
language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  return query
  select
    ck.id, ck.display_name, ck.avatar_url, k.neighborhood,
    (select count(*)::int from messages m
      where m.conversation_id = c.id and m.kind = 'pickup'),
    (select count(*)::int from messages m
      where m.conversation_id = c.id and m.kind = 'order'),
    c.last_message_at,
    r.rating, r.body, r.created_at
  from conversations c
  join cooks ck on ck.id = c.cook_id
  left join kitchens k on k.cook_id = ck.id
  left join reviews r on r.conversation_id = c.id
  where c.buyer_id = v_me
  order by c.last_message_at desc;
end $$;

revoke all on function my_buying_history() from public, anon;
grant execute on function my_buying_history() to authenticated;

comment on function my_buying_history() is
  'Kitchens the caller has bought from, with their own review of each. Reads '
  'only rows the caller is party to.';
