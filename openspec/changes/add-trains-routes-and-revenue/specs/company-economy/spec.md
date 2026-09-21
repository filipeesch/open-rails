# Spec Delta

## Purpose

Defines the company's financial state, the single service through which every money change flows, monthly accounting and the sandbox behaviour when cash runs out.

## ADDED Requirements

### Requirement: Single money-mutation boundary
All changes to company cash SHALL go through `EconomyService`, and no other system SHALL mutate cash directly. Every mutation SHALL create a ledger transaction recording game date, amount, category and description.

#### Scenario: Direct mutation is impossible by convention and test
- **WHEN** the domain test suite runs its economy guard
- **THEN** cash has only changed through `EconomyService` calls
- **AND** each recorded transaction corresponds to one service call

#### Scenario: Ledger reconstructs cash
- **WHEN** all recorded transactions are summed from the opening balance
- **THEN** the result equals the current cash value exactly

### Requirement: Construction and purchase expense categories
The system SHALL record expenses for track construction, station construction, train purchase, wagon purchase, train operating cost and track maintenance as distinct categories.

#### Scenario: Each expense category is distinguishable
- **WHEN** each expense type occurs once in a test scenario
- **THEN** six distinct ledger categories are present in the month's totals

### Requirement: Monthly accounting
At each month boundary the system SHALL compute monthly revenue, monthly expenses and monthly profit from that month's transactions, expose them as the current month's figures, and retain the previous month's figures for display.

#### Scenario: Profit equals revenue minus expenses
- **WHEN** a month closes with recorded revenue and expenses
- **THEN** monthly profit equals monthly revenue minus monthly expenses for that month

#### Scenario: Accounting resets monthly
- **WHEN** a new month begins
- **THEN** current-month accumulators start from zero and the previous month's totals remain readable

### Requirement: Recurring costs are charged automatically
Train operating cost SHALL be charged per train and track maintenance per rail tile at each month boundary, without player action.

#### Scenario: Idle railway still costs money
- **WHEN** a month passes with one train and 40 rail tiles and no deliveries
- **THEN** operating and maintenance expenses are recorded and cash decreases

### Requirement: No bankruptcy game over
There SHALL be no game-over condition. When available cash cannot cover a construction or purchase, that action SHALL be blocked and reported; recurring costs may drive the balance temporarily negative while the existing railway keeps operating, and the deficit SHALL be made obvious in the finance presentation.

#### Scenario: Negative balance still runs trains
- **WHEN** cash falls below zero through operating costs
- **THEN** trains continue moving and earning

#### Scenario: Blocked purchase explains itself
- **WHEN** the player attempts a purchase exceeding available cash
- **THEN** the action is refused with an insufficient-funds reason and cash is unchanged

### Requirement: Company identity
The company SHALL have a player-supplied name set when a sandbox starts, defaulting to a generated name when none is entered, and the name SHALL appear in the finance and top-bar presentation.

#### Scenario: Named company survives a save round trip
- **WHEN** a sandbox is started with a company name and later loaded
- **THEN** the name is unchanged
