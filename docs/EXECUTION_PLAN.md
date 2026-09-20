# AgentKhata on CoreBari: Execution Plan

Status: EXECUTED on 2026-09-20. P1 to P4 are built, tested and committed to the
working tree; P5 is configured but not deployed (that needs the VPS). See
section 11 for what was built, what changed against this plan, and what is left.

Audience: the engineer or agent session that will implement this. It assumes no memory of the
conversation that produced it. Every path is absolute or repo-relative with the repo named.

Repos involved:

| Alias | Path | Role |
|---|---|---|
| PLATFORM | `/home/ziaur-rahman/WorkGround/Studio/corebari` | Next.js 16 platform: SSO issuer, billing, catalog |
| APPS | `/home/ziaur-rahman/WorkGround/Studio/corebari-apps` | pnpm/turbo monorepo of business apps, shared packages |
| MOBILE | `/home/ziaur-rahman/WorkGround/Studio/unknown app/app` | Flutter Android app (capture + offline ledger) |
| LEGACY | `/home/ziaur-rahman/WorkGround/Studio/unknown app/backend` | Self-hosted Supabase prototype, to be retired |

---

## 0. Decision record

**D1. AgentKhata ships as a CoreBari app, not a standalone SaaS.** One platform for SSO, billing,
tenancy, deploy. Cross-sell to agents who also run shops.

**D2. The Android app is the product; the portal is the companion.** Capture of bKash / Nagad /
Rocket / Upay notifications and SMS only works natively. The portal is for viewing, correcting,
reporting, customers, staff and settings. The portal is a PWA (installable on desktop and phone).

**D3. One backend: the AgentKhata Next.js app owns the data in CoreBari Postgres.** No Supabase in
production. The Flutter sync engine keeps its design (client ids, server versions per row (D10),
soft deletes, server cursor) and swaps transport to the app's HTTP API.

**D4. Phone-first accounts are a platform change, done once, opt-in.** PLATFORM already has phone-OTP
login gated by `users.phone_login_enabled`. We add self-signup that creates a phone-only customer
account with that flag on. Existing password accounts are untouched.

**D5. Native app authentication uses a device token minted by the AgentKhata web app after SSO.**
PLATFORM SSO clients are confidential (client secret). A phone cannot hold that secret, so the phone
never talks to the SSO token endpoint. It opens the web app's login in a Custom Tab, the web app
completes SSO server-side, mints a device token bound to the phone's public key, and hands it back
via an `agentkhata://` deep link. The API accepts `Authorization: Bearer <device token>`.

**D6. Business logic that already exists in MOBILE `lib/core` (parser, ledger postings, commission,
dedup, float advisor, reports) stays in Dart and is mirrored in TypeScript only where the portal
needs server-side numbers (balances, commission totals, P&L). The two implementations are kept in
lock-step by a shared JSON fixture suite (section 6).**

**D7. Customers are `core.parties`. Baki is a SUM over ledger rows, never stored.** Per APPS
`CONTEXT.md` glossary.

Resolved during the grill (each was a fork; the recommended branch was chosen):

**D8. Tenancy.** One tenant per agent business, `counters` inside. A new tenant gets one counter
automatically; the counter concept is hidden in the UI until a second counter is added.
Multi-counter dashboards shipped in the second wave; `counter_id` on rows and "attach phone to counter"
at pairing ship at launch.

**D9. Phone signup and existing accounts.** A number that belongs to a password account is never
logged in by OTP. The user is told to log in with their password; SSO then carries them into
AgentKhata. Phone-only accounts and unknown numbers log in / sign up by OTP.

**D10. Conflicts.** Server-assigned `version` per synced row replaces client-clock LWW. A push
carries `base_version`; a mismatch returns 409 with the server row. The phone auto-resolves:
if the local change touched `status`, local status wins and is re-pushed on the new version;
otherwise the server row is taken. The losing change is appended to `entry_events` so nothing
disappears silently. Field-level merge is backlog. `updated_at` stays for display only.

**D11. Baki repayments are also written to `core.payments`** (`app_source = agentkhata`,
`direction = in`, `method` from the wallet kind) so the same party's payment history is visible
to other CoreBari apps. Other entry types stay inside `agentkhata.entries`.

**D12. Raw message upload is opt-in, default off**, toggled by the owner in Settings with a plain
Bangla explanation. When off, the portal's Unsorted shows only `pending_review` entries.

**D13. Pricing class `business`** from `APP_CLASS_PRICES`. The free tier is the phone's
offline-only mode with no account; connecting to CoreBari starts the normal trial and billing.
No separate cheaper class at launch.

**D14. Staff never self-sign-up.** Owners invite through `@corebari/staff` (`inviteStaff`,
`claimInvite`, `changeStaffRole`, `removeStaff`). Staff phones pair with the staff member's own
session; the owner can revoke any device.

**D15. Demo host at launch.** `agentkhata.corebari.net/demo` using the kernel `demoRoute`,
seeded by `scripts/seed.ts`. Cheap because the pattern exists.

**D16. Enums are stored by name, not by Dart index**, on the server (`cash_in`, `cash_out`, ...).
The Dart side maps by name. Readable rows and no ordering trap.

**D17. Default commission rules** live in one TS constant in `apps/agentkhata/src/server/
commission-defaults.ts`, mirrored in Dart, seeded per tenant on first bootstrap. Server-served
rate updates are P6.

**D18. Time.** `occurred_at` is `timestamptz`; day boundaries use the tenant timezone, default
`Asia/Dhaka`, stored on the tenant settings row. Bangladesh has no DST.

**D19. Wallet reconciliation on first connect covers all wallets, not only cash.** The phone asks
`/api/m/sync/reconcile` for the counter's live wallets and maps local wallets by `(kind,
account_number)`. Exact matches are adopted automatically; ambiguous ones (same kind, no account
number, more than one candidate) prompt the user once to merge or keep.

**D20. Audit trail.** `agentkhata.entry_events` is append-only: who (user or device), what
(created, edited, voided, accepted, conflict_lost), before and after JSON, when. Written by every
mutation path (portal, mobile push, day-close adjustment).

**D21. Portal writes go through the kernel offline queue** (`/api/sync` op envelopes,
`runIdempotent`) like other apps; portal reads use `defineReplica` for offline. The mobile API
(`/api/m/*`) is separate because the phone syncs whole tables, not ops.

**D22. Fixture lock-step across repos.** Canonical `ledger.fixtures.json` lives in APPS. MOBILE
holds a copy plus the file's sha256 in `test/fixtures/FIXTURES_SHA`. A MOBILE test fails if the
copy's hash differs from the recorded one, and `scripts/sync-fixtures.sh` in MOBILE refreshes both.
Any posting-rule change starts with the APPS fixture.

**D23. Flutter web target is removed.** The public portal is the Next.js app. `web/`,
`drift_worker.js`, `sqlite3.wasm` and the web login route are deleted in P4.

**D24. LEGACY is retired in P5.** Supabase stack stopped, `backend/deploy` deleted, migrations
kept in git history, Supabase packages removed from MOBILE.

---

## 1. Target architecture

```
+-----------------------+        HTTPS         +--------------------------------------+
|  Android (Flutter)    |  Bearer device token |  apps/agentkhata (Next.js 15, :3127)  |
|  - notification/SMS   | <------------------> |  - portal UI (AppShell, PWA)          |
|  - Drift SQLite       |  /api/m/*            |  - /api/m/* mobile sync + auth        |
|  - SyncService        |                      |  - /api/sync (web offline queue)      |
+-----------------------+                      |  - server ledger (balances, reports)  |
                                               +-------------------+------------------+
                                                                   | withTenant (RLS)
+-----------------------+     OAuth PKCE (web)   +-----------------v------------------+
|  corebari (PLATFORM)  | <--------------------> |  Postgres 17 (schema agentkhata,   |
|  - SSO issuer, JWKS   |   entitlements HTTP    |  core.parties, core.payments)      |
|  - phone-first signup |                        +------------------------------------+
|  - billing, catalog   |
+-----------------------+
```

Tenant model: one CoreBari tenant = one agent business ("shop"). Multi-counter owners get one
tenant with several `counters` rows; staff are tenant members with role `staff`. This matches how
POS and DueFlow model shops and staff.

---

## 2. Data model (APPS `packages/db/src/schema/agentkhata/`)

Schema `agentkhata`. All tables carry `tenant_id uuid` FK cascade and are registered for RLS.
Money is `bigint` poisha. Timestamps `timestamptz`. Client-generated uuid ids on synced tables.

| Table | Purpose | Key columns |
|---|---|---|
| `counters` | physical counter / shop location | `id`, `tenant_id`, `name`, `is_default` |
| `wallets` | operator wallets, cash, bank, recharge float | `id` (client uuid), `tenant_id`, `counter_id`, `kind` enum (bkash, nagad, rocket, upay, tap, bank, cash, recharge, other), `label`, `account_number`, `is_active`, `opening_poisha`, `opening_at`, `sort_order`, `updated_at`, `deleted_at`, `server_updated_at` |
| `entries` | the ledger (one row per transaction) | `id` (client uuid), `tenant_id`, `counter_id`, `wallet_id`, `type` enum (16 values from MOBILE `TxType`, same order), `amount_poisha`, `fee_poisha`, `commission_poisha`, `counterparty`, `trx_id`, `balance_after_poisha`, `occurred_at`, `source` enum (auto_sms, auto_notification, manual, import, portal), `note`, `party_id` FK `core.parties` nullable, `counter_wallet_id`, `status` enum (posted, pending_review, voided), `created_by` user id, `device_id` nullable, `updated_at`, `deleted_at`, `server_updated_at` |
| `day_closes` | end-of-day snapshot per wallet | `id` text (`YYYY-MM-DD_<wallet_id>`), `tenant_id`, `date`, `wallet_id`, `expected_poisha`, `actual_poisha`, `note`, `closed_at`, `closed_by`, sync columns |
| `commission_rules` | per-operator rate table | `id`, `tenant_id`, `wallet_kind`, `entry_type`, `mode` enum (per_thousand, percent, flat, slab), `value numeric(10,4)` (a rate, not money, so numeric is allowed; add a CI exemption comment), `effective_from`, sync columns |
| `devices` | phones authorised for the mobile API | `id`, `tenant_id`, `user_id`, `name`, `public_key`, `token_hash`, `last_seen_at`, `revoked_at`, `created_at` |
| `raw_messages` | optional server copy of unparsed / suspicious messages for parser improvement (opt-in per tenant) | `id`, `tenant_id`, `device_id`, `sender`, `body`, `received_at`, `parse_status`, `reason` |
| `sync_cursors` | per device per table high-water mark (server side view for diagnostics) | `device_id`, `table_name`, `cursor` |
| `entry_events` | append-only audit trail (D20) | `id`, `tenant_id`, `entry_id`, `actor_user_id`, `actor_device_id`, `action` enum (created, edited, voided, accepted, conflict_lost, adjustment), `before jsonb`, `after jsonb`, `at` |
| `tenant_settings` | per-tenant switches | `tenant_id` PK, `timezone` default `Asia/Dhaka`, `upload_raw_messages` bool default false, `locale` default `bn` |

Every synced table (`wallets`, `entries`, `day_closes`, `commission_rules`) also carries
`version integer not null default 1`, incremented by the server on every accepted write (D10).
Enum columns store names, not integers (D16).

Unique indexes: `entries (wallet_id, trx_id) where trx_id is not null`; `wallets (tenant_id,
counter_id) where kind = 'cash' and deleted_at is null` (exactly one live cash wallet per counter).

Trigger: `server_updated_at := clock_timestamp()` before insert or update on the synced tables.

Wire-up (exact files): `packages/db/src/schema.ts`, `packages/db/src/rls.ts`
(`APP_TABLE_REGISTRIES`, `WIRED_APPS`), `packages/db/src/schema/enums.ts` (`appSource` add
`agentkhata`). Generate with `pnpm db:generate`, apply with `pnpm db:migrate`.

Views (SQL, `security_invoker`): `agentkhata.wallet_balances` and `agentkhata.daily_summary`,
implementing the same posting rules as MOBILE `lib/core/ledger/posting.dart`. Section 6 pins them
with fixtures.

---

## 3. Work breakdown

Phases are ordered so that every phase ends in a deployable, testable state. P1 and P3 can run in
parallel with P2. P4 depends on P1. P5 depends on P1 and P3. P6 depends on all.

### P1. APPS: `apps/agentkhata` skeleton, schema, portal (est. 7 days, scope per section 3b "Launch")

1. Copy `apps/dueflow` structure to `apps/agentkhata`. Package name `@corebari/agentkhata`, port
   3127 in `dev`, `start`, `APP_PUBLIC_URL`. Add to `turbo.json` `globalEnv` any new env var
   (`APPS_SSO_SECRET_AGENTKHATA`, `AGENTKHATA_SW_KILL`). Extend root `check:messages`.
2. `src/app.config.tsx`: `defineApp({ slug: 'agentkhata', name: {en:'AgentKhata', bn:'এজেন্ট খাতা'},
   accent: 'agentkhata', nav: [...], shortcuts: [...], messages })`. Add `'agentkhata'` to the slug
   union in `packages/app-kernel/src/defineApp.ts`. Add accent `agentkhata` to
   `packages/ui/src/tokens.ts` `APP_ACCENTS` (proposal: a teal-green family distinct from `serial`;
   exact hexes chosen by the implementer inside tokens.ts only).
3. Nav (four primary): Home (float dashboard), Entries, Day close, Baki. Secondary: Reports,
   Customers, Staff, Devices, Settings. Shortcuts: Add entry, Close day, Unsorted.
4. Schema per section 2, migration generated and applied locally. Seed script
   `scripts/seed.ts` creating a demo tenant with 14 days of realistic entries (port the SQL seed
   from LEGACY `scratchpad/seed.sql` logic).
5. Shell: `src/shell/page-guard.ts`, `app-frame.tsx`, `text.ts` copied from dueflow and adapted.
   All seven items from `docs/PORTING-THE-SHELL.md` from day one: `sw.js` route, appearance script,
   `chrome="theme"`, `/auth/logout`, attention bell (`api/attention` returning unsorted count and
   low-float count), jump box, `UpdateReady`.
6. Pages, read-only first, all wired to real queries under `withTenant`:
   - `/` dashboard: total e-money, cash in hand, today's commission and entry count, wallet cards
     with balance and runway, recent entries. `StatCard`, `DashboardRow/Panel`.
   - `/entries`: `DataTable` with wallet/type/date filters, TrxID and phone search, detail drawer
     with accept / void.
   - `/unsorted`: pending-review entries and suspicious raw messages, accept / classify / ignore.
   - `/day-close`: expected vs actual per wallet, difference, history table.
   - `/baki`: parties with derived due, statement view, WhatsApp / SMS reminder links.
   - `/reports`: today / month / last month, commission by wallet, volume by type, P&L. CSV export.
   - `/customers`: `PartyPicker`-based party management.
   - `/settings`: wallets, commission rules, counters.
   - `/devices`: list of phones, revoke.
   - `/staff`: tenant members, invites and roles through `@corebari/staff` (`staffList`,
     `inviteStaff`, `pendingInvites`, `revokeInvite`, `changeStaffRole`, `removeStaff`). Confirmed
     to fit; ships at launch (D14).
   - `/audit`: `entry_events` timeline with filters (D20).
7. Mutations via `guardedAction` with `requireEntitlement` on every write. `EntitlementBanner`
   mounted in the frame.
8. Manifest via `appManifest(agentkhataApp, 'bn')`, icons `public/icons/icon-{192,512,maskable}.png`.
9. Tests: `messages/parity.test.ts`, ledger view fixtures (section 6), page-guard tests copied
   from dueflow. `pnpm check` green.

Acceptance: `pnpm --filter @corebari/agentkhata dev` serves a portal that logs in through CoreBari
SSO on localhost, shows the seeded tenant, installs as a PWA in Chrome, and passes `pnpm check`.

### P2. PLATFORM: phone-first self-signup, catalog, SSO client (est. 2 days)

1. `src/config/catalog/apps.ts`: `appEntry({ id: 'agentkhata', category: 'finance', appClass:
   business, status: 'live', demoUrl: 'https://agentkhata.corebari.net/demo' })`. Add
   `'agentkhata'` to the `AppId` unions in `src/config/catalog/schema.ts` and
   `src/config/catalog/index.ts`. Add en/bn tagline in `messages/*/Catalog.json`.
2. `src/config/apps-sso.ts`: append client `app-agentkhata` with redirect URIs, production first:
   `https://agentkhata.corebari.com/auth/callback`, `https://agentkhata.corebari.net/auth/callback`,
   `http://localhost:3127/auth/callback`. Secret env `APPS_SSO_SECRET_AGENTKHATA` in both repos.
3. Phone-first self-signup, new module `src/server/billing/auth/phone-signup.ts` and route
   `src/app/api/billing/auth/phone/signup/route.ts`:
   - Input: BD phone (`canonicalBdPhone`), locale. Issues OTP via existing `issueOtp`.
   - On verify: if no user with that phone, create user with `phone_login_enabled = true`,
     no password, `phone_verified_at = now()`, then `createSession`. If a user exists with the
     phone and `phone_login_enabled`, behave as login. If a user exists with the phone but a
     password, refuse with a message directing to password login (do not merge accounts).
   - Rate limits: reuse the limits in `otp.ts`. Audit via `writeAudit`.
   - The SSO authorize page must offer "Continue with phone" alongside password and Google when the
     requesting client is `app-agentkhata` (and later any client that opts in via a new
     `preferredLogin: 'phone'` field on the SSO client entry).
   - Tests beside the module, plus one test proving a password user cannot be logged in by phone.
4. Billing: bKash, Nagad and Rocket are already supported through the PipraPay provider
   (`src/server/billing/providers/payments/provider.piprapay.ts`). Nothing to build; verify the
   new catalog entry is purchasable end to end in staging.

Acceptance: a brand-new phone number can create an account and land in `apps/agentkhata` through
SSO without ever seeing a password field; an existing password user's login is unchanged; PLATFORM
test suite green.

### P3. APPS: mobile API and device auth (est. 4 days)

Routes under `apps/agentkhata/src/app/api/m/`:

1. `POST /api/m/devices/pair/start` (session cookie, from the web login page opened in the phone's
   Custom Tab with `?device=<base64 pubkey>&name=<model>`): after SSO completes, creates a
   `devices` row, mints a random 32-byte token, stores `sha256(token)`, and redirects to
   `agentkhata://paired#token=<token>&tenant=<id>`. Token shown once. Deep link scheme registered
   in the Android manifest.
2. Bearer middleware `src/server/mobile-auth.ts`: `Authorization: Bearer <token>` →
   `devices` lookup by hash, not revoked → `{ tenantId, userId, deviceId }`. Every `/api/m/*`
   route resolves tenant through this and then `withTenant`. Optional request signing with the
   device key can come later; token over TLS is the v1.
3. `POST /api/m/sync/push`: body `{ wallets: [], entries: [], day_closes: [], commission_rules: [],
   raw_messages: [] }`, each row with `base_version` (0 for new). Server accepts when
   `base_version == current version` (or row is new), increments `version`, writes
   `entry_events`, returns per-row `{ id, status: 'ok' | 'conflict', version, row? }` with the
   server row on conflict (D10). `baki_received` entries also insert a `core.payments` row (D11).
   Enforce entitlement (`assertWritable`), max 500 rows per table. `raw_messages` are dropped
   server-side unless `tenant_settings.upload_raw_messages` is true (D12).
4. `GET /api/m/sync/pull?table=entries&since=<server_updated_at>&limit=500`: rows for the tenant
   newer than cursor, ordered by `server_updated_at`. Returns `next` cursor.
5. `GET /api/m/sync/reconcile`: returns the device's counter's live wallets (`id, kind,
   account_number, label`) so the phone can map local wallets before first push (D19).
6. `GET /api/m/bootstrap`: tenant name, counters, entitlement state, commission rules, feature
   flags. Called on app start.
7. `POST /api/m/devices/revoke` (session, portal) and `GET /api/m/devices/me`.
8. Realtime: none in v1. The phone polls `pull` on app foreground, after each push, and every 5
   minutes while in foreground. The portal's `useReplica` refreshes on focus. Push notifications
   for portal-originated edits are a v2 item.
9. Tests: route tests with a seeded tenant covering push idempotency, version conflict returns
   409-style per-row result with the server row, tenant isolation (device of tenant A cannot read
   tenant B), revoked device gets 401, entitlement lockout makes push read-only, `core.payments`
   row created for `baki_received`, `entry_events` written for every mutation.

Acceptance: a shell script with `curl` can pair a fake device, push 3 entries, pull them back, and
is refused for another tenant.

### P4. MOBILE: swap transport, SSO pairing, CoreBari branding, launch features (est. 4 days)

1. Replace `lib/sync/sync_service.dart` transport with `MobileApi` (Dio or `http`): keep the
   push/pull/cursor logic, change the calls. Remove `supabase_flutter`, `supabase`,
   `sync/supabase_config.dart`. Config via `--dart-define=AGENTKHATA_API=https://agentkhata.corebari.com`.
2. Pairing flow: `login_screen.dart` becomes "Connect to CoreBari": generates a keypair, opens
   `${API}/auth/login?device=...&name=...` in a Custom Tab (`flutter_web_auth_2` or
   `url_launcher` + app link), receives `agentkhata://paired`, stores token in
   `flutter_secure_storage`. Offline-only mode remains the default path with no account.
3. Reconcile all wallets on first sync via `/api/m/sync/reconcile` (D19); generalise the
   existing `replaceWalletId` logic; one-time merge prompt for ambiguous wallets.
3b. Version-based conflict handling in `SyncService` (D10): send `base_version`, apply the
   status-wins auto-resolve, record conflict losers locally and re-push.
3c. Enum names on the wire (D16); adapter in `lib/sync/enum_index.dart` becomes name based.
4. Branding: `app/theme.dart` to CoreBari tokens (navy, brick, blueprint, ivory; worksheet light
   theme for content), fonts IBM Plex Sans + Noto Sans Bengali + IBM Plex Mono for numbers, radius
   0.5rem controls / 0.75rem cards. App name "AgentKhata by CoreBari" on the About row; launcher
   icon from PLATFORM `brand/` mark with the AgentKhata accent. Hex values live in one Dart tokens
   file only.
5. Remove the Flutter web target entirely (D23): delete `web/`, wasm and worker files, web-only
   branches in the router and settings.
6. Tests: unit suite unchanged (36), integration test rewritten against a local
   `apps/agentkhata` on :3127 with a seeded device token.

Acceptance: APK pairs with a local CoreBari + agentkhata stack, pushes captured entries, and the
portal shows them within one pull cycle; the same edit made on the portal appears on the phone.

### P5. Cutover and deploy (est. 1 day)

1. APPS `docker/compose.vps.yml`: service `corebari-agentkhata` from the `x-app-common` anchor,
   image `ghcr.io/corebarihq/agentkhata`, port 3127, `mem_limit: 384m`. `docker/Caddyfile.vps`:
   `agentkhata.corebari.com` and `agentkhata.corebari.net` blocks with `respond /demo* 404` on .com.
2. CI: add the app to the image build matrix per `docs/CI-CD.md`.
3. DNS for both hostnames. Deploy PLATFORM first (catalog + SSO client + phone signup), then APPS.
4. Run `pnpm db:migrate` on the VPS. Smoke: SSO login, phone signup, PWA install, pairing from a
   real phone on mobile data, one day of live capture.
5. Retire LEGACY: `npx supabase stop`, delete `backend/deploy`, keep `backend/supabase/migrations`
   in git history only. Remove Supabase mentions from MOBILE README.

Rollback: the app is additive. Removing the Caddy block and compose service, and setting the
catalog status to `hidden`, returns the platform to its previous state. Phone signup is behind the
per-client `preferredLogin` flag; turning it off hides the door without a deploy of APPS.

### P6. Post-launch, ordered (not part of READY)

Staff roles and per-staff activity, PDF statements via `@corebari/pdf`, distributor (DSO) view,
push notifications for portal edits, request signing with the device key, iOS read-only client,
server-side parser rules distribution, anonymised float-demand insights.

---

## 3b. Feature catalogue (scope contract)

Goal stated by the owner: the app and the portal must be feature rich enough to beat every
existing agent app, Hisabkari included. This section is the scope contract. "Launch" items ship in
P1 to P5. "Fast follow" ships in the four weeks after launch. "Later" is backlog. Hisabkari parity
items are marked HK; everything unmarked is beyond what Hisabkari offers.

Legend: A = Android app, P = portal, B = both.

### Capture and ledger
| Feature | Where | When |
|---|---|---|
| Auto capture from operator app notifications (bKash, Nagad, Rocket, Upay, Tap) | A | Launch |
| Auto capture from operator SMS (optional permission) | A | Launch |
| OTP/PIN never stored, dropped at native layer | A | Launch |
| Fake operator SMS detection and quarantine | A | Launch |
| Duplicate detection (SMS + notification of same event) | A | Launch |
| Unsorted inbox with one-tap classify | B | Launch |
| Manual entry for all 16 types, HK | B | Launch |
| Quick-add keypad with last-used wallet and type, big Bangla numerals | A | Launch |
| Voice entry in Bangla for cash expenses | A | Launch |
| Bulk import from CSV / old paper khata template | P | Launch |
| Recharge and minute/MB card inventory, HK | B | Launch |
| Bank deposit / withdrawal and hand-cash moves, HK | B | Launch |
| Owner drawings and capital, HK | B | Launch |
| Expense categories with monthly budget | B | Launch |
| Attach photo of a receipt or customer NID to an entry | B | Later |

### Float and cash control
| Feature | Where | When |
|---|---|---|
| Live balance per wallet from operator-stated balance, HK | B | Launch |
| Cash in hand derived, never typed, HK partial | B | Launch |
| Float runway prediction per wallet and low-float alert | B | Launch |
| Suggested B2B top-up amount based on usual demand curve | B | Launch |
| Distributor (DSO) request message with one tap (WhatsApp) | A | Launch |
| Hourly demand heat-map per wallet | P | Launch |
| Multi-counter view with float per counter, and a counter filter on the ledger | P | Launch |

### Day close
| Feature | Where | When |
|---|---|---|
| Proposed closing per wallet, actual entry, difference, adjustment posting | B | Launch |
| Difference explanation: highlights suspect entries around the gap | B | Launch |
| Day close history and streak | B | Launch |
| Lock past days; edits after close require owner role | B | Launch |
| Printable day sheet (PDF) | P | Launch |

### Commission and profit
| Feature | Where | When |
|---|---|---|
| Per-operator, per-type rate tables, editable, effective-dated, HK | B | Launch |
| Operator-stated commission wins over rule | B | Launch |
| Commission by wallet, by day, by month, HK | B | Launch |
| Expected vs actually credited commission reconciliation | P | Launch |
| P&L with expenses, fees, drawings, HK | B | Launch |
| Recharge margin tracking | B | Launch |

### Customers and baki
| Feature | Where | When |
|---|---|---|
| Customer book on `core.parties`, shared with other CoreBari apps | B | Launch |
| Baki given / received, derived due, statement, HK | B | Launch |
| Free reminders via WhatsApp and phone SMS composer, HK charges for SMS | B | Launch |
| Bulk reminders to all overdue customers | P | Launch |
| Platform SMS reminders with credits (`@corebari/sms`), optional, HK | B | Launch |
| Due ageing (0-7, 8-30, 30+ days) | P | Launch |
| Customer statement share link (read-only, expiring) | P | Launch |
| Customer credit limit and warning at give time | B | Launch |

### Reports
| Feature | Where | When |
|---|---|---|
| Today, week, month, last month, custom range, HK | B | Launch |
| Commission by wallet, volume by type, entries count, HK | B | Launch |
| P&L, HK | B | Launch |
| Cash flow: opening, in, out, closing per wallet per day | P | Launch |
| Top customers by volume, top counterparties | P | Launch |
| Suspicious activity report (quarantined messages, voided entries, day-close gaps) | P | Launch |
| CSV export | P | Launch |
| PDF and Excel export | P | Launch |
| Scheduled daily summary by WhatsApp or SMS at close time | B | Launch |
| Year view with monthly totals | P | Launch |

### Portal-specific
| Feature | Where | When |
|---|---|---|
| Installable PWA, offline read of the ledger | P | Launch |
| CoreBari AppShell: sidebar, topbar, tenant switcher, jump box, alerts bell | P | Launch |
| Keyboard-first entry form and table navigation | P | Launch |
| Devices page: paired phones, last seen, revoke | P | Launch |
| Staff members and roles (owner, manager, staff), per-staff entry log | P | Launch |
| Audit trail per entry (who, when, from which device) | P | Launch |
| Bangla / English toggle, Bangla digits everywhere | B | Launch |
| Dark mode via CoreBari appearance | P | Launch |

### App-specific
| Feature | Where | When |
|---|---|---|
| Works fully offline with no account; connect later | A | Launch |
| Home-screen widget with wallet balances | A | Launch |
| App lock with fingerprint or the phone's own PIN | A | Launch |
| Backup export / import JSON, HK | A | Launch |
| Referral: invite another agent, both get free month | B | Blocked on a platform billing credit |
| In-app help in Bangla (written answers; videos later) | A | Launch |

### Trust and safety
| Feature | Where | When |
|---|---|---|
| Row-level tenant isolation, device tokens revocable | B | Launch |
| Data never leaves device without account; clear privacy page | B | Launch |
| Play SMS permission declaration and notification-only fallback | A | Launch |

Anything an existing market app offers that is not on this list must be added here before it is
built, so the scope stays visible.

## 4. Environments and secrets

| Name | Where | Purpose |
|---|---|---|
| `APPS_SSO_SECRET_AGENTKHATA` | PLATFORM `.env`, APPS `.env` | SSO client secret, same value both sides |
| `APP_PUBLIC_URL` | APPS app env | `http://localhost:3127` locally, prod host in compose |
| `COREBARI_ISSUER_URL` | APPS app env | already used by all apps |
| `AGENTKHATA_SW_KILL` | APPS app env | service worker kill switch |
| `AGENTKHATA_API` | MOBILE `--dart-define` | API base for the phone |

Local dev stack: PLATFORM on :3001 with its Postgres on :5434, APPS Postgres on :5435 via
PgBouncer :6432, `apps/agentkhata` on :3127. Phone on the same Wi-Fi uses the PC's LAN IP; the
SSO client must then also list `http://<lan-ip>:3127/auth/callback` in a dev-only entry.

---

## 5. Testing strategy

| Layer | Tool | Must cover |
|---|---|---|
| Dart core | `flutter test` (existing 36) | parser, postings, commission, dedup, float, reports |
| TS ledger | vitest, fixtures shared with Dart | balances and P&L identical to Dart for the same entries |
| API | vitest route tests with seeded tenant | push idempotency, version conflicts, isolation, revoke, entitlement |
| Portal | vitest for guards and messages; manual QA checklist per page | login, install, every page renders seeded data |
| Platform | existing PLATFORM suite + new phone-signup tests | no regression on password / Google / 2FA |
| End to end | script: pair, push, pull, portal edit, phone receives | one green run before each deploy |
| Conventions | `pnpm check` | RLS registration, poisha, hex placement, message parity |

---

## 6. Keeping Dart and TypeScript ledgers identical

Canonical file: `APPS/apps/agentkhata/src/server/ledger.fixtures.json`. Copy:
`MOBILE/test/fixtures/ledger_cases.json` plus `MOBILE/test/fixtures/FIXTURES_SHA` holding the
canonical file's sha256. A MOBILE test recomputes the hash of the copy and fails on mismatch;
`MOBILE/scripts/sync-fixtures.sh` refreshes copy and hash from APPS. Each case: opening balances,
a list of entries, expected balance per wallet, expected commission total, expected net profit.
Any change to posting rules starts with the APPS fixture (D22).

---

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Play Store SMS permission review | capture path reduced to notifications | already designed: notification listener primary, SMS optional; submit declaration form in P5 |
| Operator SMS format changes | entries land in Unsorted | parser rules become server-distributed in P6; Unsorted UX exists |
| Conflicting edits phone vs portal | a correction lost | server versions with per-row conflict result and status-wins auto-resolve (D10); losers kept in `entry_events` |
| Device token theft | data exposure for one tenant | token hashed at rest, revocable from portal, TLS only, rotate on re-pair; request signing in P6 |
| Phone-signup misuse (SMS pumping) | cost | reuse `otp.ts` limits plus per-IP and per-prefix caps; BD numbers only |
| Two ledgers drift | wrong numbers on portal | fixture lock-step with recorded hash on the MOBILE side (D22) |
| First connect of a phone with months of offline data into a tenant that already has data | duplicate wallets, double counting | `/api/m/sync/reconcile` mapping by kind and account number, merge prompt for ambiguity (D19); push batched 500 rows, resumable via dirty flag |
| `defineApp` slug union and `WIRED_APPS` forgotten | RLS not applied, CI fails | `pnpm check` rule 1 catches it; listed explicitly in P1 |

---

## 8. READY checklist (all met on 2026-09-20)

- Every fork in the decision tree resolved and recorded as D1 to D24.
- Owner explicitly confirmed D8, D9, D10 and delegated the remaining forks to the recommended
  branch.
- Phase order and estimates accepted: P1 7d, P2 2d, P3 4d, P4 4d, P5 1d. P1 and P3 can run in
  parallel with P2.

## 9. Resolved questions (for traceability)

| Question | Answer |
|---|---|
| Tenant granularity | One tenant per business, counters inside (D8) |
| Baki repayments to `core.payments` | Yes, at launch (D11) |
| Raw message upload | Opt-in, default off (D12) |
| Pricing class | `business` (D13) |
| Staff login | Owner invites via `@corebari/staff`; no staff self-signup (D14) |
| `.net` demo host | Yes at launch (D15) |

## 10. Execution notes for the implementing session

- Start with P1 steps 1 to 4 and P3 step 2 (device auth) in one branch of APPS; P2 in a branch of
  PLATFORM; they do not depend on each other until P5.
- Run `pnpm check` in APPS and the PLATFORM test suite before every commit. Both have convention
  scripts that will fail on hex colours outside tokens files, missing RLS registration, `numeric`
  money columns, `process.env` outside `env.ts`, and en/bn message parity.
- Read `APPS/CONTEXT.md`, `APPS/docs/PORTING-THE-SHELL.md` and `APPS/apps/dueflow` before writing
  code. Copy patterns; do not invent parallel ones.
- Dart source of truth for parsing and posting rules is `MOBILE/app/lib/core`. Port posting rules
  to SQL views and TS exactly, then prove it with the fixtures.
- No emojis in code, commits or docs. Bangla is the default locale everywhere.

---

## 11. What actually happened

Built on 2026-09-20 against the plan above. Everything in P1 to P4 is done and
verified; P5 is written but not run, because deploying needs the VPS.

### Verification at the end of the run

Re-run after the second wave below, on the same day.

| Suite | Result |
|---|---|
| `corebari-apps` typecheck | 44 of 44 packages |
| `corebari-apps` tests | 44 of 44 tasks; AgentKhata's own are 37, of which 13 are database-backed |
| `corebari-apps` conventions, roles, message keys | all pass; 394 AgentKhata keys, both languages |
| `corebari` tests | 1,224 of 1,224 |
| Flutter analyze and test | clean, 56 tests |
| Portal production build | succeeds |
| Android debug APK | builds, with the widget receiver and its resources |
| Phone-first signup, end to end | account created, password account correctly refused |
| SSO into the portal with that account | succeeds |

### Deviations from the plan, and why

**The commission rate is an integer, not a float.** The plan had
`value numeric` with a CI exemption. The repo's conventions check forbids
floats near money outright, and it was right to: the rate is multiplied by
money, so a float in it is a float in the answer. Rates are now stored in
parts per million (4.10 per thousand is 4,100) and `mode` survives only to
render the number back in the unit the agent was quoted in.

**`agentkhata.devices` is platform-readable.** A bearer token IS the tenant
resolution — there is no cookie to read one from — so the lookup has to cross
tenants exactly once. Added to `PLATFORM_SWEEPABLE_TABLES` beside
`core.payment_credentials`, which exists for the identical reason, with the
justification written where the next reader will find it.

**Staff shipped at launch rather than being deferred.** `@corebari/staff`
already had invites, roles and the last-owner guard, so it was an afternoon
rather than a phase.

**No MFS payment work was needed.** Billing already takes bKash, Nagad and
Rocket through PipraPay. The risk in section 7 was wrong.

### Bugs found and fixed during the run

1. **The pull cursor never advanced.** `clock_timestamp()` has microsecond
   precision and a JavaScript `Date` has millisecond precision, so parsing the
   cursor truncated it and the comparison matched the row it came from. Every
   pull re-delivered the last row of the previous page, forever, while
   appearing to work. The cursor is now a string end to end and Postgres parses
   it. Found by the integration test; it could not have been found any other
   way.
2. **A duplicate operator transaction aborted the whole push.** The unique
   index on `(wallet_id, trx_id)` raised, and one duplicate would have rejected
   an entire day of captured entries. Now checked before the insert and caught
   on the race.
3. **An overdrawn wallet reported a negative runway.** "Runs out in about -41.2
   hours" is meaningless and, worse, sorted as the least urgent row on the
   board. Fixed in both implementations, with a regression test in each.
4. **Large amounts clipped in the phone-width tiles.** `৳৭,১২,৬০২.২৯` rendered
   as `৳৭,১২,৬০২.২`, which is simply a wrong number. The headline tiles now
   show whole taka; the rows beneath keep the paisa.

### The second wave, built the same day

Everything below was marked "Fast follow" in section 3b and shipped anyway,
because a launch that concedes a feature to Hisabkari concedes the comparison.

**Portal.** Recharge and minute-card inventory with oversell refused inside the
transaction; expense categories with monthly budgets and an honest
uncategorised line; expiring read-only statement share links; commission
reconciliation of the rate table against what the operator actually credited;
an hourly demand heat-map; a year view; CSV and old-paper-khata import that
validates every row before writing any; printable day sheets and customer
statements; credit limits checked before the credit is given, not after; a
scheduled daily summary by SMS; day reopening that records itself; Excel export
beside the CSV; and a counters screen that puts each point of sale side by side
with a matching counter filter on the ledger.

**Android.** An app lock that uses the phone's own fingerprint or PIN rather
than inventing another one, off by default and re-locking when the phone is put
down; Bangla-first voice amount entry that fills the field and never saves; a
home-screen widget showing float, cash, today and any low-float warning, with
one-tap add and inbox; a one-tap float request to the distributor over WhatsApp
using the advisor's own suggested amount; and an offline help screen.

Two things stayed unbuilt on purpose, with reasons, under **What is left**.

### What is left

- **P5 deploy.** `docker/compose.vps.yml`, `docker/Caddyfile.vps` and the CI
  publish matrix all carry AgentKhata. Deploying needs DNS for
  `agentkhata.corebari.com`, `APPS_SSO_SECRET_AGENTKHATA` in
  `/srv/ops/env/corebari-apps.env`, and a run of `pnpm db:migrate` on the box.
- **Real operator messages.** The parser fixtures are realistic shapes, not
  captured texts. This is the single highest-value thing left before a pilot.
- **Commission rates.** Verify each against the operator's current circular.
- **Referral: invite an agent, both get a free month.** Deliberately not
  built. It needs a billing credit the platform does not have — there is no
  coupon, credit or grant primitive in `@corebari/billing` — so it is a
  platform change plus a commercial decision about who absorbs the month and
  what stops one person opening two businesses. Cheap to add once that credit
  exists; unsafe to fake with a discount nobody can audit.
- **Help videos.** The help screen ships with written Bangla answers to the
  eight questions support actually receives. Video needs recording, which needs
  a real agent's counter.
- **Attach a photo of a receipt or NID to an entry.** Still backlog; it needs
  object storage and a retention answer for a photograph of somebody's ID.
