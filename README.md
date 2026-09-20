# AgentKhata (এজেন্ট খাতা)

The ledger for mobile-money agents in Bangladesh. The Android app reads bKash,
Nagad, Rocket and Upay messages and records every transaction on its own; the
portal is where the owner reviews, corrects and reports.

Built as a CoreBari app. The portal lives in `corebari-apps`, the platform
changes in `corebari`, and only the Android client lives in this directory.

## Where everything is

| Piece | Where | What it is |
|---|---|---|
| Android app | `app/` here | Flutter. Capture, offline ledger, sync. |
| Portal and API | `corebari-apps/apps/agentkhata` | Next.js on port 3127. Also serves `/api/m/*`, the phone's sync endpoint. |
| Database | `corebari-apps/packages/db/src/schema/agentkhata` | Postgres schema `agentkhata`, row-level security per tenant. |
| Platform changes | `corebari` | Catalog entry, SSO client, phone-first signup. |
| Plan and decisions | [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md) | D1 to D24, the reasoning behind each. |
| Screenshots | [docs/screenshots/](docs/screenshots/) | Portal at desktop and phone width. |
| Testing it | [docs/TESTING.md](docs/TESTING.md) | How to prove the whole thing works with no agent account. |

## How it works

**Capture.** A Kotlin notification listener reads the operator apps; an
optional SMS receiver covers phones where notifications are off. Both drop OTP
and PIN texts before anything is stored. Messages that arrive while the app is
closed are queued natively and drained on next start.

**Parsing.** `app/lib/core/parser` turns an operator message into an entry. It
detects fake "payment received" texts sent from personal numbers and quarantines
them. Anything it is not confident about lands in the Unsorted inbox rather
than in the books.

**The ledger.** Double-entry, integer poisha, no stored balances. The posting
rules exist twice — Dart on the phone, TypeScript and SQL on the server — and
are pinned by one fixture file both test suites load. Change a rule and both
fail until both agree.

**Sync.** Client-generated ids, server-assigned versions. A push carries the
version it last read; a mismatch is reported as a conflict rather than
overwriting, and the losing value is kept in the audit trail. Deliberately not
last-writer-wins on a timestamp: these phones' clocks are routinely days out.

**On the phone, beyond capture.** An app lock that uses the phone's own
fingerprint or PIN, off until switched on, re-locking whenever the phone is put
down. Bangla voice entry that fills the amount field and leaves the saving to
the agent. A home-screen widget with float, cash, today's takings and any
low-float warning, plus one tap each to add an entry or open the inbox. A float
request to the distributor over WhatsApp, with the amount the float advisor
suggests already in the text. An offline help screen answering the eight
questions support actually gets.

**In the portal, beyond review.** Card and minute-bundle inventory that refuses
an oversell inside the transaction. Expense categories with monthly budgets.
Credit limits checked before the credit is given. Expiring read-only statement
links for customers. Commission reconciliation of the rate table against what
the operator credited, an hourly demand heat-map, a year view, printable day
sheets and statements, CSV and Excel export, CSV import of an old paper khata
that validates every row before writing any, a nightly SMS summary, and a
counters screen that sets each point of sale beside the others.

**Accounts.** Phone number and a texted code, no email and no password. A
number already attached to a password account is refused, because signing that
person in with one text would collapse their password and their SMS second
factor into a single code on a single SIM.

## Running it

Requires Node 22 (Node 24 segfaults the Next build, for every app in the repo),
JDK 17 and the Android SDK. The session that built this installed them under
`~/sdk`.

```bash
# Database and portal
cd corebari-apps
pnpm install
pnpm db:migrate
pnpm --filter @corebari/agentkhata dev        # http://localhost:3127

# Platform, for SSO
cd ../corebari
npx next dev --port 3001

# Android app
cd "unknown app/app"
export PATH=$HOME/sdk/flutter/bin:$HOME/sdk/jdk17/bin:$PATH
export JAVA_HOME=$HOME/sdk/jdk17 ANDROID_HOME=$HOME/sdk/android
flutter test
flutter build apk --debug --dart-define=AGENTKHATA_API=http://10.0.2.2:3127
```

Demo data for a tenant:

```bash
cd corebari-apps/apps/agentkhata
TENANT_ID=<uuid> USER_ID=<uuid> npx tsx --env-file-if-exists=../../.env scripts/seed.ts
```

## Tests

```bash
cd corebari-apps && pnpm typecheck && pnpm test && pnpm check:conventions
cd ../corebari && npx vitest run
cd "../unknown app/app" && flutter analyze && flutter test
```

For the manual side — a seeded sandbox, a portal smoke script and an in-app
simulator that feeds operator messages through the real parser with no operator
account — see [docs/TESTING.md](docs/TESTING.md).

The fixtures that keep the two ledgers in step live at
`corebari-apps/apps/agentkhata/src/server/ledger.fixtures.json`. The Android
copy is verified by hash; refresh it with `app/scripts/sync-fixtures.sh`.

## Before launch

- **Real operator messages.** The parser fixtures are realistic shapes, not
  captured texts. Collect samples from agent phones and add them to
  `app/test/core/message_parser_test.dart`.
- **Commission rates.** The defaults are published figures. Verify each against
  the operator's current agent circular; they are editable per tenant in the
  portal.
- **Operator app package names.** Confirm on a real agent phone
  (`adb shell pm list packages | grep -i nagad`).
- **Play Store SMS permission.** Submit the declaration, or ship with
  notification access only. The app is built to work either way.
