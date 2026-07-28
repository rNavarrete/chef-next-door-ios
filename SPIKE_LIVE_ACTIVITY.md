# Spike: Live Activity & Control Center burner

*M0 · run 2026-07-25 · Xcode 26.2, iOS 26.2 simulator, Swift 6 strict*

**Question:** can we ship the two native capabilities the product's differentiation rests on — a Lock Screen handoff card for an active claim, and a Control Center toggle for the cook's burner — and what does each actually require?

**Answer:** yes, both build and the Live Activity renders correctly. But **push-updated activities need a signing team**, which is a dependency the plan didn't name, and it changes what "done" means for M3.

---

## Verified working

The Lock Screen card renders as designed: amber lamp dot, `MARÍA IS STILL COOKING SINCE 9:40 AM`, `6 tamales de puerco  $18 · $3 each`, the address, and blue `Text María` / `Directions`.

The design rules survived contact with the platform:

- **Amber marks heat, blue marks affordance.** The lamp dot is the only amber element; both buttons are blue. No amber control.
- **Absolute clock time.** `since 9:40 am`, never an elapsed duration.
- **A handoff card, not a countdown.** No timer, because there's no pickup window to count down to. This turned out to make the implementation *simpler* than the usual Live Activity — nothing needs periodic refresh.
- **Price always carries its unit.** `$18 · $3 each`, same rule as everywhere else.

Also built: the iOS 18 `ControlWidget` for the cook's burner, and the Dynamic Island presentations (compact, minimal, expanded).

---

## Finding 1 — push-updatable activities require a signing team *(affects M3)*

`Activity.request(pushType: .token)` fails on an unsigned build:

```
Error Domain=com.apple.ActivityKit.ActivityInput Code=0
  NSUnderlyingError = SessionCore.PermissionsError Code=3
```

`.token` needs the push entitlement (`aps-environment`), which needs a provisioning profile, which needs `DEVELOPMENT_TEAM` — currently empty in `project.yml`. **Nothing appears at all** in that state; there is no partial degradation.

**Why this matters beyond dev setup:** the whole point of pushing updates is that the *cook's* decay-ladder state changes while the *buyer* is walking to the door. Without push, the card only updates when the buyer foregrounds the app — which is exactly when they don't need it.

**Handled** by attempting `.token` and falling back to `pushType: nil`, recording which path succeeded. That keeps the card working for development and for any user whose push registration fails, while making the degraded mode explicit rather than silent.

**Still required before M3 is genuinely done:** a signing team, then verification on a *physical device* that a server-sent `apns-push-type: liveactivity` payload actually updates a running activity. The simulator cannot test this. Treat M3 as incomplete until that happens.

## Finding 2 — `areActivitiesEnabled` is not consent

`ActivityAuthorizationInfo().areActivitiesEnabled` returned `true`, the activity started successfully, **and then iOS showed** *"Allow Live Activities from Lit Kitchen?"* on the Lock Screen with Don't Allow / Allow.

So the property is a capability check, not a permission result. The first activity a user ever sees is wrapped in a system prompt.

**Product consequence:** don't fire the first Live Activity at an arbitrary moment. It lands attached to a real claim — a decent context to be asked in — but the app should not treat a successful `request` as proof the card will be seen, and should handle a declined prompt without breaking the claim flow.

## Finding 3 — Swift 6 strict concurrency vs. ActivityKit

Three separate errors, all real rather than pedantic:

1. A bare `static let shared` over mutable state is rejected → the manager is `@MainActor`, which is where activity lifecycle belongs anyway.
2. `Activity` and `ActivityContent` carry no `Sendable` annotations, so every `await activity.update(...)` is flagged → `@preconcurrency import ActivityKit`, the documented escape for an unaudited framework.
3. `activity.end(content, dismissalPolicy: .immediate)` still failed after that. **The fix was to stop passing content at all** — with `.immediate` the final state is never rendered, so constructing it was both the compile error and pointless. The compiler was right about something that was also a design smell.

Budget a little time for this in any milestone touching a system framework; it is not free, and it is not always mechanical.

## Finding 4 — a Control Center toggle cannot express hold-to-close

The design specifies **one tap to open, hold to close**, so a cook can't accidentally close their kitchen from a pocket (`DESIGN_BRIEF.md` §6). `ControlWidgetToggle` is a toggle: one tap either way.

Unresolved, and it's a product decision rather than a technical one:

- accept single-tap close from Control Center and rely on the confirmation being cheap to undo; or
- make the control **open-only** (tap to light up; closing happens in-app, where hold works); or
- have the control open the app when turning off.

The middle option looks best — it matches the asymmetry that matters (accidental *opens* are harmless, accidental *closes* cost a cook their afternoon) — but it needs a decision before M1 builds the control for real.

---

## Finding 5 — the card has to start at *claim* time, not at reveal *(found in M3)*

The first real integration started the activity only once the cook confirmed and the address had been fetched. It never once appeared. Two compounding reasons, both worth writing down because neither produces an error:

1. **By the time both conditions held, the buyer was already looking at the app.** Confirmation is the payoff; the wait before it is the part someone locks their phone and walks away from. Starting at confirmation meant the card existed only during the moments it was least needed.
2. **`directionsURL` lived in `ActivityAttributes`, which are frozen at `request` time.** So the activity *structurally could not* start before the address existed — the data model had encoded the wrong lifecycle. Moving it to `ContentState` is what made an earlier start possible at all.

The fix adds a `Stage` (`waiting` / `confirmed`) to `ContentState`. The card goes up when the claim is sent, says `YOLANDA HASN'T ANSWERED YET SINCE 7:38 PM` with a single `Text Yolanda` button, and updates in place to `YOLANDA IS STILL COOKING SINCE 5:57 PM` with the address and `Directions` when the cook says yes.

**The general lesson:** `ActivityAttributes` is for what is fixed for the life of the activity — anything that *becomes* known belongs in `ContentState`, even if it feels like an identifier. Putting it in the wrong half doesn't fail loudly; it just quietly constrains when the activity can start.

Two smaller things this surfaced:

- **`try?` at the call site hid everything.** A card that fails to start is indistinguishable from a card nobody wrote. `CookingActivityManager.sync` now returns the failure and logs it.
- **Which clock the card shows depends on the stage.** Reusing the cook's session-open time while waiting produced `HASN'T ANSWERED YET SINCE 5:57 PM` for a claim placed at 7:38 — technically the session start, but read as plainly wrong. Waiting shows the claim time; confirmed shows how long the cook has been cooking.

---

## What is left before M3

| Item | Blocked on |
|---|---|
| ~~Signing team~~ | **Done.** Team `HCEA5N57HT`, paid membership. `DEVELOPMENT_TEAM` set, `aps-environment: development` in `Sources/LitKitchen/LitKitchen.entitlements` |
| ~~Sign in with Apple~~ | **Done.** Entitlement signed in; Supabase Apple provider enabled. Links to an anonymous user via `linkIdentityWithIdToken`, so it sidesteps the email-confirmation wall that blocks the password upgrade |
| ~~Push Notifications on the App ID~~ | **Done.** Explicit App ID registered; profile `iOS Team Provisioning Profile: com.litkitchen.app` carries `aps-environment: development`, and the signed device binary now has the entitlement |
| Push-updated activity verified end-to-end | Physical device (see below) |
| APNs `liveactivity` payload from the backend | An APNs auth key (`.p8`), plus somewhere to send from |
| Push-to-start token (start an activity without the app running) | iOS 17.2+ API, same App ID dependency |
| Burner control close semantics | Product decision (Finding 4) |

### The simulator cannot verify this, and it lies about why

`Activity.request(pushType: .token)` fails on the simulator with
`SessionCore.PermissionsError Code=3` **even with the team and entitlement
configured** — because simulator builds are ad-hoc signed with *empty*
entitlements (`codesign -dv` reports `TeamIdentifier=not set`). The entitlement
file is simply not applied for the simulator SDK, and there is no APNs there to
get a token from. The error is identical to the one an unsigned build produces,
so the simulator cannot distinguish "not configured" from "correctly configured,
wrong platform". Only a device build proves anything.

Before the App ID existed, the device build failed honestly:

```
error: Provisioning profile "iOS Team Provisioning Profile: *" doesn't include
       the Push Notifications capability.
```

and it now signs with the entitlement present. But note the order of events:
before the entitlement was added to the project at all, that same device build
**succeeded** and silently produced a binary with no `aps-environment`. A green
build is not evidence that push is configured. The check that means something:

```
codesign -d --entitlements :- <path>/LitKitchen.app   # expect aps-environment
```

**Everything above is still only half of push.** The app can now be issued a
per-activity push token; nothing can yet send to it. That needs an APNs auth
key (`.p8`, from Keys in the developer portal), a sender, and a physical
device — the simulator has no APNs at all and returns the same
`PermissionsError Code=3` no matter how the signing is configured.

**Estimate check:** M0 put the Live Activity spike at "ActivityKit push tokens, physical device." The device half is untested and is where the remaining risk lives. The rendering half — the part most likely to have design churn — is done and matches the handoff.

**Local-only is a real constraint, not just a dev fallback.** Without push, the card only changes when the app runs. In the verified run above, the `waiting → confirmed` transition landed because the buyer opened the app — which is exactly the moment the card was supposed to save them. Until push works the Live Activity is a nicer place to *hold* the claim, not a way to *learn* the cook answered.

## Reproducing

The M0 harness in `SpikeHarness.swift` is no longer reachable — the Saved tab hosts the real claims screen since M3. It still compiles and now toggles stage as well as cooking state; wire it into a tab temporarily if you need to drive the card by hand.

For the real path: claim from a cook, then lock the simulator. Confirm as the cook (in-app via the Claims inbox, or with `answer_claim` against the API), reopen the app, and lock again to see the confirmed state.
