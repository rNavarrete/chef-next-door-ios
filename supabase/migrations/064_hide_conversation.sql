-- 064 — let someone remove a conversation from their own list
--
-- ## Why this is not a DELETE
--
-- A conversation has exactly two parties. If deleting it removed the row, a
-- buyer could erase a cook's record of an order — the dishes, the pickup time,
-- the address the cook chose to share — and a cook could erase a buyer's. That
-- is not a delete button, it is a way to destroy someone else's records, and it
-- would sit directly against the complaint that might depend on them.
--
-- So each side hides its own copy. The row survives while either party still
-- wants it, exactly as an email you delete stays in the recipient's inbox. The
-- privacy policy already promises this: "messages you sent remain visible in
-- the other person's copy of the conversation."
--
-- The UI can still call it Delete, because that is what it is from where the
-- person is standing. What it must not do is claim to have deleted it for
-- everyone.
--
-- ## Hidden until someone speaks again
--
-- `hidden_at` is a timestamp rather than a boolean, so a conversation comes
-- back the moment a message arrives that is newer than the hide. Anything else
-- means clearing your list quietly mutes a cook you are mid-order with, and the
-- first you learn of it is a stranger asking why you never replied. Blocking is
-- the feature for not hearing from someone; this one is for tidiness.
--
-- Nothing is destroyed, so there is deliberately no confirmation in the UI —
-- an action that can be undone by the other person typing does not warrant one.

set search_path = public, extensions;

alter table conversations
  add column if not exists cook_hidden_at  timestamptz,
  add column if not exists buyer_hidden_at timestamptz;

comment on column conversations.cook_hidden_at is
  'When the cook cleared this from their list. The conversation reappears if a '
  'message arrives after this time. Never affects the buyer''s copy.';
comment on column conversations.buyer_hidden_at is
  'The buyer''s equivalent. Both null for a conversation nobody has hidden.';

-- ---------------------------------------------------------------------------
-- Hide, for whichever side is asking.
-- ---------------------------------------------------------------------------
create or replace function hide_conversation(p_conversation uuid)
returns void
language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_user uuid := auth.uid();
  v_rows int;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  -- One statement for both sides, so there is no path where a caller who is
  -- neither party writes anything. A stranger's id matches no branch and
  -- updates no rows.
  update conversations
     set cook_hidden_at  = case when cook_id  = v_user then now() else cook_hidden_at  end,
         buyer_hidden_at = case when buyer_id = v_user then now() else buyer_hidden_at end
   where id = p_conversation
     and (cook_id = v_user or buyer_id = v_user);

  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'not your conversation'; end if;
end $$;

revoke all on function hide_conversation(uuid) from public, anon;
grant execute on function hide_conversation(uuid) to authenticated;

comment on function hide_conversation is
  'Removes a conversation from the caller''s own list only. The other party '
  'keeps theirs, and a newer message brings it back for both.';

-- ---------------------------------------------------------------------------
-- The list, now respecting each side's own hide.
-- ---------------------------------------------------------------------------
create or replace function my_conversations()
returns table (
  id uuid, cook_id uuid, buyer_id uuid, other_name text, other_avatar text,
  last_body text, last_kind message_kind, last_payload jsonb,
  last_at timestamptz, unread integer, i_am_the_cook boolean
)
language sql stable security definer
set search_path to 'public', 'extensions'
as $$
  with last_message as (
    select distinct on (m.conversation_id)
           m.conversation_id, m.body, m.kind, m.payload
      from messages m
     order by m.conversation_id, m.created_at desc
  )
  select c.id, c.cook_id, c.buyer_id,
         case when c.cook_id = auth.uid()
              then coalesce(bp.display_name, 'Someone nearby')
              else co.display_name end,
         case when c.cook_id = auth.uid() then bp.avatar_path else co.avatar_url end,
         lm.body, lm.kind, lm.payload,
         c.last_message_at,
         (select count(*)::int from messages m
           where m.conversation_id = c.id
             and m.sender_id <> auth.uid() and m.read_at is null),
         c.cook_id = auth.uid()
    from conversations c
    join cooks co         on co.id = c.cook_id
    left join profiles bp on bp.id = c.buyer_id
    left join last_message lm on lm.conversation_id = c.id
   where (c.buyer_id = auth.uid() or c.cook_id = auth.uid())
     and not (c.cook_id = auth.uid()
              and exists (select 1 from blocked_buyers b
                           where b.cook_id = c.cook_id and b.buyer_id = c.buyer_id))
     -- Show it if I have not hidden it, or if something has been said since I
     -- did. Parenthesised deliberately: a bare `or` here would bind across the
     -- block and the blocked-buyer filters above and quietly undo both.
     --
     -- The other party's hide is never consulted. Their tidying is not mine.
     and (
       case when c.cook_id = auth.uid() then c.cook_hidden_at
            else c.buyer_hidden_at end is null
       or c.last_message_at > case when c.cook_id = auth.uid() then c.cook_hidden_at
                                   else c.buyer_hidden_at end
     )
   order by c.last_message_at desc;
$$;
