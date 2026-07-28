-- 051 — either party can say the food changed hands
--
-- 043's `mark_picked_up` is cook-only, and a review is gated on a pickup
-- existing. Put together: **a cook who forgets to tap the button permanently
-- blocks their own reviews**, and the buyer — the person who actually knows
-- whether they collected the food — has no way to say so.
--
-- 027 had this right and said so explicitly: `complete_claim` accepted either
-- party and recorded `completed_by`, because "a handoff confirmed by both sides
-- is the only honest evidence we can get". 043 narrowed it to the cook while
-- porting, with no reason given. This restores it.
--
-- ## Who said so is recorded
--
-- Not decoration. A pickup is the closest thing this app has to evidence that a
-- transaction occurred (`PRD.md` §8, `COUNSEL_QUESTIONS.md` Q3), and "the buyer
-- says they collected it" and "the cook says they handed it over" are different
-- claims with different weight. Flattening them into one undated fact would
-- make the record less useful precisely where it matters most.

set search_path = public, extensions;

create or replace function mark_picked_up(p_thread uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid(); v_is_cook boolean;
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  select (c.cook_id = v_me) into v_is_cook
    from conversations c
   where c.id = p_thread and (c.cook_id = v_me or c.buyer_id = v_me);
  if v_is_cook is null then raise exception 'not authorized'; end if;

  -- Idempotent, as before: tapping twice must not stack pickup events, and the
  -- review gate only asks whether one exists.
  if exists (select 1 from messages m
              where m.conversation_id = p_thread and m.kind = 'pickup'
                and m.created_at > now() - interval '12 hours') then
    return;
  end if;

  insert into messages (conversation_id, sender_id, body, kind, payload)
  values (
    p_thread, v_me,
    case when v_is_cook then 'Marked as picked up' else 'Confirmed they picked it up' end,
    'pickup',
    jsonb_build_object('by', case when v_is_cook then 'cook' else 'buyer' end)
  );

  update conversations set last_message_at = now() where id = p_thread;
end $$;

revoke all on function mark_picked_up(uuid) from public, anon;
grant execute on function mark_picked_up(uuid) to authenticated;

comment on function mark_picked_up is
  'Either party. Records which one in the message payload — a buyer confirming '
  'collection and a cook confirming handover are different statements.';
