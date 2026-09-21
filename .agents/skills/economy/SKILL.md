# economy

## Purpose
Owns company money: `EconomyService` as the single mutation point, the
transaction ledger, expense/revenue categories, monthly accounting,
recurring charges, and the sandbox no-bankruptcy behaviour.

## When to use
Any feature that costs or earns money; finance panel data; refund/undo of
transactions; monthly profit figures.

## Non-goals
What things cost (each system passes amounts; data pins prices), delivery
quality math (`cargo-system` produces the revenue number), loans/bonds/
stock market (out of scope §115).

## Dependencies
- `GameSession` owns one `EconomyService`; `SimulationClock.month_changed`
  triggers accounting + recurring charges.
- Data: prices and rates in `game/data/economy/` (construction cost/tile,
  station cost, stock prices, running cost/train/month, maintenance/tile,
  starting cash within the spec's $500k–$1M band).
- Shared `Money` helper: the only place rounding happens (half-up to whole
  currency), used by revenue and ledger alike.

## Invariants
1. **Every** cash change goes through `EconomyService`
  (`spend/revenue/refund`); no system writes cash. A domain test guard
  proves opening balance + Σ ledger == cash exactly.
2. Every mutation creates a ledger transaction: game date, signed amount,
  category, description. Categories are exactly: track_construction,
  station_construction, train_purchase, wagon_purchase,
  train_operating_cost, track_maintenance — plus revenue entries naming
  cargo/quantity/route.
3. Monthly accounting on each `month_changed`: compute current-month
  revenue/expenses/profit from that month's transactions; reset
  accumulators; keep the previous month's figures readable. Profit ==
  revenue − expenses always.
4. Recurring charges (per train, per rail tile) fire automatically at the
  month boundary; an idle railway still costs money.
5. No game over: construction/purchases the cash can't cover are blocked
  with an insufficient-funds reason and change nothing; recurring costs may
  push cash temporarily negative while trains keep running; the finance UI
  makes the deficit obvious.
6. Company name is set at sandbox start (generated default when blank) and
  survives save/load.

## Public interfaces
`EconomyService`:
- `spend(amount, category, description) -> {ok, transaction_id} |
  InsufficientFunds`
- `revenue(amount, category, description) -> transaction_id`
- `refund(transaction_id)`, `cash()`, `month_totals() -> {revenue,
  expenses, profit}`, `previous_month_totals()`, `ledger(limit) -> recent`
- signals `money_changed`.

## Implementation rules
- Construction flows commit **one** transaction per player action (a
  12-tile route = one track_construction entry), refundable as a unit.
- Keep amounts as integers (whole currency); floats only inside calculators,
  rounded once through `Money` before the ledger.
- The finance list is a ledger query with a limit — never a parallel
  history buffer.
- Undo integrates via `refund(transaction_id)` (see `rail-builder`).

## Validation
Tests: six expense categories distinguishable in one month; ledger sum
reconstructs cash; month rollover resets and preserves previous figures;
one train + 40 tiles, no deliveries ⇒ expenses recorded, cash decreased;
negative balance keeps trains moving; refused purchase leaves cash
untouched and notifies.

## Common mistakes
- `cash -= cost` "just here for now" — the guard test will (rightly) fail
  the suite.
- Rounding in two places (revenue rounds, ledger rounds again → exactness
  tests fail).
- Refunds creating negative expenses instead of reversal entries.
- Polling the clock for month accounting instead of subscribing.

## Related skills
`rail-builder`, `station-system`, `train-system`, `cargo-system`,
`simulation-clock`, `save-load`, `testing`, `ui-layout` reference.
