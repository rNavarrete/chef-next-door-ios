# TestFlight build notes

Paste the **What to Test** section into App Store Connect when you add a build
to a group. The rest is for you.

---

## What to Test (paste this)

Thanks for trying Lit Kitchen. It shows which home cooks near you are cooking
**right now**, and lets you message them. Nothing is paid for in the app —
you'd arrange everything with the cook directly.

**Start here, or the app will look empty.** It only shows kitchens near you,
and all the test kitchens are in Southern California. Open the **Map** tab, tap
the search bar at the top, and type **91722** (Covina) or **90013** (downtown
LA). If you're already in LA, allow location and skip this.

**The cooks aren't real.** There are 90 invented ones with placeholder photos,
so the faces won't match the names and some look nothing like home cooks. Their
menus, prices and stories are made up. Don't drive anywhere.

Things I'd love you to try:

1. **Find somewhere to eat.** Search a ZIP, scroll the Cooking tab, open a
   kitchen, look at a dish and its photos. Does it feel obvious what's
   available right now versus what's just on the menu?
2. **Drag the map around.** Kitchens should load as you move. Does anywhere
   feel dead or slow?
3. **Search for a dish** — try "tamales", "birria", "pan dulce", "noodles".
   Does it find what you'd expect? Try it in Spanish too.
4. **Make an account** from the Account tab, then **delete it** from the same
   screen. Both should just work.
5. **Message a cook.** Tap into a kitchen and start a conversation. Then
   long-press it in Messages and delete it.
6. **Follow a kitchen** whose light is off, so you'd hear when it comes on.
7. **Set up your own kitchen** if you're curious — Account → Start a kitchen.
   It asks for a permit; choose "I'll sort this out later" unless you want to
   see the check run, in which case enter **PR0313409**.

What's most useful to hear: anywhere you tapped something and nothing
happened, anywhere the wording confused you, and anything that looked broken.
Screenshots help more than descriptions.

---

## For you — before you add the build

- [ ] Confirm the build number is unique. `CURRENT_PROJECT_VERSION` lives in
      `project.yml`; App Store Connect rejects a repeat.
- [x] Seeded kitchens stay lit on their own now. `close_quiet_kitchens()` was
      shutting 86 of 90 overnight; migration 066 re-confirms the fictional ones
      every four hours. Scoped to seed accounts — verified it modifies zero real
      cook sessions. Remove it before launch, along with the seed itself.
- [ ] Decide internal vs external. Internal is instant but the tester becomes a
      User on your App Store Connect account. External needs one Beta App
      Review pass but hands over nothing except the app.

## Known, so nobody reports them as new

- Push notifications and Live Activities have not been tested on a real device
  end to end. They *should* work — the production entitlement is verified in
  the shipped IPA — but nobody has watched one arrive.
- Cooks outside Los Angeles County are attached to their real county health
  department, but the MEHKO opt-in flag for those counties is set conservatively
  to "not opted in" pending verification. A cook in Orange County will be warned
  that meals may not be permitted. That warning is deliberate and may be wrong.
- The demo kitchen ("Demo Kitchen (Lit Kitchen)") is scaffolding for App Review
  and will look odd beside the others.
