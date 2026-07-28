# App Review notes

Paste the **Review Notes** section below into App Store Connect verbatim. The
rest of this file is for you, not for Apple.

---

## Review Notes (paste this)

Lit Kitchen shows which permitted home cooks near you are cooking right now, in
the San Gabriel Valley, California. No payments are taken in the app — buyers
and cooks arrange everything by message and pay each other directly.

**IMPORTANT — please search for a location first.** The app shows kitchens near
you, and all current kitchens are in the San Gabriel Valley, about 350 miles
south of Cupertino. From the **Map** tab, tap the search bar at the top and
enter **91722**, then choose "91722 · Covina". The Cooking tab will then show
the kitchen. Without this step both tabs are correctly empty, because nobody is
cooking near you.

You may decline the location permission — searching a ZIP code or city works
just as well and is a supported way to use the app.

**Demo cook account**
Email: demo@litkitchen.app
Password: DEMO_PASSWORD

Signing in with that account and opening the **Account** tab shows the cook side:
the burner dial that turns a kitchen's light on and off, the menu builder, and
the kitchen's conversations.

**About permits.** Cooks in California need a MEHKO permit from their county to
sell home-cooked meals. When a cook enters a permit number we check it against
Los Angeles County's published register before they can finish setting up, and
only a matched permit earns a badge. The demo account deliberately claims no
permit, so you can see the un-badged state; entering the number **PR0313409**
during kitchen setup will show a successful match.

**Account deletion** is at Account → Delete my account, and for a signed-in cook
in the menu at the top right of the Kitchen tab.

---

## For you — before you submit

- [ ] Host `docs/privacy.html` and put the URL in App Store Connect. Replace
      every highlighted placeholder in it first.
- [ ] Fill in Support URL and Marketing URL.
- [ ] Complete App Privacy (the nutrition labels). They must match
      `PrivacyInfo.xcprivacy`: email, name, phone, physical address, precise
      location, photos, messages, other user content, user ID, device ID — all
      linked to identity, all "App Functionality", none used for tracking.
- [ ] Age rating. There is user-generated content and messaging between
      strangers, so answer that section honestly rather than reaching for 4+.
- [ ] Screenshots for 6.9" and 6.5" iPhone. Take them **after** searching 91722
      so the feed is populated — a screenshot of an empty feed invites the same
      rejection as an empty app.
- [ ] Confirm the demo account still works and the demo kitchen is still lit
      immediately before you submit. Its serving session is real, and the
      cook-side rules close a kitchen that goes quiet for ten hours. If it has
      gone dark, re-run `supabase/seed_review_demo.sql`.

## After approval

Remove the demo kitchen once real cooks are on the platform. It is scaffolding,
not content, and a fake kitchen in a live marketplace is worse than an empty
one:

```
delete from auth.users where email = 'demo@litkitchen.app';
```

## Why the demo kitchen is named what it is

"Demo Kitchen (Lit Kitchen)", not "Maria's Tamales". A real buyer who finds it
before the first genuine cook signs up should be able to tell instantly what
they are looking at. It also claims no permit, because a fake permit badge is
the one thing in this app that must never be faked — the badge is the whole
trust mechanism, and inventing one to make a demo look better would undermine
the thing being demonstrated.
