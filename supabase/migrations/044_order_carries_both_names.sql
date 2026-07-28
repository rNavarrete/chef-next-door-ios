-- 044 — an order line carries both names
--
-- 043 resolved dish names with `coalesce(name_es, name_en)`, inherited from
-- `claim_inbox` (020). That rule was written when the order summary was
-- **cook-facing only**, and it was right for that: the cook named the dish, and
-- should see it back the way they wrote it.
--
-- Moving the order into a shared thread broke the assumption. One string now
-- has two readers who may not read the same language, and it showed
-- immediately: a buyer on an English device picked "Pork tamale" and watched it
-- confirm as "Tamal de puerco en rojo". Same dish, and no way for them to know
-- that.
--
-- So the payload carries both, and each side renders whichever it renders
-- everywhere else (`MenuItem.displayName`). This is not localisation work —
-- nothing new is being translated. It is the app being consistent about a name
-- it already had in two forms.
--
-- `name` stays, unchanged, for rows written by 043 and as the canonical record
-- of what was ordered.

set search_path = public, extensions;

create or replace function post_order(p_cook uuid, p_items jsonb, p_note text default null)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_me      uuid := auth.uid();
  v_gate    text;
  v_thread  uuid;
  v_lines   jsonb;
  v_total   int;
  v_summary text;
  v_message uuid;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  v_gate := sender_can_message();
  if v_gate = 'anonymous' then
    raise exception 'sign in to order' using errcode = 'P0002';
  elsif v_gate = 'no_profile' then
    raise exception 'add your name to order' using errcode = 'P0003';
  end if;

  if v_me = p_cook then raise exception 'a cook cannot order from themselves'; end if;
  if exists (select 1 from blocked_cooks b
              where b.blocker_id = v_me and b.cook_id = p_cook) then
    raise exception 'not authorized';
  end if;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', mi.id,
           -- Canonical record of what was ordered, cook's naming first.
           'name',         coalesce(mi.name_es, mi.name_en),
           -- Both forms, so each reader gets the one they'd see anywhere else.
           'name_en',      mi.name_en,
           'name_es',      mi.name_es,
           'quantity',     (i ->> 'quantity')::int,
           'unit_cents',   mi.amount_cents
         ) order by mi.sort_order),
         sum(mi.amount_cents * (i ->> 'quantity')::int)::int,
         string_agg((i ->> 'quantity') || '× ' || coalesce(mi.name_es, mi.name_en),
                    ', ' order by mi.sort_order)
    into v_lines, v_total, v_summary
    from jsonb_array_elements(p_items) i
    join menu_items mi on mi.id = (i ->> 'menu_item_id')::uuid
   where mi.cook_id = p_cook
     and mi.is_available
     and (i ->> 'quantity')::int between 1 and 99;

  if v_lines is null then
    raise exception 'nothing orderable in that request' using errcode = 'P0001';
  end if;

  if exists (select 1 from blocked_buyers b
              where b.cook_id = p_cook and b.buyer_id = v_me) then
    return gen_random_uuid();
  end if;

  insert into conversations (cook_id, buyer_id)
  values (p_cook, v_me)
  on conflict (cook_id, buyer_id) do update set last_message_at = now()
  returning id into v_thread;

  insert into messages (conversation_id, sender_id, body, kind, payload)
  values (v_thread, v_me,
          v_summary || ' · $' || to_char(v_total / 100.0, 'FM999990.00'),
          'order',
          jsonb_build_object('lines', v_lines, 'total_cents', v_total,
                             'note', nullif(trim(coalesce(p_note, '')), '')))
  returning id into v_message;

  return v_message;
end $$;

revoke all on function post_order(uuid, jsonb, text) from public, anon;
grant execute on function post_order(uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The inbox preview has the same problem, one line further out.
--
-- `messages.body` is a single stored string, so the preview inherited the
-- cook's naming too. Returning the kind and payload alongside it lets the
-- client rebuild an order preview in the reader's own language — and leaves
-- plain text alone, which needs no such treatment.
-- ---------------------------------------------------------------------------
drop function if exists my_conversations();

create or replace function my_conversations()
returns table (
  id            uuid,
  cook_id       uuid,
  buyer_id      uuid,
  other_name    text,
  other_avatar  text,
  last_body     text,
  last_kind     message_kind,
  last_payload  jsonb,
  last_at       timestamptz,
  unread        integer,
  i_am_the_cook boolean
)
language sql stable security definer
set search_path = public, extensions as $$
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
   order by c.last_message_at desc;
$$;

grant execute on function my_conversations() to authenticated;
