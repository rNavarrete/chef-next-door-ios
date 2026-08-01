# Onboarding — the spec

Written after reading the research rather than before. The short version: the
thing most apps ship — a five-card carousel on first launch — is the one format
the evidence is against.

Nielsen Norman Group tested exactly that pattern with 70 users across 4 apps.
Tutorials **did not improve task performance**, and they "make the interface
appear more complicated than it actually is". Three reasons they fail: people
want to start using the thing, the interruption gets skipped, and guidance given
out of context cannot be recalled at the moment it is needed.

The finding that actually matters is not about format at all. The *same* modal
shown at the right behavioural trigger completes 47% of the time; at the wrong
trigger 38% of people dismiss it in under four seconds. **Trigger beats
format.** Everything below is organised around triggers.

- <https://www.nngroup.com/articles/mobile-app-onboarding/>
- <https://www.nngroup.com/articles/onboarding-tutorials/>
- <https://www.chameleon.io/blog/onboarding-ux-patterns>

## What we are not building

**No carousel.** See above.

**No feature tour.** Nobody remembers a tour of a screen they have not needed
yet.

**No "are you a cook or a buyer?" fork.** It forces a decision before anyone has
seen anything worth deciding about, and the overwhelming majority are buyers.
The current routing is already right: everyone browses as a buyer, and "Start a
kitchen" is offered once, as a choice, in Account. Marketplace guidance is to
onboard the supply side *personally* — a phone call, not a screen.

**No tutorial for the light metaphor.** See the last section; the answer there
is to change the words, not teach them.

---

## A. The welcome screen — one screen, first launch only

The research does support a first screen that states what the app is: the core
problem it solves, before any feature explanation. One screen. Not five.

**Trigger:** first launch ever. `UserDefaults` key
`litkitchen.hasSeenWelcome`. Shown after the splash, before the feed.

**Why it earns its place:** three facts about this app are not inferable from
looking at it, and getting any of them wrong costs a real interaction — someone
expecting a checkout, or expecting delivery, or not realising the food is being
cooked *now*.

```
        [ chef illustration, the one from the splash ]

              Neighbours cooking today

    Home cooks near you, making food right now.

    Message them, arrange a pickup, and pay them
    directly — we never take a payment or a fee.

    Everyone here is somebody's neighbour.

            [  Find food near me  ]        <- primary
                  Not now                  <- text button
```

**"Find food near me" is also the location prime.** It requests location
authorisation, so Apple's dialog arrives immediately after a sentence explaining
why — rather than cold on launch, which is what happens today. "Not now" goes
straight to the feed with no system prompt, and location can still be granted
later from the map.

**Rules:** dismissible, once, never again. No progress dots, because there is
nothing to progress through.

---

## B. Push permission — a soft ask, twice, at two different moments

The highest-value change in this document, and the one fixing a real defect:
`requestAuthorizationIfNeeded()` is called from exactly one place — sending a
message in `ThreadView`. **A cook who sets up a kitchen and waits for buyers is
never asked at all**, so the first message arrives silently.

The pattern is well evidenced. Show your own screen first; fire Apple's prompt
**only** if they say yes. Priming lifts opt-in 2–3×, and it matters because iOS
baseline opt-in is about 54%, and a cold up-front prompt lands at 40–45%. Apple
gives one attempt, ever — a "Don't Allow" is only recoverable through Settings.

- <https://www.pushengage.com/ios-push-notification-permission/>
- <https://onesignal.com/blog/how-to-create-more-compelling-opt-in-messages-for-ios-push/>

### B1 — the cook, when they first turn their light on

**Trigger:** `open_kitchen` succeeds and `UserDefaults` has no
`litkitchen.askedPushCook`. This is the value moment: they have just told the
neighbourhood they are cooking, so a message is now something they are waiting
for.

```
    You're open. Want to know when someone writes?

    You've just told your neighbours you're cooking.
    We can tell you the moment somebody messages —
    otherwise you'll need to keep checking.

            [  Yes, tell me  ]
                 Not now
```

### B2 — the buyer, when they first follow a kitchen

**Trigger:** first successful follow, `litkitchen.askedPushBuyer`. Following
*is* a request to be told; the notification is the entire feature.

```
    We'll tell you when Estela starts cooking

    That's what following is for. Without
    notifications we've no way to reach you.

            [  Yes, tell me  ]
                 Not now
```

**The rule that makes this work:** "Not now" must never call
`UNUserNotificationCenter.requestAuthorization`. It costs nothing and can be
asked again at the other trigger. Only "Yes, tell me" spends the one attempt.

---

## C. Contextual tips — two, both behaviourally triggered

### C1 — an empty feed teaches search

**Trigger:** feed loads with zero results. Not a timer, not first launch — the
moment the app has nothing to show is exactly when "search somewhere else" is
worth knowing, and it is currently a dead end.

The empty state already reads "No kitchens are lit right now." Add the way out:

```
    Nobody's cooking within 40 miles of you.

    Most of our cooks are in the San Gabriel Valley
    right now. Try searching a ZIP code.

            [  Search another area  ]   -> opens the map's place search
```

### C2 — the burner dial, once

**Trigger:** a cook's first visit to their own kitchen after registering.

One tip anchored to the dial: *"This is your light. Tap it when you start
cooking and neighbours can find you — tap it again when you're done."*

Dismissible, once. This is the only control in the app whose meaning is not
written on it.

---

## D. The light metaphor — change the words, don't teach them

Not onboarding. Listed here because it came up as an onboarding problem and it
is not one.

There are **30+ user-facing strings** built on the metaphor: "lit right now",
"6 lit up", "Your light's off", "Notify me when X lights up", "Turn their light
on for me", "Light went out at 5:45 pm".

If a metaphor needs a tutorial, the tutorial is not the fix. NN/g's finding that
tutorials make an interface *appear* more complicated is precisely this: a
concept that has to be explained up front was already costing you something.
And since the product is moving away from "lit" anyway, teaching it now means
un-teaching it later.

Most of these have a plain replacement that needs no explanation at all:

| Today | Plainly |
|---|---|
| `31 lit near Covina` | `31 cooking near Covina` |
| `6 lit up` | `6 cooking now` |
| `No kitchens are lit right now.` | `Nobody's cooking near you right now.` |
| `Your light's off` | `You're closed` |
| `Neighbours can see your light` | `Neighbours can see you're cooking` |
| `Notify me when Estela lights up` | `Tell me when Estela is cooking` |
| `Turn their light on for me` | `Ask them to open` |
| `Light went out at 5:45 pm` | `Closed at 5:45 pm` |
| `Lit at 5:45 pm · unconfirmed` | `Open since 5:45 pm · not confirmed recently` |

`Cooking right now` already exists in the feed and needs nothing done to it —
which is the point. It was always the clearest string in the app.

Worth keeping the dial itself. A physical control that turns on and off is a
good metaphor *as an object*; it is the vocabulary around it that has to be
explained.

---

## Order to build

1. **B1 and B2**, the push soft-asks. They fix a defect, not just a first
   impression, and cooks are missing messages today.
2. **C1**, the empty feed. It is a dead end right now.
3. **A**, the welcome screen. Highest visibility, lowest urgency.
4. **D**, the language. Independent of all of the above, and shippable in
   pieces.
5. **C2**, the dial tip. Do it last, or skip it if D lands first — plainer
   language may make it unnecessary.
