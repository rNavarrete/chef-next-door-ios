-- 029 — completion has exactly one door
--
-- 027 added `complete_claim`, which records *who* marked the handoff done and
-- refuses anything that was never confirmed. `answer_claim` (008) meanwhile
-- takes an arbitrary `claim_status` and writes it straight through — so the
-- cook's "Picked up" button reached `completed` without `completed_at`,
-- without `completed_by`, and without ever passing the confirmed check.
--
-- Two consequences, neither acceptable:
--
--   * A claim could go `pending` → `completed` without the cook ever agreeing
--     to it, which manufactures precisely the "a purchase happened" evidence
--     `PRD.md` §8 and COUNSEL_QUESTIONS.md Q3 are careful not to overstate.
--   * Reviews gate on `completed`, so a cook could unlock a review on a claim
--     they never confirmed.
--
-- `answer_claim` is now the *answer* to a claim — yes, no, didn't show — and
-- completion goes through `complete_claim`. Enforced in the function rather
-- than in the app, because the app is not the only thing that can call it.

set search_path = public, extensions;

create or replace function answer_claim(p_claim uuid, p_status claim_status)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_cook uuid; v_session uuid; v_open uuid;
begin
  if p_status = 'completed' then
    raise exception 'use complete_claim() to mark a claim picked up'
      using errcode = '22023';
  end if;
  if p_status = 'pending' then
    raise exception 'a claim cannot be returned to pending'
      using errcode = '22023';
  end if;

  select cook_id, serving_session_id into v_cook, v_session
    from claims where id = p_claim;

  if v_cook is null or v_cook <> auth.uid() then
    raise exception 'not authorized';
  end if;

  update claims set status = p_status where id = p_claim;

  select id into v_open
    from serving_sessions where cook_id = v_cook and closed_at is null;

  if v_open is not null and v_open = v_session then
    perform confirm_session(v_cook);   -- responding to live demand
  end if;                              -- else: bookkeeping, not cooking
end $$;

-- Backfill: any claim that reached `completed` through the old path has no
-- record of who said so. Left as completed — it did happen — but attributed to
-- nobody rather than guessed at, so the evidence stays honest.
update claims
   set completed_at = coalesce(completed_at, now())
 where status = 'completed'
   and completed_at is null;

comment on function answer_claim is
  'The cook''s answer to a claim: confirmed, cancelled, or no_show. '
  'Completion is complete_claim() — it records who, and requires confirmed.';
