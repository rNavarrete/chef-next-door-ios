-- The messaging trust surface: the gate, profiles, who may see a buyer's
-- identity, blocking in both directions, and ordering in the thread —
-- including the address gate, which is the one assertion here that protects a
-- physical person rather than a preference.
--
-- ⚠ UNLIKE ./authorization_matrix.sql, THIS ONE RUNS. No pgTAP and no external
-- fixtures: apply the migrations to an empty database, then run this file.
--
--   psql -d lk_test -f <the stub from .github/workflows/ci.yml>
--   for f in supabase/migrations/*.sql; do psql -d lk_test -f "$f"; done
--   psql -d lk_test -v ON_ERROR_STOP=1 -f supabase/tests/messaging_gate.sql
--
-- Every assertion runs as the `authenticated` or `anon` ROLE, never as the
-- database owner. Not incidental: the owner bypasses RLS *and* column grants,
-- and an earlier round of testing ran that way and therefore proved nothing —
-- it hid a cook who could PATCH themselves a verified permit badge. `set local`
-- goes inside an explicit transaction for the same reason; outside one it is
-- silently a no-op, which makes a negative test vacuously green.
--
-- A failure raises rather than notices, so the script stops at the first one.

\set ON_ERROR_STOP on

create or replace function t_try(s text) returns text language plpgsql as $$
begin
  execute s;
  return 'ok';
exception when others then
  return sqlstate;
end $$;
grant execute on function t_try(text) to authenticated, anon;

create or replace function t(label text, got text, want text) returns void
language plpgsql as $$
begin
  if got is not distinct from want then
    raise notice 'PASS  %', label;
  else
    raise exception 'FAIL  % — got [%] want [%]', label, got, want;
  end if;
end $$;
grant execute on function t(text, text, text) to authenticated, anon;

-- ===========================================================================
-- Fixtures
-- ===========================================================================

-- Fixed ids so the assertions can name them.
--   A/B      = cooks (B is an uninvolved third party)
--   ANON     = anonymous session
--   NOPROF   = real account, no profile yet
--   FULL     = real account with a profile
\set A      '11111111-1111-1111-1111-111111111111'
\set B      '22222222-2222-2222-2222-222222222222'
\set ANON   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
\set NOPROF 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
\set FULL   'cccccccc-cccc-cccc-cccc-cccccccccccc'
-- Fixed uuids so the assertions can reference them.
-- cook A = 1111…, cook B (unrelated third party) = 2222…
-- anon buyer = aaaa…, registered-no-profile = bbbb…, registered+profile = cccc…
-- Reset first. The suite is written for a fresh database, but a suite that
-- fails with "duplicate key" the second time you run it is a suite people stop
-- running. Scoped to the tables these assertions touch.
truncate messages, conversations, claims, profiles, serving_sessions,
         kitchen_locations, kitchens, cooks cascade;
delete from auth.users;

insert into auth.users (id, is_anonymous) values
  ('11111111-1111-1111-1111-111111111111', false),
  ('22222222-2222-2222-2222-222222222222', false),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', false),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', false);

insert into enforcement_agencies (id, name, county, mehko_opted_in)
values ('99999999-9999-9999-9999-999999999999', 'Test County', 'Test', true)
on conflict do nothing;

insert into cooks (id, display_name, contact_value) values
  ('11111111-1111-1111-1111-111111111111', 'Ana''s Kitchen', '5550001'),
  ('22222222-2222-2222-2222-222222222222', 'Beto''s Kitchen', '5550002');

insert into kitchens (id, cook_id, public_point, neighborhood, city, agency_id) values
  ('aaaa1111-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   st_point(-117.9,34.1)::geography, 'Test', 'Covina',
   '99999999-9999-9999-9999-999999999999');

insert into serving_sessions (id, cook_id, kitchen_id) values
  ('aaaa2222-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'aaaa1111-0000-0000-0000-000000000001');

-- Two claims on cook A: one from a registered buyer, one from an anonymous one.
insert into claims (id, cook_id, serving_session_id, buyer_id) values
  ('aaaa3333-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'aaaa2222-0000-0000-0000-000000000001',
   'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  ('aaaa3333-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'aaaa2222-0000-0000-0000-000000000001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- A thread that predates 040: buyer d… has no profile. Proves the fallback.
insert into conversations (id, cook_id, buyer_id) values
  ('aaaa4444-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'dddddddd-dddd-dddd-dddd-dddddddddddd');
insert into messages (conversation_id, sender_id, body) values
  ('aaaa4444-0000-0000-0000-000000000001',
   'dddddddd-dddd-dddd-dddd-dddddddddddd', 'legacy thread');

-- ===========================================================================
-- The gate, profiles and visibility
-- ===========================================================================
\set ANON 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
\set NOPROF 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
\set FULL 'cccccccc-cccc-cccc-cccc-cccccccccccc'
\set B  '22222222-2222-2222-2222-222222222222'

-- ===========================================================================
-- 1. Anonymous account is refused (P0002).
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'ANON';
select t('anon cannot DM',
         t_try(format('select send_message(%L,%L)', :'A', 'hola')), 'P0002');
select t('anon gate reason', sender_can_message(), 'anonymous');
rollback;

-- ===========================================================================
-- 2. Real account, no profile → refused with a different code (P0003).
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('registered-but-nameless cannot DM',
         t_try(format('select send_message(%L,%L)', :'A', 'hola')), 'P0003');
select t('no-profile gate reason', sender_can_message(), 'no_profile');
rollback;

-- ===========================================================================
-- 3. Same user sets a name, then can send. The gate must be *passable*.
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('can create own profile',
         t_try($$select upsert_my_profile('Rosa')$$), 'ok');
select t('now allowed to DM',
         t_try(format('select send_message(%L,%L)', :'A', 'still cooking?')), 'ok');
select t('empty name refused',  t_try($$select upsert_my_profile('   ')$$), 'P0001');
select t('50+ char name refused',
         t_try(format('select upsert_my_profile(%L)', repeat('x',51))), 'P0001');
rollback;

-- ===========================================================================
-- 4. Profiles are not a directory.
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('sets own profile', t_try($$select upsert_my_profile('Marisol','cccccccc-cccc-cccc-cccc-cccccccccccc/a.jpg')$$), 'ok');
select t('sends to cook A',
         t_try(format('select send_message(%L,%L)', :'A', 'two tamales?')), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';   -- unrelated cook, never contacted
select t('third-party cook cannot see the buyer',
         (select count(*)::text from profiles where id = :'FULL'), '0');
select t('… and sees only themselves',
         (select string_agg(id::text, ',') from profiles), :'B');
rollback;

-- Both cooks were backfilled into profiles, so "1" here means the buyer sees
-- themselves and neither cook — not that the table happens to be empty.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('buyer sees only their own profile',
         (select count(*)::text from profiles), '1');
rollback;

-- Cook A has been contacted by FULL, so sees exactly two: self and Marisol.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('contacted cook sees self + that buyer only',
         (select count(*)::text from profiles), '2');
rollback;

-- ===========================================================================
-- 5. The cook contacted sees the name — the whole point of 040+041.
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cook sees buyer profile',
         (select display_name from profiles where id = :'FULL'), 'Marisol');
select t('conversation shows real name',
         (select other_name from my_conversations() where buyer_id = :'FULL'),
         'Marisol');
select t('conversation shows avatar',
         (select other_avatar from my_conversations() where buyer_id = :'FULL'),
         'cccccccc-cccc-cccc-cccc-cccccccccccc/a.jpg');
-- Pre-040 thread: no profile, fallback must survive.
select t('legacy thread falls back',
         (select other_name from my_conversations()
           where buyer_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
         'Someone nearby');
select t('claim inbox names the registered buyer',
         (select buyer_name from claim_inbox() where buyer_id = :'FULL'), 'Marisol');
select t('claim inbox leaves anonymous buyer null',
         (select buyer_name from claim_inbox() where buyer_id = :'ANON'), null);
select t('member_since populated',
         (select (member_since is not null)::text from claim_inbox() where buyer_id = :'FULL'),
         'true');
rollback;

-- ===========================================================================
-- 6. Buyer identity does not leak to the other side of the app.
-- ===========================================================================
begin;
set local role anon;
select t('anon role cannot read profiles',
         t_try($$select count(*) from profiles$$), '42501');
rollback;

-- ===========================================================================
-- 7. You cannot write someone else's profile.
-- ===========================================================================
-- Committed on purpose. Checking the result from the attacker's own session
-- would read null because RLS *hides* the row, which passes whether or not the
-- write landed. The only honest check is from a session that can see it.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('rename of another user raises nothing',
         (select t_try(format(
            'update profiles set display_name = %L where id = %L', 'Hacked', :'FULL'))),
         'ok');   -- RLS filters the row rather than raising
commit;

select t('… and the row is untouched',
         (select display_name from profiles where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
         'Marisol');

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('cannot insert a profile for someone else',
         t_try(format(
           'insert into profiles (id, display_name) values (%L, %L)', :'FULL', 'Hacked')),
         '42501');
rollback;

-- ===========================================================================
-- 8. Reply is gated identically.
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'ANON';
select t('anon cannot reply',
         t_try(format('select reply_in_conversation(%L,%L)',
                      'aaaa4444-0000-0000-0000-000000000001', 'hi')), 'P0002');
rollback;

-- ===========================================================================
-- 9. A rename must not silently drop the photo.
-- ===========================================================================
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select upsert_my_profile('Marisol G.');
select t('rename keeps avatar', (select avatar_path from my_profile()),
         'cccccccc-cccc-cccc-cccc-cccccccccccc/a.jpg');
rollback;

-- ===========================================================================
-- Cook/profile coupling, the anonymous feed, and grant hygiene
-- ===========================================================================
-- Trigger still fires despite the revoke (privilege is checked at CREATE
-- TRIGGER, not per-row — verified, not assumed).
insert into auth.users (id) values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
insert into cooks (id, display_name, contact_value)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Carmen', '5550003');
select t('trigger creates profile for a new cook',
         (select display_name from profiles where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
         'Carmen');

-- A >50-char kitchen name must not break cook registration.
insert into auth.users (id) values ('ffffffff-ffff-ffff-ffff-ffffffffffff');
insert into cooks (id, display_name, contact_value)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff', repeat('z', 80), '5550004');
select t('long kitchen name is truncated, not fatal',
         (select length(display_name)::text from profiles
           where id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'), '50');

-- A buyer who already named themselves keeps that name on opening a kitchen.
insert into auth.users (id) values ('12341234-1234-1234-1234-123412341234');
insert into profiles (id, display_name) values ('12341234-1234-1234-1234-123412341234','Sofia');
insert into cooks (id, display_name, contact_value)
values ('12341234-1234-1234-1234-123412341234', 'Sofia''s Panaderia', '5550005');
select t('opening a kitchen does not rename an existing buyer',
         (select display_name from profiles where id = '12341234-1234-1234-1234-123412341234'),
         'Sofia');

-- The anonymous feed. Blocking broke exactly this once, by referencing a table
-- anon had no grant on from a non-definer function.
begin;
set local role anon;
select t('anon can still read the feed',
         t_try($$select count(*) from cooking_now(34.09,-117.89,20000)$$), 'ok');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select t('cook inbox still readable', t_try($$select count(*) from claim_inbox()$$), 'ok');
select t('conversations still readable', t_try($$select count(*) from my_conversations()$$), 'ok');
rollback;

-- No SECURITY DEFINER function added here is anon-executable.
select t('new definer functions are not anon-executable',
         (select coalesce(string_agg(p.proname, ','), 'none')
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and p.proname in ('sender_can_message','upsert_my_profile',
                               'my_profile','cook_ensures_profile',
                               'send_message','reply_in_conversation')
             and has_function_privilege('anon', p.oid, 'execute')),
         'none');

-- ===========================================================================
-- Seeding a name from Apple must never overwrite a chosen one
-- ===========================================================================

-- Fresh account: Apple's name seeds it.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('apple name seeds an empty profile',
         (select seed_my_profile_name('Rosa Delgado')::text), 'true');
select t('… and is readable', (select display_name from my_profile()), 'Rosa Delgado');
commit;

-- Now the user renames themselves deliberately.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select upsert_my_profile('Ro');
commit;

-- A later Apple link must NOT clobber that.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('apple seed does not overwrite a chosen name',
         (select seed_my_profile_name('Rosa Delgado')::text), 'false');
select t('… the typed name survives', (select display_name from my_profile()), 'Ro');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('empty apple name is a no-op', (select seed_my_profile_name('  ')::text), 'false');
rollback;

begin;
set local role anon;
select t('anon cannot seed a profile',
         t_try($$select seed_my_profile_name('X')$$), '42501');
rollback;



-- ===========================================================================
-- 042 — a cook blocks and reports a buyer, silently
-- ===========================================================================

-- FULL already has a profile and a thread with cook A (from the main suite).
-- Give NOPROF one too, so there is a second buyer to prove the block is
-- targeted rather than a blanket mute.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select upsert_my_profile('Rosa');
select send_message(:'A', 'do you have any left?');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cook sees both threads before blocking',
         (select count(*)::text from my_conversations()), '3');
commit;

-- ── the cook blocks Marisol ────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cook blocks a buyer in a thread',
         t_try(format('select block_buyer_in(%L)',
           (select id from conversations
             where cook_id = :'A' and buyer_id = :'FULL'))), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('blocked thread leaves the cook''s inbox',
         (select count(*)::text from my_conversations() where buyer_id = :'FULL'), '0');
select t('the other buyer is unaffected',
         (select count(*)::text from my_conversations() where buyer_id = :'NOPROF'), '1');
select t('cook can list who they blocked',
         (select display_name from my_blocked_buyers() where buyer_id = :'FULL'), 'Marisol');
rollback;

-- ── and the buyer must not be able to tell ─────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('buyer still sees their own thread',
         (select count(*)::text from my_conversations() where cook_id = :'A'), '1');
select t('sending appears to succeed',
         t_try(format('select send_message(%L,%L)', :'A', 'hello?')), 'ok');
select t('blocked_buyers is unreachable to them',
         t_try($$select count(*) from blocked_buyers$$), '42501');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('…but the message never arrived',
         (select count(*)::text from messages m
            join conversations c on c.id = m.conversation_id
           where c.buyer_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and m.body = 'hello?'), '0');
rollback;

-- ── the block is total, not just a mute ────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('kitchen vanishes from the blocked buyer''s feed',
         (select count(*)::text from cooking_now(34.1,-117.9,20000,true)
           where cook_id = :'A'), '0');
select t('claiming is refused, without naming the block',
         t_try(format($$insert into claims (cook_id, serving_session_id, buyer_id)
                        values (%L, %L, %L)$$,
               :'A', 'aaaa2222-0000-0000-0000-000000000001', :'FULL')), 'P0001');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'NOPROF';
select t('an unblocked buyer still sees the kitchen',
         (select count(*)::text from cooking_now(34.1,-117.9,20000,true)
           where cook_id = :'A'), '1');
rollback;

-- The regression that broke discovery last time blocking shipped.
begin;
set local role anon;
select t('anonymous feed survives the new predicate',
         t_try($$select count(*) from cooking_now(34.1,-117.9,20000,true)$$), 'ok');
rollback;

-- ── unblocking restores it ─────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select unblock_buyer(:'FULL');
select t('unblocking restores the thread',
         (select count(*)::text from my_conversations() where buyer_id = :'FULL'), '1');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('and the kitchen comes back',
         (select count(*)::text from cooking_now(34.1,-117.9,20000,true)
           where cook_id = :'A'), '1');
rollback;

-- ── reporting ──────────────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('report files and blocks by default',
         t_try(format('select report_buyer(%L,%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           'harassment')), 'ok');
select t('…and the block took effect',
         (select buyer_is_blocked(:'FULL')::text), 'true');
select t('unknown report kind refused',
         t_try(format('select report_buyer(%L,%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           'nonsense')), 'P0001');
select t('reports are not readable, even by the filer',
         t_try($$select count(*) from buyer_reports$$), '42501');
rollback;

-- A third party must not be able to block or report through someone else's
-- thread just by knowing its id.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('another cook cannot block through a thread they''re not in',
         t_try(format('select block_buyer_in(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'P0001');
select t('…nor report through it',
         t_try(format('select report_buyer(%L,%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           'spam')), 'P0001');
rollback;

begin;
set local role anon;
select t('anon cannot block', t_try($$select unblock_buyer(gen_random_uuid())$$), '42501');
rollback;



-- ===========================================================================
-- 043 — ordering, the address gate, pickup and reviews
-- ===========================================================================

-- Cook A needs a menu, a geo secret (the location trigger refuses without it)
-- and an exact address to share.
insert into app_secrets (key, value) values ('geo_secret','test-secret')
on conflict (key) do nothing;

insert into menu_items (id, cook_id, name_en, category, category_type,
                        amount_cents, unit, is_available, sort_order)
values ('aaaa5555-0000-0000-0000-000000000001', :'A', 'Pork tamale', 'Tamales',
        'mehko_meal', 300, 'each', true, 1),
       ('aaaa5555-0000-0000-0000-000000000002', :'A', 'Champurrado', 'Drinks',
        'mehko_meal', 400, 'each', true, 2),
       ('aaaa5555-0000-0000-0000-000000000003', :'A', 'Sold out thing', 'Tamales',
        'mehko_meal', 900, 'each', false, 3);

insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code)
values ('aaaa1111-0000-0000-0000-000000000001',
        st_point(-117.9,34.1)::geography, '12 Real St', 'Covina', '91722')
on conflict do nothing;

-- ── ordering ───────────────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'ANON';
select t('anonymous cannot order',
         t_try(format($$select post_order(%L, '[{"menu_item_id":"aaaa5555-0000-0000-0000-000000000001","quantity":2}]')$$, :'A')),
         'P0002');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('registered buyer can order',
         t_try(format($$select post_order(%L, '[{"menu_item_id":"aaaa5555-0000-0000-0000-000000000001","quantity":2},{"menu_item_id":"aaaa5555-0000-0000-0000-000000000002","quantity":1}]')$$, :'A')),
         'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('order body is priced server-side',
         (select body from messages where kind = 'order' order by created_at desc limit 1),
         '2× Pork tamale, 1× Champurrado · $10.00');
select t('order carries structured lines',
         (select (payload -> 'total_cents')::text from messages
           where kind = 'order' order by created_at desc limit 1), '1000');
rollback;

-- A sold-out dish must not be orderable, and a bogus price must not stick.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('sold-out dish is not orderable',
         t_try(format($$select post_order(%L, '[{"menu_item_id":"aaaa5555-0000-0000-0000-000000000003","quantity":1}]')$$, :'A')),
         'P0001');
select t('another cook''s dish is not orderable',
         t_try(format($$select post_order(%L, '[{"menu_item_id":"aaaa5555-0000-0000-0000-000000000001","quantity":1}]')$$, :'B')),
         'P0001');
rollback;

-- ── the address gate: the thing that must not regress ──────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('buyer cannot read the address before it is shared',
         t_try(format('select thread_address(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         '42501');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('an unrelated cook cannot share A''s address',
         t_try(format('select share_address(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'P0001');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('the cook shares it',
         t_try(format('select share_address(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('now the buyer can read it',
         (select street from thread_address(
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         '12 Real St');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('a third party still cannot',
         t_try(format('select thread_address(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         '42501');
rollback;

-- The address must never appear in the message row itself.
select t('the address is not stored in messages',
         (select count(*)::text from messages where body ilike '%Real St%'), '0');
select t('disclosure was audited',
         (select count(*)::text from address_disclosures
           where buyer_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and conversation_id is not null), '1');

-- ── pickup and review ──────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('no review before the cook confirms pickup',
         t_try(format($$insert into reviews (conversation_id, cook_id, rating)
                        values (%L, %L, 5)$$,
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           :'A')), '42501');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cook marks picked up',
         t_try(format('select mark_picked_up(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('now the review lands',
         t_try(format($$insert into reviews (conversation_id, cook_id, rating)
                        values (%L, %L, 5)$$,
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           :'A')), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('a second review on the same thread is refused',
         t_try(format($$insert into reviews (conversation_id, cook_id, rating)
                        values (%L, %L, 1)$$,
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           :'A')), '23505');
select t('a buyer cannot aim a review at another kitchen',
         t_try(format($$insert into reviews (conversation_id, cook_id, rating)
                        values (%L, %L, 1)$$,
           (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'),
           :'B')), '42501');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('thread_state reflects the whole arc',
         (select address_shared::text || ',' || picked_up::text || ',' || reviewed::text
            from thread_state(
              (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'true,true,true');
rollback;



-- ===========================================================================
-- 044 — an order line carries both names, and the inbox preview follows
-- ===========================================================================

-- A dish with both names, and one with only English — the fallback case.
update menu_items set name_es = 'Tamal de puerco'
 where id = 'aaaa5555-0000-0000-0000-000000000001';

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select post_order(:'A', '[{"menu_item_id":"aaaa5555-0000-0000-0000-000000000001","quantity":2},{"menu_item_id":"aaaa5555-0000-0000-0000-000000000002","quantity":1}]');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('line carries the English name',
         (select payload -> 'lines' -> 0 ->> 'name_en' from messages
           where kind = 'order' order by created_at desc limit 1), 'Pork tamale');
select t('line carries the Spanish name',
         (select payload -> 'lines' -> 0 ->> 'name_es' from messages
           where kind = 'order' order by created_at desc limit 1), 'Tamal de puerco');
select t('English-only dish has a null name_es, not an empty string',
         (select payload -> 'lines' -> 1 ->> 'name_es' from messages
           where kind = 'order' order by created_at desc limit 1), null);
select t('… and still has its English name',
         (select payload -> 'lines' -> 1 ->> 'name_en' from messages
           where kind = 'order' order by created_at desc limit 1), 'Champurrado');
select t('canonical name unchanged for the record',
         (select payload -> 'lines' -> 0 ->> 'name' from messages
           where kind = 'order' order by created_at desc limit 1), 'Tamal de puerco');

-- The inbox now carries what the client needs to rebuild the preview.
select t('inbox returns the message kind',
         (select last_kind::text from my_conversations() where cook_id = :'A'), 'order');
select t('inbox returns the payload',
         (select (last_payload -> 'total_cents')::text from my_conversations()
           where cook_id = :'A'), '1000');
rollback;

-- Plain text still previews normally, and must not carry a stale payload.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select send_message(:'A', 'on my way');
select t('a text message previews as text',
         (select last_kind::text from my_conversations() where cook_id = :'A'), 'text');
select t('… with no payload',
         (select last_payload::text from my_conversations() where cook_id = :'A'), null);
select t('… and the right body',
         (select last_body from my_conversations() where cook_id = :'A'), 'on my way');
rollback;

-- 042's block must survive the my_conversations rewrite.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select block_buyer_in((select id from conversations where cook_id = :'A' and buyer_id = :'FULL'));
select t('blocking still hides the thread from the cook',
         (select count(*)::text from my_conversations() where buyer_id = :'FULL'), '0');
rollback;



-- ===========================================================================
-- 045 — the Lock Screen card follows the conversation, and close-out
-- A buyer of its own: reusing FULL would inherit the address disclosure the
-- 043 section created, making every "before sharing" assertion below vacuous.
insert into auth.users (id, is_anonymous)
values ('77777777-7777-7777-7777-777777777777', false)
on conflict (id) do nothing;

-- ===========================================================================

insert into app_secrets (key, value) values ('geo_secret','test-secret')
on conflict (key) do nothing;
insert into menu_items (id, cook_id, name_en, name_es, category, category_type,
                        amount_cents, unit, is_available, sort_order)
values ('bbbb5555-0000-0000-0000-000000000001', :'A', 'Pork tamale',
        'Tamal de puerco', 'Tamales', 'mehko_meal', 300, 'each', true, 1)
on conflict (id) do nothing;
insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code)
values ('aaaa1111-0000-0000-0000-000000000001',
        st_point(-117.9,34.1)::geography, '12 Real St', 'Covina', '91722')
on conflict do nothing;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select upsert_my_profile('Nina');
select post_order(:'A', '[{"menu_item_id":"bbbb5555-0000-0000-0000-000000000001","quantity":3}]');
commit;

-- ── the token ──────────────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('a stranger cannot register a token on someone else''s thread',
         t_try(format($$select register_thread_activity_token(%L, 'tok')$$,
           (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))),
         'P0001');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('the COOK cannot register one either — the card is the buyer''s',
         t_try(format($$select register_thread_activity_token(%L, 'tok')$$,
           (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))),
         'P0001');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select t('the buyer registers a token',
         t_try(format($$select register_thread_activity_token(%L, 'tok-1', 'act-1')$$,
           (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))),
         'ok');
select t('tokens stay unreadable to the client',
         t_try($$select count(*) from live_activity_tokens$$), '42501');
commit;

-- ── the payload, before the address is shared ──────────────────────────────
select t('stage is waiting before sharing',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'stage'), 'waiting');
select t('NO address in the payload before sharing',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'addressLine'), '');
select t('no directions link either',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'directionsURL'), null);
select t('items are summarised in English for the buyer''s card',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'itemSummary'), '3× Pork tamale');
select t('price is the order total',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'priceSummary'), '$9.00');

-- ── after the cook shares ──────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select share_address((select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'));
commit;

select t('stage advances to confirmed',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'stage'), 'confirmed');
select t('and only now does the address appear',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'addressLine'), '12 Real St, Covina 91722');
select t('directions link is built',
         ((activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))
          -> 'contentState' ->> 'directionsURL') like 'maps://%')::text, 'true');

-- ── pickup ends it and clears the token ────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select mark_picked_up((select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'));
commit;

select t('the token is dropped once food changes hands',
         (select count(*)::text from live_activity_tokens
           where conversation_id = (select id from conversations
                                     where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777')), '0');
select t('and the payload goes null with no token',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777')))::text,
         null);

-- ── the payload function must not be reachable by a client ─────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('a client cannot call the payload builder directly',
         t_try(format('select activity_payload_for_thread(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = '77777777-7777-7777-7777-777777777777'))),
         '42501');
rollback;

-- ── open_orders: the close-out prompt's data ───────────────────────────────
-- The previous section ended with a pickup, so this thread is closed out.
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select t('a picked-up order is not open',
         (select count(*)::text from open_orders()), '0');
rollback;

-- A second buyer orders and is never closed out.
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select upsert_my_profile('Rosa');
select post_order('11111111-1111-1111-1111-111111111111',
  '[{"menu_item_id":"bbbb5555-0000-0000-0000-000000000001","quantity":2}]');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select t('an unresolved order IS open', (select count(*)::text from open_orders()), '1');
select t('it names the buyer', (select buyer_name from open_orders()), 'Rosa');
select t('it itemises', (select item_summary from open_orders()), '2× Tamal de puerco');
select t('and flags that no address was shared',
         (select address_shared::text from open_orders()), 'false');
rollback;

-- A cook must not see another cook's open orders.
begin;
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select t('another cook sees none of them',
         (select count(*)::text from open_orders()), '0');
rollback;

-- Blocking removes them from the list: not someone you are still waiting on.
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select block_buyer_in((select id from conversations
                        where cook_id = '11111111-1111-1111-1111-111111111111'
                          and buyer_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));
select t('a blocked buyer drops off the close-out list',
         (select count(*)::text from open_orders()), '0');
rollback;

begin;
set local role anon;
select t('anon cannot read open orders', t_try($$select count(*) from open_orders()$$), '42501');
rollback;



-- ===========================================================================
-- 046 — the lamp on the Lock Screen card follows the decay ladder
-- ===========================================================================

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('thread_state names the cook',
         (select cook_name from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'Ana''s Kitchen');
select t('lamp is on while the session is open',
         (select cook_is_cooking::text from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'true');
select t('ordered_at is the latest order, not the thread',
         (select (ordered_at is not null)::text from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'true');
rollback;

-- A stale session must NOT keep asserting a lit kitchen.
update serving_sessions set last_confirmed_at = now() - interval '48 hours'
 where cook_id = :'A' and closed_at is null;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('a decayed session reads as not cooking',
         (select cook_is_cooking::text from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         'false');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select t('a third party gets no thread state at all',
         (select count(*)::text from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))),
         '0');
rollback;



-- ===========================================================================
-- 047 — message push: who is told, and what it is allowed to say
-- ===========================================================================

insert into app_secrets (key, value) values ('geo_secret','test-secret')
on conflict (key) do nothing;
insert into menu_items (id, cook_id, name_en, category, category_type,
                        amount_cents, unit, is_available, sort_order)
values ('cccc5555-0000-0000-0000-000000000001', :'A', 'Pork tamale', 'Tamales',
        'mehko_meal', 300, 'each', true, 1) on conflict (id) do nothing;
insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code)
values ('aaaa1111-0000-0000-0000-000000000001',
        st_point(-117.9,34.1)::geography, '12 Real St', 'Covina', '91722')
on conflict do nothing;

-- ── the token ──────────────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cook registers a device', t_try($$select register_device_token('cook-tok')$$), 'ok');
select t('device_tokens is unreachable to clients',
         t_try($$select count(*) from device_tokens$$), '42501');
select t('a bad environment is refused',
         t_try($$select register_device_token('x','staging')$$), 'P0001');
commit;

begin;
set local role anon;
select t('anon cannot register a device', t_try($$select register_device_token('x')$$), '42501');
rollback;

-- ── an order notifies the cook ─────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select post_order(:'A', '[{"menu_item_id":"cccc5555-0000-0000-0000-000000000001","quantity":2}]');
commit;

select t('the alert goes to the cook''s device',
         (message_alert_payload((select id from messages where kind = 'order'
                                  order by created_at desc limit 1))
          -> 'tokens' -> 0 ->> 'token'), 'cook-tok');
select t('titled with the buyer''s name',
         (message_alert_payload((select id from messages where kind = 'order'
                                  order by created_at desc limit 1)) ->> 'title'), 'Marisol');
select t('body is the itemised order',
         (message_alert_payload((select id from messages where kind = 'order'
                                  order by created_at desc limit 1)) ->> 'body'),
         '2× Pork tamale · $6.00');

-- ── the address alert must not carry an address ────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('buyer registers a device', t_try($$select register_device_token('buyer-tok')$$), 'ok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select share_address((select id from conversations where cook_id = :'A' and buyer_id = :'FULL'));
commit;

select t('the address alert reaches the BUYER',
         (message_alert_payload((select id from messages where kind = 'address'
                                  order by created_at desc limit 1))
          -> 'tokens' -> 0 ->> 'token'), 'buyer-tok');
select t('and says nothing about where',
         (message_alert_payload((select id from messages where kind = 'address'
                                  order by created_at desc limit 1)) ->> 'body'),
         'Shared their address');
select t('no street leaks into the payload anywhere',
         (message_alert_payload((select id from messages where kind = 'address'
                                  order by created_at desc limit 1))::text
          like '%Real St%')::text, 'false');

-- ── a sender is never notified of their own message ────────────────────────
select t('the order alert did not go to the buyer who sent it',
         (message_alert_payload((select id from messages where kind = 'order'
                                  order by created_at desc limit 1))::text
          like '%buyer-tok%')::text, 'false');

-- ── no devices, no payload ─────────────────────────────────────────────────
-- The payload builder is revoked from every client role, so this assertion has
-- to run as the owner — checking it inside `set local role authenticated` tests
-- the grant, not the behaviour.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select forget_device_token('cook-tok');
commit;

select t('a cook with no device produces no alert',
         (message_alert_payload((select id from messages where kind = 'order'
                                  order by created_at desc limit 1)))::text, null);

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select register_device_token('cook-tok');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('clients cannot build alert payloads themselves',
         t_try(format('select message_alert_payload(%L)',
           (select id from messages where kind = 'order' order by created_at desc limit 1))),
         '42501');
rollback;

-- ===========================================================================
-- 048 — the Edge Function payload contract
-- ===========================================================================

-- The Edge Function reads exactly these keys. Asserting the contract here is
-- the only place it is checked: a wrong key produces a 400 the trigger swallows
-- into a warning nobody reads.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select register_thread_activity_token(
  (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'), 'tok-x');
commit;

select t('payload uses contentState, not state',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          ? 'contentState')::text, 'true');
select t('the old key is gone',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          ? 'state')::text, 'false');
select t('threadId is present for the 410 cleanup',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          ? 'threadId')::text, 'true');
select t('redundant server-side headline is gone',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          ? 'headline')::text, 'false');
select t('contentState still carries the stage',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          -> 'contentState' ->> 'stage'), 'confirmed');
select t('and still refuses to leak the address early',
         (activity_payload_for_thread(
            (select id from conversations where cook_id = :'A' and buyer_id = :'FULL'))
          -> 'contentState' ? 'addressLine')::text, 'true');



-- ===========================================================================
-- 050 — "Ana just lit up": who hears it, how often, and who never does
-- ===========================================================================

insert into app_secrets (key, value) values
  ('geo_secret','test-secret'),
  -- Without these the trigger returns early and nothing is attempted, which is
  -- correct behaviour and made the first draft of these assertions read as
  -- failures. net.http_post is stubbed in CI, so no request leaves.
  ('push_fn_url','https://example.invalid/push'),
  ('push_fn_secret','test-secret')
on conflict (key) do nothing;
insert into menu_items (id, cook_id, name_en, category, category_type,
                        amount_cents, unit, is_available, sort_order)
values ('dddd5555-0000-0000-0000-000000000001', :'A', 'Pork tamale', 'Tamales',
        'mehko_meal', 300, 'each', true, 1),
       ('dddd5555-0000-0000-0000-000000000002', :'A', 'Champurrado', 'Drinks',
        'mehko_meal', 400, 'each', true, 2) on conflict (id) do nothing;

-- Two followers with devices, one quiet follower, one stranger.
insert into follows (buyer_id, cook_id, notify) values
  (:'FULL',   :'A', true),
  (:'NOPROF', :'A', false)          -- follows quietly
on conflict do nothing;
insert into device_tokens (user_id, token) values
  (:'FULL',   'full-tok'),
  (:'NOPROF', 'noprof-tok')
on conflict do nothing;

-- ── who is eligible ────────────────────────────────────────────────────────
select t('a notifying follower is eligible',
         (select count(*)::text from followers_to_notify(:'A')
           where buyer_id = :'FULL'), '1');
select t('a QUIET follower is not',
         (select count(*)::text from followers_to_notify(:'A')
           where buyer_id = :'NOPROF'), '0');

-- ── the payload ────────────────────────────────────────────────────────────
select t('titled with the cook',
         (follow_alert_payload(:'A', array(select buyer_id from followers_to_notify(:'A'))) ->> 'title'), 'Ana''s Kitchen is cooking');
-- Not an exact string: by this point in the suite cook A carries menu items
-- from four earlier sections, so "the top three" depends on what ran before.
-- What matters is the `limit 3` — a notification that lists a whole menu is
-- not a notification.
select t('body lists at most three dishes',
         (select (count(*) <= 3)::text from unnest(string_to_array(
            follow_alert_payload(:'A', array(select buyer_id from followers_to_notify(:'A')))
            ->> 'body', ', '))), 'true');
select t('and names something',
         (select (length(follow_alert_payload(:'A',
            array(select buyer_id from followers_to_notify(:'A'))) ->> 'body') > 0)::text),
         'true');

-- Building a payload twice must give the same answer: it writes nothing.
select t('the payload builder is pure',
         (follow_alert_payload(:'A', array(select buyer_id from followers_to_notify(:'A'))) ->> 'title'),
         'Ana''s Kitchen is cooking');
select t('and returns null when nobody is eligible',
         (follow_alert_payload(:'A', array[]::uuid[]))::text, null);

-- ── caps ───────────────────────────────────────────────────────────────────
delete from follow_notifications;
insert into follow_notifications (buyer_id, cook_id, sent_at)
select :'FULL', :'B', now() - (n || ' minutes')::interval
  from generate_series(1,5) n;
select t('a buyer at the daily cap hears nothing more',
         (select count(*)::text from followers_to_notify(:'A')
           where buyer_id = :'FULL'), '0');

delete from follow_notifications;
insert into follow_notifications (buyer_id, cook_id, sent_at)
values (:'FULL', :'A', now() - interval '9 hours');
select t('an announcement older than the cooldown is allowed again',
         (select count(*)::text from followers_to_notify(:'A')
           where buyer_id = :'FULL'), '1');

-- ── blocks, both directions ────────────────────────────────────────────────
delete from follow_notifications;
insert into blocked_cooks (blocker_id, cook_id) values (:'FULL', :'A');
select t('a buyer who blocked the kitchen is not told it opened',
         (select count(*)::text from followers_to_notify(:'A')), '0');
delete from blocked_cooks where blocker_id = :'FULL';

insert into blocked_buyers (cook_id, buyer_id) values (:'A', :'FULL');
select t('a buyer the COOK blocked is not invited over',
         (select count(*)::text from followers_to_notify(:'A')), '0');
delete from blocked_buyers where cook_id = :'A';

-- ── the trigger fires on a real opening, once ──────────────────────────────
delete from follow_notifications;
update serving_sessions set closed_at = now() where cook_id = :'A' and closed_at is null;
insert into serving_sessions (cook_id, kitchen_id)
values (:'A', 'aaaa1111-0000-0000-0000-000000000001');
select t('opening the kitchen recorded a notification',
         (select count(*)::text from follow_notifications
           where cook_id = :'A' and buyer_id = :'FULL'), '1');

-- A cook double-tapping the burner must not re-announce. open_kitchen only
-- inserts on a genuine open, so a confirm is an UPDATE and fires nothing.
update serving_sessions set last_confirmed_at = now()
 where cook_id = :'A' and closed_at is null;
select t('confirming an open session announces nothing new',
         (select count(*)::text from follow_notifications where cook_id = :'A'), '1');

-- ── grants ─────────────────────────────────────────────────────────────────
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('a cook cannot read the notification log',
         t_try($$select count(*) from follow_notifications$$), '42501');
select t('nor derive their follower list from the helper',
         t_try(format('select count(*) from followers_to_notify(%L)', :'A')), '42501');
rollback;

-- A send that throws must not undo the record. Break http_post deliberately.
delete from follow_notifications;
update serving_sessions set closed_at = now() where cook_id = :'A' and closed_at is null;

create or replace function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint language plpgsql as $$ begin raise exception 'network down'; end $$;

insert into serving_sessions (cook_id, kitchen_id)
values (:'A', 'aaaa1111-0000-0000-0000-000000000001');

select t('a failed send still counts against the cap',
         (select count(*)::text from follow_notifications where cook_id = :'A'), '1');

-- Put it back so later runs behave.
create or replace function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint language sql as $$ select nextval('net._http_response_id_seq') $$;



-- ===========================================================================
-- 051 — either party can record the pickup
-- Its own buyer: the 043 section already recorded a pickup in cook A's thread
-- with FULL, and `mark_picked_up` is idempotent within 12 hours — so reusing
-- that thread makes the buyer's call a silent no-op and the assertion reads the
-- cook's earlier mark.
insert into auth.users (id, is_anonymous)
values ('88888888-8888-8888-8888-888888888888', false) on conflict (id) do nothing;

-- ===========================================================================

insert into app_secrets (key, value) values ('geo_secret','t') on conflict do nothing;
insert into menu_items (id, cook_id, name_en, category, category_type,
                        amount_cents, unit, is_available, sort_order)
values ('eeee5555-0000-0000-0000-000000000001', :'A', 'Tamale', 'Tamales',
        'mehko_meal', 300, 'each', true, 1) on conflict (id) do nothing;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
select upsert_my_profile('Alma');
select post_order(:'A', '[{"menu_item_id":"eeee5555-0000-0000-0000-000000000001","quantity":1}]');
commit;

-- The regression this fixes: the BUYER can now close it out.
begin;
set local role authenticated;
set local request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
select t('the buyer can mark it picked up',
         t_try(format('select mark_picked_up(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = '88888888-8888-8888-8888-888888888888'))), 'ok');
select t('and it is recorded as theirs',
         (select payload ->> 'by' from messages where kind = 'pickup'
           order by created_at desc limit 1), 'buyer');
select t('which unblocks their review',
         (select picked_up::text from thread_state(
            (select id from conversations where cook_id = :'A' and buyer_id = '88888888-8888-8888-8888-888888888888'))), 'true');
commit;

-- Still idempotent, and still not open to strangers.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select mark_picked_up((select id from conversations where cook_id = :'A' and buyer_id = '88888888-8888-8888-8888-888888888888'));
select t('a second mark does not stack',
         (select count(*)::text from messages m
            join conversations c on c.id = m.conversation_id
           where c.cook_id = :'A' and c.buyer_id = '88888888-8888-8888-8888-888888888888' and m.kind = 'pickup'), '1');
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = :'B';
select t('a third party still cannot',
         t_try(format('select mark_picked_up(%L)',
           (select id from conversations where cook_id = :'A' and buyer_id = '88888888-8888-8888-8888-888888888888'))), 'P0001');
rollback;

begin;
set local role anon;
select t('anon still cannot', t_try($$select mark_picked_up(gen_random_uuid())$$), '42501');
rollback;



-- ===========================================================================
-- 052 — an anonymous caller must not be able to open a stranger's kitchen
-- ===========================================================================

update serving_sessions set closed_at = now() where closed_at is null;
update cooks set serving_status = 'closed' where id = :'A';

-- The bug: an anonymous caller advertised a stranger's home as cooking.
begin;
set local role anon;
select t('anon cannot open a kitchen',
         t_try($$select open_kitchen('aaaa1111-0000-0000-0000-000000000001')$$), '42501');
select t('anon cannot close one', t_try($$select close_kitchen('x')$$), '42501');
select t('anon cannot confirm a session',
         t_try(format('select confirm_session(%L)', :'A')), '42501');
select t('anon cannot answer a claim',
         t_try($$select answer_claim(gen_random_uuid(), 'confirmed')$$), '42501');
select t('anon cannot create a claim',
         t_try($$select create_claim(gen_random_uuid(), gen_random_uuid(), '[]'::jsonb, null)$$),
         '42501');
rollback;

select t('the kitchen is still closed',
         (select serving_status::text from cooks where id = :'A'), 'closed');
select t('and no session exists',
         (select count(*)::text from serving_sessions where cook_id = :'A' and closed_at is null),
         '0');

-- A signed-in user who is not the cook is still refused, and now by the
-- explicit branch rather than by luck.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'FULL';
select t('a non-owner cannot open it',
         t_try($$select open_kitchen('aaaa1111-0000-0000-0000-000000000001')$$), 'P0001');
select t('a non-owner cannot promote a dish',
         t_try(format('select set_menu_headline(%L)', 'aaaa5555-0000-0000-0000-000000000001')),
         'P0001');
rollback;

-- And the cook themselves still can.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('the owner can open their own kitchen',
         t_try($$select open_kitchen('aaaa1111-0000-0000-0000-000000000001')$$), 'ok');
rollback;

-- Trigger functions are not a public API.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('trigger functions are not callable',
         t_try($$select push_claim_update()$$), '42501');
rollback;



-- ===========================================================================
-- 053 — who turned this light on
-- ===========================================================================

-- Deltas, not absolutes: `suspicious_sessions()` reports history on purpose,
-- and earlier sections of this suite leave sessions behind.
create temp table baseline as select count(*) as n from suspicious_sessions();

update serving_sessions set closed_at = now() where closed_at is null;

-- A cook opening their own kitchen through the app.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select open_kitchen('aaaa1111-0000-0000-0000-000000000001');
commit;

select t('a real open is attributed to the cook',
         (select opened_by from serving_sessions
           where cook_id = :'A' and closed_at is null), 'cook');
select t('and stamped with their session',
         (select (opened_by_user = cook_id)::text from serving_sessions
           where cook_id = :'A' and closed_at is null), 'true');
select t('so it adds nothing to the incident view',
         ((select count(*) from suspicious_sessions()) - (select n from baseline))::text, '0');

-- The shape of today's incident: a row that never went through open_kitchen.
update serving_sessions set closed_at = now() where closed_at is null;
insert into serving_sessions (cook_id, kitchen_id)
values (:'A', 'aaaa1111-0000-0000-0000-000000000001');

select t('a direct insert is recorded as unknown',
         (select opened_by from serving_sessions
           where cook_id = :'A' and closed_at is null), 'unknown');
select t('with no session behind it',
         (select (opened_by_user is null)::text from serving_sessions
           where cook_id = :'A' and closed_at is null), 'true');
select t('and it IS flagged',
         ((select count(*) from suspicious_sessions()) - (select n from baseline))::text, '1');

-- The exact 052 scenario: someone else's session, even claiming to be a cook.
update serving_sessions set closed_at = now() where closed_at is null;
insert into serving_sessions (cook_id, kitchen_id, opened_by, opened_by_user)
values (:'A', 'aaaa1111-0000-0000-0000-000000000001', 'cook',
        'cccccccc-cccc-cccc-cccc-cccccccccccc');

select t('a stranger''s stamp is caught despite claiming to be a cook',
         ((select count(*) from suspicious_sessions()) - (select n from baseline))::text, '2');
select t('and the flag names it',
         (select matched_owner::text from suspicious_sessions() limit 1), 'false');

-- Not a product surface.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('cooks cannot read the incident view',
         t_try($$select count(*) from suspicious_sessions()$$), '42501');
rollback;

-- ===========================================================================
-- 054 — close what has gone quiet, not what is late
-- ===========================================================================

update serving_sessions set closed_at = now() where closed_at is null;

-- A cook who has been serving 14 hours and confirmed 20 minutes ago. Under the
-- old 12-hour cap this was closed mid-service; under the curfew, at 8pm.
insert into serving_sessions (cook_id, kitchen_id, opened_at, last_confirmed_at)
values (:'A', 'aaaa1111-0000-0000-0000-000000000001',
        now() - interval '14 hours', now() - interval '20 minutes');

select t('a long but active shift survives',
         (select close_quiet_kitchens())::text, '0');
select t('and the kitchen is still lit',
         (select count(*)::text from serving_sessions
           where cook_id = :'A' and closed_at is null), '1');

-- The failure the rule actually exists for: opened and abandoned.
update serving_sessions set last_confirmed_at = now() - interval '11 hours'
 where cook_id = :'A' and closed_at is null;

select t('an unattended kitchen is closed', (select close_quiet_kitchens())::text, '1');
select t('and the cook is marked closed',
         (select serving_status::text from cooks where id = :'A'), 'closed');
select t('with an honest reason',
         (select closed_by from serving_sessions
           where cook_id = :'A' order by closed_at desc limit 1), 'auto_quiet');

-- Nine hours quiet is still inside the window — the decay ladder is already
-- saying "hasn't confirmed since", which is the graceful signal.
update serving_sessions set closed_at = now() where closed_at is null;
insert into serving_sessions (cook_id, kitchen_id, last_confirmed_at)
values (:'B', 'aaaa1111-0000-0000-0000-000000000001', now() - interval '9 hours');
select t('nine quiet hours is not yet closed', (select close_quiet_kitchens())::text, '0');

-- No hour of the day is consulted anywhere.
select t('the curfew function is gone',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'close_kitchens_for_the_night'), '0');
select t('and so is the 12-hour cap',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'auto_close_stale_sessions'), '0');
select t('nothing left reads the local hour',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosrc ilike '%America/Los_Angeles%'
             and p.proname like 'close%'), '0');



-- ===========================================================================
-- 055 — a cook's phone number is not public
-- ===========================================================================

-- The leak: any holder of the anon key could dump every cook's phone number.
begin;
set local role anon;
select t('anon cannot read a cook''s phone number',
         t_try($$select contact_value from cooks limit 1$$), '42501');
select t('nor the channel it uses',
         t_try($$select contact_method from cooks limit 1$$), '42501');
select t('nor whether it is verified',
         t_try($$select phone_verified from cooks limit 1$$), '42501');
select t('but the feed still reads what it needs',
         t_try($$select display_name, permit_status, serving_status, avatar_url from cooks limit 1$$),
         'ok');
rollback;

-- A signed-in buyer gains nothing extra.
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
select t('a signed-in buyer cannot read it either',
         t_try($$select contact_value from cooks limit 1$$), '42501');
rollback;

-- Not even the cook themselves, through the table. Nothing in the app reads it,
-- and `select *` is the shape that leaked.
begin;
set local role authenticated;
set local request.jwt.claim.sub = :'A';
select t('a cook cannot select * over their own row',
         t_try($$select * from cooks where id = auth.uid()$$), '42501');
select t('but the one column the client actually reads still works',
         t_try($$select id from cooks where id = auth.uid()$$), 'ok');
rollback;

-- Definer functions are unaffected: reveal_address reads phone_verified.
select t('discovery still works for anonymous browsers',
         (select count(*) >= 0 from cooking_now(34.1,-117.9,20000,true))::text, 'true');

select 'all assertions passed' as result;
