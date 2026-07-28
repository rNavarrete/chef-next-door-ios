-- 039 — messages
--
-- The handoff never worked. Every "Text Ana" button in the app opened `sms:`
-- with **no recipient** — a blank Messages compose window — and `contact_value`
-- was never in the discovery payload at all, so the client had no number to
-- put there even if the URL had been built properly. The claim-sent screen,
-- the claims list and the Live Activity card were all dead in the same way.
-- The last step of the core loop has never once functioned.
--
-- ## Why in-app rather than fixing the sms: link
--
-- Fixing it means disclosing the cook's personal phone number to every buyer
-- with a confirmed claim. This schema puts a rate-limited, audited RPC in front
-- of home addresses (004/009) precisely because a cook's location is not ours
-- to hand out; a phone number is the same class of thing, and handing it out
-- freely while guarding the address would be incoherent. Messaging here means
-- the number is never disclosed at all.
--
-- It does reverse "we hand off, we don't host the conversation"
-- (`DESIGN_BRIEF.md`). That was written when the alternative looked free. It
-- isn't: hosting brings retention, moderation and a stronger resemblance to a
-- transaction platform (`COUNSEL_QUESTIONS.md` Q3).
--
-- ## Shape
--
-- One thread per (cook, buyer) pair, not per claim. A buyer who claims from
-- the same cook three times is having one continuing conversation, and
-- splitting it per claim would scatter "is there any left?" across threads.
-- `claim_id` records what *started* it, for context only.
--
-- Messaging is deliberately allowed **before** a claim: the app already offers
-- "Ask if Beto is still cooking" on a stale kitchen, which is a question, not
-- an order. That does open a spam surface, so there is a rate limit below.

set search_path = public, extensions;

create table if not exists conversations (
  id             uuid primary key default gen_random_uuid(),
  cook_id        uuid not null references cooks(id) on delete cascade,
  buyer_id       uuid not null references auth.users(id) on delete cascade,
  -- What prompted it. Nullable: plenty of conversations start before a claim.
  opening_claim  uuid references claims(id) on delete set null,
  created_at     timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  -- One thread per pair, enforced rather than hoped for.
  unique (cook_id, buyer_id)
);

create index if not exists conversations_cook_idx  on conversations (cook_id, last_message_at desc);
create index if not exists conversations_buyer_idx on conversations (buyer_id, last_message_at desc);

create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references auth.users(id) on delete cascade,
  body            text not null check (length(trim(body)) between 1 and 2000),
  created_at      timestamptz not null default now(),
  read_at         timestamptz
);

create index if not exists messages_thread_idx on messages (conversation_id, created_at);

alter table conversations enable row level security;
alter table messages      enable row level security;

-- ---------------------------------------------------------------------------
-- Only the two parties, for both tables. A cook is `cooks.id`, which is the
-- user id, so both sides compare against auth.uid() directly.
-- ---------------------------------------------------------------------------
drop policy if exists conversations_parties on conversations;
create policy conversations_parties on conversations for select
  using (buyer_id = auth.uid() or cook_id = auth.uid());

drop policy if exists messages_parties_read on messages;
create policy messages_parties_read on messages for select
  using (exists (
    select 1 from conversations c
     where c.id = messages.conversation_id
       and (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
  ));

-- Marking read is the only direct write a client makes; everything else goes
-- through send_message() so the thread bookkeeping cannot drift.
drop policy if exists messages_mark_read on messages;
create policy messages_mark_read on messages for update
  using (exists (
    select 1 from conversations c
     where c.id = messages.conversation_id
       and (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
  ))
  with check (exists (
    select 1 from conversations c
     where c.id = messages.conversation_id
       and (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
  ));

grant select on conversations to authenticated;
grant select, update on messages to authenticated;

-- ---------------------------------------------------------------------------
-- Sending.
--
-- An RPC rather than an insert: the thread has to be found-or-created, the
-- sender has to be one of the two parties, `last_message_at` has to move, and
-- the rate limit has to hold. A client-side insert would have to be trusted
-- with all four.
-- ---------------------------------------------------------------------------
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
  v_buyer   uuid;
  v_recent  integer;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;
  if length(trim(p_body)) > 2000 then raise exception 'message too long'; end if;

  -- Either party may send. The cook is identified by their own id, so a cook
  -- messaging "their own" cook id means they are replying in a thread where
  -- the buyer is someone else — resolved below.
  if v_me = p_cook then
    raise exception 'a cook cannot open a conversation with themselves';
  end if;

  if not exists (select 1 from cooks where id = p_cook) then
    raise exception 'no such cook';
  end if;

  v_buyer := v_me;

  -- A blocked buyer cannot start or continue a thread. Blocking is meant to
  -- make a kitchen disappear; leaving the message channel open would defeat it.
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  -- Rate limit. Messaging is open before any claim exists, which is right for
  -- "are you still cooking?" and also the obvious way to spam every kitchen in
  -- the county. Counted per sender across all threads.
  select count(*) into v_recent
    from messages m
   where m.sender_id = v_me
     and m.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'too many messages — try again shortly' using errcode = 'P0001';
  end if;

  insert into conversations (cook_id, buyer_id, opening_claim)
  values (p_cook, v_buyer, p_claim)
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

-- ---------------------------------------------------------------------------
-- Replying as the cook, where the counterparty is the buyer rather than a cook.
-- ---------------------------------------------------------------------------
create or replace function reply_in_conversation(p_thread uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_ok boolean; v_message uuid; v_recent integer;
begin
  if v_me is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'empty message'; end if;

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

-- ---------------------------------------------------------------------------
-- The inbox: every thread you are part of, newest first, with the other
-- party's name and what is unread.
--
-- One call rather than a join the client assembles, because the counterparty's
-- display name lives in `cooks` for one side and nowhere useful for the other —
-- a buyer has no profile, so the cook sees the claim history instead.
-- ---------------------------------------------------------------------------
create or replace function my_conversations()
returns table (
  id            uuid,
  cook_id       uuid,
  buyer_id      uuid,
  other_name    text,
  other_avatar  text,
  last_body     text,
  last_at       timestamptz,
  unread        integer,
  i_am_the_cook boolean
)
language sql stable security definer
set search_path = public, extensions as $$
  select c.id, c.cook_id, c.buyer_id,
         case when c.cook_id = auth.uid()
              then 'Someone nearby'          -- buyers have no public profile
              else co.display_name end,
         case when c.cook_id = auth.uid() then null else co.avatar_url end,
         (select m.body from messages m
           where m.conversation_id = c.id
           order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*)::int from messages m
           where m.conversation_id = c.id
             and m.sender_id <> auth.uid()
             and m.read_at is null),
         c.cook_id = auth.uid()
    from conversations c
    join cooks co on co.id = c.cook_id
   where c.buyer_id = auth.uid() or c.cook_id = auth.uid()
   order by c.last_message_at desc;
$$;

grant execute on function my_conversations() to authenticated;

create or replace function mark_conversation_read(p_thread uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_ok boolean;
begin
  select (c.buyer_id = auth.uid() or c.cook_id = auth.uid()) into v_ok
    from conversations c where c.id = p_thread;
  if not coalesce(v_ok, false) then raise exception 'not authorized'; end if;

  update messages
     set read_at = now()
   where conversation_id = p_thread
     and sender_id <> auth.uid()
     and read_at is null;
end $$;

revoke all on function mark_conversation_read(uuid) from public, anon;
grant execute on function mark_conversation_read(uuid) to authenticated;
