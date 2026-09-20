# AgentKhata (এজেন্ট খাতা) — Product Brief

Working title. Rename freely; the code uses the package id `agentkhata`.

## One line
The zero-typing ledger for mobile banking agents in Bangladesh: it reads every bKash / Nagad / Rocket / Upay transaction automatically, keeps float and cash balanced, closes the day in one tap, and tells the agent exactly what they earned.

## Who it is for
- Primary: single-counter MFS agents (bKash Agent, Nagad Uddokta, Rocket, Upay) who also do recharge and some bank cash. ~1.8 million agents in Bangladesh.
- Secondary: multi-counter owners with staff, and distributors (DSO) who want to see float needs across their agents.

## Why agents will switch from paper / Hisabkari
| Pain today | Hisabkari | AgentKhata |
|---|---|---|
| Typing every transaction | Manual entry | Auto-captured from SMS + app notifications |
| Not knowing the true float | Balance = what you typed | Balance parsed from the operator's own SMS, cash derived |
| Running out of e-money mid-day | Nothing | Float runway prediction + low-float alert per wallet |
| Day-end mismatch hunting | Enter closing, see difference | App proposes closing, highlights the suspect transaction |
| Commission guesswork | Approximate | Exact per-operator rate tables, per wallet per day |
| Fake "payment received" SMS | Nothing | Sender-ID and message-shape verification, red flag |
| Poor network | Cloud-dependent | Offline-first, sync when online |
| Reminders cost money | Paid SMS ৳0.50 | Free WhatsApp / share-link reminders, SMS optional |
| Staff at the counter | No roles | Owner / staff roles, per-staff activity log |
| Android only, Bangla only | Yes | Android first, Bangla + English, iOS/web dashboard later |

## Positioning
"হিসাব লিখতে হবে না, হিসাব নিজেই হবে।" (You do not write the accounts; the accounts write themselves.)

## Business model
- Free: auto capture, 1 counter, 30 days of history, day close, baki ledger.
- Pro ৳29/month or ৳299/year (under Hisabkari's ৳40/month): unlimited history, cloud backup and multi-device, reports export (PDF/Excel), staff roles, float alerts, WhatsApp statements.
- Later: distributor dashboard (B2B subscription), anonymised float-demand insights.

## Success metrics (first 6 months)
- 70% of transactions auto-captured without edits (parser quality).
- Day close completed on 5+ of 7 days by active agents.
- D30 retention above 40%.
- 1,000 paying agents.

## Key risks
1. Google Play SMS permission policy. Mitigation: Notification Listener as primary source, SMS as opt-in fallback with a policy declaration; core use case is clearly financial bookkeeping for the user's own messages.
2. Operators change SMS formats. Mitigation: rule tables are data, hot-updatable from the backend; unparsed messages are kept and surfaced for one-tap manual classification, which also trains new rules.
3. Trust. Mitigation: everything on device by default, encrypted backup, no PIN or OTP ever read (filtered out at the native layer before reaching Dart).
