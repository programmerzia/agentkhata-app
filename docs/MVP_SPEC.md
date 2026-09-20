# AgentKhata — MVP Specification

## Scope (v1.0)
1. Onboarding: language, wallets the agent uses, opening balances, permissions (notification access, optional SMS).
2. Auto capture: parse operator SMS and notifications into transactions. Unparsed messages go to an "Unsorted" inbox.
3. Ledger: transactions per wallet, manual entry for cash expenses, owner drawings, hand-cash moves, recharge sales.
4. Float dashboard: live balance per wallet, total e-money, cash in hand, today's in/out, runway alert.
5. Day close: proposed closing per wallet vs actual, difference explanation, snapshot locked.
6. Commission: per-operator rate tables, daily/monthly earned per wallet.
7. Baki (customer credit) ledger: customers, give/receive, due list, reminder via WhatsApp share.
8. Reports: daily, monthly, profit and loss (commission + recharge margin − expenses − drawings).
9. Backup: local export/import (JSON) in v1; cloud sync in v1.1.

Out of scope for v1: iOS, distributor dashboard, staff roles (v1.2), in-app payments.

## Domain model
- Wallet {id, kind: bkash|nagad|rocket|upay|tap|bank|cash|other, label, accountNumber?, isActive, openingBalance, openingAt}
- Transaction {id, walletId, type, amount, fee, commission, counterparty?, trxId?, balanceAfter?, occurredAt, source: auto_sms|auto_notification|manual, rawMessageId?, note?, customerId?, linkedTransactionId?, status: posted|pending_review|voided}
  - type: cashIn, cashOut, sendMoney, receiveMoney, b2bIn, b2bOut, payment, recharge, billPay, expense, drawing, capital, cashMove, bakiGiven, bakiReceived, adjustment
- RawMessage {id, source, sender, packageName?, body, receivedAt, parsedTransactionId?, parseStatus: parsed|unparsed|ignored|suspicious}
- CommissionRule {id, walletKind, txType, mode: perThousand|percent|flat|slab, value, slabs?, effectiveFrom}
- Customer {id, name, phone?, note?}
- DayClose {id, date, walletId, expectedBalance, actualBalance, difference, note, closedAt}
- Expense category {id, name}

Cash in hand is derived: opening cash + cashIn received in cash + cashOut paid... explicitly:
- cashIn (customer gives cash, agent sends e-money): cash +amount, wallet −amount
- cashOut (customer takes cash): cash −amount, wallet +amount
- b2bIn / b2bOut: wallet ±, usually paid in cash to the distributor → optional cash leg
- recharge sale: cash +amount, recharge float −amount
- expense/drawing: cash −
- capital: cash or wallet +
Every transaction is posted as double-entry between two "accounts" (wallet, cash, income:commission, expense, equity) so the books always balance.

## Parsing strategy
- Native layer (Kotlin): NotificationListenerService for packages com.bkash.businessapp, com.konasl.nagad.agent, rocket/upay apps; SMS BroadcastReceiver for sender IDs bKash, NAGAD, 16216, Rocket, upay. Messages containing OTP/PIN keywords are dropped before crossing to Dart.
- Dart layer: `MessageParser` runs a list of `ParseRule`s (regex + field map) per operator; a generic fallback extracts amount / balance / TrxID / counterparty / type keywords. Confidence below threshold → pending_review.
- Rules are data (JSON) bundled with the app and updatable remotely later.
- Deduplication by (trxId) and by (wallet, amount, ±2 min, balanceAfter).
- Suspicious detection: message shape matches an operator but sender is a personal number, or balance jumps inconsistently → flagged, never auto-posted.

## Architecture
- Flutter (Android first), Riverpod for state, Drift (SQLite) for storage, go_router for navigation, intl for Bangla/English.
- Layers: `core/` pure Dart (domain, parser, commission, ledger math, 100% unit-tested), `data/` Drift + repositories, `features/` UI per screen, `platform/` method/event channels.
- Backend (v1.1): Supabase — auth by phone OTP, encrypted backup blobs, rule table distribution, subscription state. 

## Screens
1. Home / Float dashboard
2. Transactions (filter by wallet/type/date, search TrxID), Unsorted inbox
3. Add transaction (manual)
4. Day close
5. Customers and baki
6. Reports
7. Settings: wallets, commission rates, permissions, backup, language, subscription

## Play Store policy plan
- Primary permission: BIND_NOTIFICATION_LISTENER_SERVICE with in-app explanation screen.
- SMS: RECEIVE_SMS declared as optional with a Permissions Declaration Form citing "financial transaction bookkeeping of the user's own accounts"; feature-flag to ship without it if rejected.
- Privacy policy page, on-device processing statement, no message content leaves the device unless backup is enabled.
