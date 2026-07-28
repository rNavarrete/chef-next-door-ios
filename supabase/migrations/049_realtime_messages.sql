-- 049 — messages arrive without a refresh
--
-- Until now a reply only appeared if you left the thread and came back. For an
-- app whose whole premise is *right now* — a buyer walking over, a cook asking
-- "how far away are you?" — that is the difference between a conversation and a
-- page you have to remember to reload.
--
-- ## RLS still applies, and that is the reason this is safe
--
-- Realtime evaluates `messages_parties_read` (039) per subscriber, so a client
-- receives only inserts in threads it is already entitled to read. That matters
-- more than usual here: the channel is *named* after a conversation id, and ids
-- are guessable in the sense that anyone can put one in a filter. Without RLS a
-- filter would be an access-control decision made by the client, which is no
-- decision at all.
--
-- The 'address' message carries no address (043), so even a subscriber who
-- somehow saw one would learn only that a disclosure happened — the street
-- still comes from `thread_address`, behind its own check.
--
-- ## Only `messages`
--
-- Deliberately not `conversations`, `profiles`, or anything else. Each table
-- added to this publication is a table whose every write is evaluated against
-- every subscriber's policies; adding them speculatively costs real work on the
-- database for surfaces that already refresh on appear.

set search_path = public, extensions;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    -- Self-hosted or a fresh project that has never enabled Realtime.
    create publication supabase_realtime;
  end if;

  -- `add table` raises if the table is already a member, and this migration
  -- claims to be re-runnable.
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table messages;
  end if;
end $$;

-- Inserts carry the full new row by default, which is all the client needs —
-- it reloads the thread rather than trusting the payload. `replica identity`
-- would only matter for updates and deletes, and neither is published here.

comment on table messages is
  'Published to supabase_realtime for live delivery. RLS is what scopes a '
  'subscription to its own threads — the channel filter is a convenience, not '
  'a control.';
