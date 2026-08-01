# TestFlight build notes

Paste the **What to Test** section into App Store Connect when you add a build
to a group. The rest is for you.

---

## Beta App Description (paste this)

Required before a build can go to external testers. This is the standing
description of what the app *is* — testers see it in the TestFlight app. The
"What to Test" section below is different: it is per-build, and it changes.

Chef Next Door shows which home cooks near you are cooking right now, across
Southern California. Browse what's being made today, see how far away it is, and
message the cook directly. Nothing is bought or paid for in the app — you
arrange everything with the cook yourself.

---

## What to Test (paste this)

Plain text, no asterisks. TestFlight renders this field literally, so markdown
emphasis reaches testers as `**right now**` and reads like a bug in the thing
they were asked to look for bugs in.

Thanks for trying Chef Next Door. It shows which home cooks near you are
cooking RIGHT NOW, and lets you message them. Nothing is paid for in the app —
you'd arrange everything with the cook directly.

START HERE, or the app will look empty. It only shows kitchens near you, and
all the test kitchens are in Southern California. Open the Map tab, tap the
search bar at the top, and type 91722 (Covina) or 90013 (downtown LA). If
you're already in LA, allow location and skip this.

THE COOKS AREN'T REAL. There are 90 invented ones with placeholder photos, so
the faces won't match the names and some look nothing like home cooks. Their
menus, prices and stories are made up. Don't drive anywhere.

Things I'd love you to try:

1. Find somewhere to eat. Search a ZIP, scroll the Cooking tab, open a kitchen,
   look at a dish and its photos. Does it feel obvious what's available right
   now versus what's just on the menu?
2. Drag the map around. Kitchens should load as you move. Does anywhere feel
   dead or slow?
3. Search for a dish — try "tamales", "birria", "pan dulce", "noodles". Does it
   find what you'd expect? Try it in Spanish too.
4. Make an account from the Account tab, then delete it from the same screen.
   Both should just work.
5. Message a cook. Tap into a kitchen and start a conversation. Then long-press
   it in Messages and delete it.
6. Follow a kitchen that's closed, so you'd hear when they start cooking.
7. Set up your own kitchen if you're curious — Account, then Start a kitchen.
   It asks for a permit; choose "I'll sort this out later" unless you want to
   see the check run, in which case enter PR0313409.

One known gap: notifications have never been confirmed arriving on a real
device. If you follow a kitchen and never hear about it, that's the likely
cause and it's worth telling me.

What's most useful to hear: anywhere you tapped something and nothing happened,
anywhere the wording confused you, and anything that looked broken. Screenshots
help more than descriptions.

---

## For you — before you add the build

- [ ] Confirm the build number is unique. `CURRENT_PROJECT_VERSION` lives in
      `project.yml`; App Store Connect rejects a repeat.
- [x] Seeded kitchens keep cooking on their own now. `close_quiet_kitchens()` was
      shutting 86 of 90 overnight; migration 066 re-confirms the fictional ones
      every four hours. Scoped to seed accounts — verified it modifies zero real
      cook sessions. Remove it before launch, along with the seed itself.
- [x] External testing chosen. Testers get a link and nothing else — no access
      to your App Store Connect account.

## Beta App Review — what external testing actually requires

The first external build is reviewed. It is lighter than full App Store review,
but it is a human opening your app, so the reviewer-facing work matters now
rather than later.

Fill these in App Store Connect before submitting for beta review:

- [ ] **Beta App Description** — what the app is, two or three sentences.
- [ ] **Feedback email** — where tester reports land.
- [ ] **Contact info** — first name, last name, phone, email. Used only if the
      reviewer needs to reach you.
- [ ] **Sign-in required: YES**, with the demo account:
      `demo@litkitchen.app` / `DEMO_PASSWORD`
- [ ] **Review notes** — paste the Review Notes section from
      `docs/APP_REVIEW_NOTES.md`. Its first paragraph is the one that decides
      whether this passes: the reviewer is in Cupertino, every kitchen is in
      Southern California, and without being told to search **91722** on the
      Map tab they open an empty app and reasonably fail it as incomplete.
- [x] **Privacy policy URL** — <https://rnavarrete.github.io/chef-next-door/privacy.html>
      Hosted from its own public repo, `rNavarrete/chef-next-door`. Separate
      from this one on purpose: Pages serves from a repo, and two static pages
      are not a reason to publish the schema and the address-disclosure logic.
      **That copy is canonical.** `docs/privacy.html` here is the draft it came
      from; change the live one first, then copy back.

Beta review usually turns around in under a day. Later builds of the same
version go out without re-review.

## Known, so nobody reports them as new

- **Push alerts are confirmed working on a real device**, 30 July 2026.
  `share_address` from the demo cook produced an APNs 200 against the buyer's
  production token and the notification arrived — verified in Notification
  Center, not inferred from the 200. The banner style is Temporary, so it
  vanishes in seconds; twice now that has been mistaken for nothing having
  happened. Check Notification Center before concluding a push failed.
- **Live Activities are confirmed working on a real device**, 30 July 2026. A
  buyer ordered from Javier O.; the card appeared reading "hasn't answered yet",
  and a `share_address` pushed from the cook's side changed it in place to
  "SAID YES" with the address and a Directions button. Changed remotely, with
  the phone locked and the app closed. Both push types — alert and
  liveactivity — delivered in the same moment.
- **Stale device tokens are not being cleaned up.** In the same test Apple
  returned `410 Unregistered` for a token from a sideloaded Debug build, and
  the row was still in `device_tokens` afterwards. The edge function has the
  right code for this — delete on 410 using the service-role key — so either
  `SUPABASE_SERVICE_ROLE_KEY` is unset in the deployed function's environment
  or the deployment predates that code. Harmless per push, but tokens will
  accumulate forever instead of retiring themselves, and this is the same class
  of problem migration 059 was written for. That one row was removed by hand.
- Cooks outside Los Angeles County are attached to their real county health
  department, but the MEHKO opt-in flag for those counties is set conservatively
  to "not opted in" pending verification. A cook in Orange County will be warned
  that meals may not be permitted. That warning is deliberate and may be wrong.
- The demo kitchen ("Demo Kitchen (Chef Next Door)") is scaffolding for App Review
  and will look odd beside the others.
