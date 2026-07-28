-- 040 — messaging requires a real account
--
-- Claiming stays anonymous on purpose: a buyer establishes identity lazily, at
-- the moment of their first claim, rather than behind a sign-up wall on launch
-- (`SessionController`). Messaging is different in kind.
--
--   * A claim is answerable — the cook says yes or no, and nothing reaches
--     them but a row in an inbox. A message arrives as text a stranger wrote.
--   * An anonymous identity costs nothing to make. Rate limiting one is
--     theatre: the spammer signs in anonymously again and carries on.
--   * There is no recourse. Banning an anonymous user bans a session, not a
--     person.
--
-- So the gate goes here, at the point where a stranger can put words in front
-- of a cook, and nowhere else. Browsing, claiming, following and reviewing are
-- unchanged.
--
-- Checked against `auth.users.is_anonymous` rather than the JWT claim: the
-- function is SECURITY DEFINER and can read the table, and the table is the
-- thing the claim is derived from.

set search_path = public, extensions;

create or replace function sender_has_account()
returns boolean language sql stable security definer
set search_path = public, extensions, auth as $$
  select coalesce(
    (select not u.is_anonymous from auth.users u where u.id = auth.uid()),
    false
  );
$$;

revoke all on function sender_has_account() from public, anon;
grant execute on function sender_has_account() to authenticated;

comment on function sender_has_account is
  'True when the caller is a permanent account. Messaging is gated on this; '
  'claiming deliberately is not.';

create or replace function send_message(
  p_cook  uuid,
  p_body  text,
  p_claim uuid default null
)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me      uuid := auth.uid();
  v_thread  uuid;
  v_recent  integer;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- The registration gate. A distinct errcode so the app can offer sign-in
  -- rather than showing a failure — this is a prompt, not an error.
  if not sender_has_account() then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  end if;

  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;
  if v_me = p_cook then
    raise exception 'a cook cannot open a conversation with themselves';
  end if;
  if not exists (select 1 from cooks where id = p_cook) then
    raise exception 'no such cook';
  end if;
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  select count(*) into v_recent
    from messages m
   where m.sender_id = v_me
     and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  insert into conversations (cook_id, buyer_id, opening_claim)
  values (p_cook, v_me, p_claim)
  on conflict (cook_id, buyer_id) do update
    set last_message_at = now()
  returning id into v_thread;

  insert into messages (conversation_id, sender_id, body)
  values (v_thread, v_me, trim(p_body))
  returning id into v_message;

  return v_message;
end $$;

revoke all on function send_message(uuid, text, uuid) from public, anon;
grant execute on function send_message(uuid, text, uuid) to authenticated;

-- Replying is gated too. A thread can only have been opened by a registered
-- buyer, but an account can be deleted and re-created, and the cheap check
-- costs nothing next to the write it guards.
create or replace function reply_in_conversation(p_thread uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_ok boolean; v_message uuid; v_recent integer;
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if not sender_has_account() then
    raise exception 'sign in to send a message' using errcode = 'P0002';
  end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;

  select (c.buyer_id = v_me or c.cook_id = v_me) into v_ok
    from conversations c where c.id = p_thread;
  if not coalesce(v_ok, false) then raise exception 'not authorized'; end if;

  select count(*) into v_recent
    from messages m where m.sender_id = v_me and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  insert into messages (conversation_id, sender_id, body)
  values (p_thread, v_me, trim(p_body))
  returning id into v_message;

  update conversations set last_message_at = now() where id = p_thread;
  return v_message;
end $$;

revoke all on function reply_in_conversation(uuid, text) from public, anon;
grant execute on function reply_in_conversation(uuid, text) to authenticated;
