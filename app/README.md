# AgentKhata — Android client

Flutter. The half of AgentKhata that sits on the counter: it captures operator
messages, keeps the whole khata on the phone with no account, and syncs to the
CoreBari portal when the agent chooses to connect.

Read [../README.md](../README.md) first for how the pieces fit together, and
[../docs/EXECUTION_PLAN.md](../docs/EXECUTION_PLAN.md) for why each decision
went the way it did.

## Layout

| Path | What lives there |
|---|---|
| `lib/core/parser` | Operator message to entry. Fake-message detection, OTP stripping. |
| `lib/core/ledger` | Posting rules, float advisor. Mirrors the server, pinned by shared fixtures. |
| `lib/core/commission` | Rate tables in parts per million. |
| `lib/data` | Drift database, repository, backup and restore. |
| `lib/sync` | Push, pull and conflict reporting against `/api/m/*`. |
| `lib/features` | The screens, one directory each. |
| `android/app/src/main/kotlin` | Notification listener, SMS receiver, native message queue, home-screen widget. |

## Running it

```bash
export PATH=$HOME/sdk/flutter/bin:$HOME/sdk/jdk17/bin:$PATH
export JAVA_HOME=$HOME/sdk/jdk17 ANDROID_HOME=$HOME/sdk/android

flutter analyze
flutter test
flutter build apk --debug --dart-define=AGENTKHATA_API=http://10.0.2.2:3127
```

`10.0.2.2` is the host as seen from the Android emulator. On a real phone use
the machine's LAN address.

## Things worth knowing before changing code

**Money is integer paisa.** `Paisa` is an extension type over `int`. There is no
double anywhere near an amount, and `Paisa.format()` does Bangladeshi grouping
(12,34,567.89), not thousands.

**The ledger rules are duplicated on purpose** and pinned by
`test/fixtures/ledger.fixtures.json`, whose hash is checked against the server's
copy. Refresh with `scripts/sync-fixtures.sh` after changing the server rules,
and expect both suites to fail until they agree.

**The lock wraps the router, not a route.** `AppLockGate` sits in
`MaterialApp.router`'s builder because the pairing deep link would otherwise
route around a shutter placed inside the tree.

**The home-screen widget paints strings, never numbers.** Every visible value is
formatted in Dart and written to shared preferences; `HomeScreenWidget.kt` only
lays them out. A widget provider has no Flutter engine, no locale and about ten
seconds, so summing a ledger there would be an ANR waiting to happen.

**Voice entry never saves.** `VoiceAmountButton` fills the amount field and
stops. A mishearing that costs a glance is a nuisance; one that posts money is a
loss.
