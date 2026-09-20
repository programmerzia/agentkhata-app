# Testing AgentKhata without an agent

Written for whoever is putting this through its paces before it goes live. It
assumes no bKash agent account, no real operator messages and no pilot shop —
only this machine, a phone or emulator, and an hour.

Read it top to bottom once. The order matters: each section leans on the one
above it.

## What can and cannot be proved this way

**Provable with no agent at all.** Every screen on both surfaces, every
calculation, the parser against every message shape it claims to handle, the
safety behaviour (OTP dropped, fake messages quarantined, duplicates stored
once), day close and its lock, commission arithmetic, baki and reminders,
exports and printed documents, sync including conflicts, and the whole portal.

**Needs a phone in your hand, but no agent account.** Whether Android actually
delivers operator notifications to the listener, whether the phone's battery
saver kills it overnight, the home-screen widget, the app lock, voice entry,
and the pairing deep link.

**Needs a real agent, and nothing else will do.** The exact wording operators
use in 2026, and whether the commission rates match the circular your
distributor is paying against. Everything else on this page is a rehearsal for
those two, which is why the message simulator lets you paste a real message the
moment you get one.

## 1. The automated suites

Run these first. If any of them is red, stop: the manual work below will waste
your time.

```bash
cd corebari-apps
nvm use 22                     # Node 24 segfaults the Next build
pnpm typecheck && pnpm test && pnpm check:conventions && pnpm check:roles && pnpm check:messages

cd ../corebari && npx vitest run

cd "../unknown app/app"
export PATH=$HOME/sdk/flutter/bin:$HOME/sdk/jdk17/bin:$PATH
export JAVA_HOME=$HOME/sdk/jdk17 ANDROID_HOME=$HOME/sdk/android
flutter analyze && flutter test
```

What they cover that you should not re-test by hand: the ledger posting rules
on both sides against one shared fixture file, the parser against every message
shape, and thirteen database-backed sync tests that exercise push, pull,
cursors, conflicts and duplicate transaction ids.

## 2. The portal, from a sandbox

The fastest honest test of the portal needs no account. `/demo` creates a fresh
tenant seeded with a believable fortnight at a busy counter and drops you into
it.

```bash
cd corebari-apps && nvm use 22
pnpm --filter @corebari/agentkhata dev     # http://localhost:3127
```

Then either open `http://localhost:3127/demo` in a browser, or run the smoke
script, which does the same thing and asks for every page and every download:

```bash
apps/agentkhata/scripts/smoke.sh
# or against a deployed portal
apps/agentkhata/scripts/smoke.sh https://agentkhata.corebari.com
```

It checks status codes and content types, not numbers. Twenty-nine checks, and
it exits non-zero if any fails. Numbers are the suites' job.

### The click-through, screen by screen

Do this once in the sandbox with your own eyes. Each line is a thing that has
broken in similar apps and would embarrass you in front of an agent.

| Screen | Look for |
|---|---|
| Dashboard | Float and cash tiles are not clipped. Runway reads as hours, never negative. |
| Entries | Filters change the URL. Back button works. A search for a TrxID finds it. |
| New entry | Cash-only types hide the wallet picker. Expense shows the category picker. |
| Unsorted | Classifying a message posts it and removes it from the inbox. |
| Day close | Type a wrong cash figure: the difference appears with suspect entries beside it. Close it, then try to edit a closed day. |
| Customers | Ageing buckets. Set a credit limit, then give more credit than the limit. |
| Customer detail | Statement opens and prints. The share link opens in a private window with no login. |
| Cards | Sell more cards than the batch holds: it must refuse, not go negative. |
| Expenses | Seed the default categories, set a budget, overspend it. |
| Counters | Two counters compare side by side. Rename one. The ledger filter follows. |
| Reports | Both exports download. Open the Excel one in a spreadsheet: amounts are numbers, TrxIDs are text. |
| Wallets | Edit a commission rate and check the next entry uses it. |
| Import | Download the template, add a row, preview it, then run it. A bad row must block the whole file. |
| Staff, devices, audit | Each loads and lists. Revoking a device shows as revoked. |

Switch to Bangla on every screen at least once. Bangla numerals, Bangla
grouping (12,34,567), and no clipped text at phone width.

### The real signup path

The sandbox skips onboarding, so test that separately, once:

```bash
cd corebari && npx next dev --port 3001
```

Sign up with a phone number, land in `/welcome`, create the business, and check
you arrive at an empty dashboard with one counter and a cash drawer already
made. `NEXT_PUBLIC_SITE_URL` must equal `COREBARI_ISSUER_URL` exactly or the
token is rejected, and redirect URIs are matched exactly, so `localhost` and
`127.0.0.1` are different origins.

## 3. The Android app, with no operator account

Build and install:

```bash
cd "unknown app/app"
export PATH=$HOME/sdk/flutter/bin:$HOME/sdk/jdk17/bin:$PATH
export JAVA_HOME=$HOME/sdk/jdk17 ANDROID_HOME=$HOME/sdk/android

# A phone on the same wifi reaches this machine by its LAN address.
flutter build apk --debug --dart-define=AGENTKHATA_API=http://192.168.0.187:3127
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

For the emulator use `http://10.0.2.2:3127`, which is how the emulator sees its
host.

### Running the emulator

An AVD called `ak_test` is already created on this machine (Android 15,
x86_64, KVM accelerated). Headless, so it costs nothing to leave running:

```bash
export ANDROID_HOME=$HOME/sdk/android
$ANDROID_HOME/emulator/emulator -avd ak_test -no-window -no-audio -no-boot-anim &
adb wait-for-device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n no.osilion.agentkhata/.MainActivity
```

Useful while testing:

```bash
adb exec-out screencap -p > shot.png            # see what it looks like
adb logcat -d | grep -E "E/flutter|FATAL"       # did anything throw
adb shell run-as no.osilion.agentkhata \
  cat /data/data/no.osilion.agentkhata/app_flutter/agentkhata.sqlite > app.sqlite
```

That last one pulls the app's own database, which settles arguments the screen
cannot: whether a message posted, what status it landed in, and what the
commission came out as.

### The message simulator

Debug builds carry a bench for the capture pipeline: **Settings → Message
simulator**. It pushes text through the same ingestion service the notification
listener uses, so the parser, the safety checks, deduplication, the commission
engine and the Unsorted inbox all behave exactly as they will in a shop.

Each row says what it should do. Tap down the list; any row whose result
disagrees with its subtitle is a bug worth filing.

- **Replay a busy hour** fires eleven messages across four operators and ends
  by sending one twice. Expect a full dashboard and exactly one duplicate.
- **Long-press** a row to load it into the composer instead of sending, so you
  can mangle a real shape and watch the parser's confidence fall.
- **Paste a real message** into the composer the day you get one. That is the
  fastest route from "an agent forwarded me this" to a fixture.

It writes to the real books on that phone, so use a test install rather than
one carrying a khata you care about.

### The checklist

| Area | Do this |
|---|---|
| Onboarding | Fresh install, pick Bangla, add wallets with opening balances. |
| Capture | Run the simulator list. Check the dashboard, Unsorted and the quarantine. |
| Manual entry | Add an expense and a baki. Voice button fills the amount and never saves by itself. |
| Day close | Close with a deliberate shortfall; check the adjustment posting. |
| Backup | Export, wipe the app data, restore, and compare the dashboard. |
| App lock | Turn it on, background the app, come back. It must ask. |
| Widget | Add it to the home screen. Check both buttons and the low-float line. |
| Offline | Aeroplane mode: everything still works. Reconnect and watch it sync. |

### What still needs a physical phone

The emulator will not prove these, so do them on hardware before you ship:
notification access surviving a reboot and a night of battery saving, the SMS
receiver if you ship that permission, the fingerprint prompt, the microphone,
and the operator app package names (`adb shell pm list packages | grep -i
nagad`).

## 4. Phone and portal together

1. Portal running, phone on the same wifi, APK built against the LAN address.
2. On the phone: Settings → Cloud sync → Connect. A browser tab opens `/pair`,
   you sign in, and it returns to the app through `agentkhata://paired`.
3. The portal's Devices page should now list the phone with a recent last-seen.
4. Add an entry on the phone, refresh the portal: it appears.
5. Add one in the portal, pull on the phone: it appears.
6. **The conflict case.** Put the phone in aeroplane mode. Edit the same entry
   in both places. Reconnect. The server's version wins, and the losing value is
   recorded in the audit trail rather than thrown away.
7. **The duplicate case.** Use the simulator's "send the last one again". One
   entry, not two, on both sides.

## 5. Before production

Everything above green, plus:

- [ ] `pnpm build` for the portal on Node 22
- [ ] A release APK, not a debug one, built against the production URL
- [ ] `pnpm db:migrate` run on the server
- [ ] DNS for `agentkhata.corebari.com` and `APPS_SSO_SECRET_AGENTKHATA` set
- [ ] `scripts/smoke.sh https://agentkhata.corebari.com` passing against the
      deployed portal
- [ ] Commission rates checked against each operator's current circular
- [ ] At least one real operator message per operator, added to
      `app/test/core/message_parser_test.dart`

The last two are the only items on this page that a real agent has to give you.
Everything else you can finish today.
