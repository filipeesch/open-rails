class_name EconomyService
extends RefCounted

## The only place company cash changes.
##
## Systems never write `cash -= cost`; they call spend()/earn()/refund() and
## receive a transaction id.  The ledger is the ground truth: summing it from
## the opening balance always reproduces cash exactly, which is asserted by
## the domain test suite so the rule cannot rot.

signal money_changed(cash: float)
signal transaction_recorded(transaction: Transaction)
signal insufficient_funds(required: float, available: float, purpose: String)

const CATEGORY_REVENUE := "revenue"
const CATEGORY_TRACK := "track_construction"
const CATEGORY_STATION := "station_construction"
const CATEGORY_TRAIN := "train_purchase"
const CATEGORY_WAGON := "wagon_purchase"
const CATEGORY_OPERATING := "train_operating"
const CATEGORY_MAINTENANCE := "track_maintenance"
const CATEGORY_REFUND := "refund"

const CATEGORY_LABELS := {
	CATEGORY_REVENUE: "Revenue",
	CATEGORY_TRACK: "Track construction",
	CATEGORY_STATION: "Station construction",
	CATEGORY_TRAIN: "Train purchase",
	CATEGORY_WAGON: "Wagon purchase",
	CATEGORY_OPERATING: "Train operating cost",
	CATEGORY_MAINTENANCE: "Track maintenance",
	CATEGORY_REFUND: "Refund",
}

var company_name: String = "Founder's Railway"
var cash: float = 0.0
var opening_balance: float = 0.0

var _ledger: Array[Transaction] = []
var _transactions_by_id := {}
var _next_transaction_id: int = 1
var _date: GameDate


class Transaction extends RefCounted:
	var id: int = 0
	var amount: float = 0.0
	var category: String = ""
	var description: String = ""
	var day: int = 0
	var month: int = 1
	var year: int = 1850
	var reversed_by: int = 0

	var month_key: int:
		get:
			return year * 100 + month

	func signed_amount() -> float:
		return amount

	func is_expense() -> bool:
		return amount < 0.0


func configure(starting_cash: float, date: GameDate, name: String = "Founder's Railway") -> void:
	company_name = name
	opening_balance = Money.round(starting_cash)
	cash = opening_balance
	_date = date


func date() -> GameDate:
	return _date


func can_afford(amount: float) -> bool:
	return cash + 0.000001 >= Money.round(amount)


func earn(amount: float, category: String, description: String) -> Transaction:
	return _record(Money.round(amount), category, description, false)


func spend(amount: float, category: String, description: String) -> Transaction:
	var cost := Money.round(amount)
	if cost <= 0.0:
		return _record(0.0, category, description, false)
	if not can_afford(cost):
		insufficient_funds.emit(cost, cash, description)
		return null
	return _record(-cost, category, description, false)


func spend_allowing_deficit(amount: float, category: String, description: String) -> Transaction:
	return _record(-Money.round(amount), category, description, false)


## Reverses a recorded transaction, restoring the balance.  Used by undo and
## by demolishing an asset.  Returns the reversal, or null when there is
## nothing to reverse.
func refund(transaction_id: int) -> Transaction:
	var original: Transaction = _transactions_by_id.get(transaction_id)
	if original == null or original.reversed_by != 0:
		return null
	var reversal := _record(-original.amount, CATEGORY_REFUND, "Undo: " + original.description, false)
	original.reversed_by = reversal.id
	reversal.reversed_by = original.id
	return reversal


func unreversed_ledger() -> Array[Transaction]:
	var out: Array[Transaction] = []
	for transaction in _ledger:
		if transaction.reversed_by == 0:
			out.append(transaction)
	return out


func ledger() -> Array[Transaction]:
	return _ledger


func recent(count: int) -> Array[Transaction]:
	var out: Array[Transaction] = []
	var index := _ledger.size() - 1
	while index >= 0 and out.size() < count:
		if _ledger[index].reversed_by == 0:
			out.append(_ledger[index])
		index -= 1
	return out


func month_totals(month_key: int) -> Dictionary:
	var revenue := 0.0
	var expenses := 0.0
	var by_category := {}
	for transaction in _ledger:
		if transaction.reversed_by != 0 or transaction.month_key != month_key:
			continue
		by_category[transaction.category] = float(by_category.get(transaction.category, 0.0)) + transaction.amount
		if transaction.amount >= 0.0:
			revenue += transaction.amount
		else:
			expenses += -transaction.amount
	return {
		"revenue": Money.round(revenue),
		"expenses": Money.round(expenses),
		"profit": Money.round(revenue - expenses),
		"by_category": by_category,
	}


func current_month_totals() -> Dictionary:
	return month_totals(_date.month_key())


func previous_month_totals() -> Dictionary:
	var previous := _date.previous_month_key()
	var totals := month_totals(previous)
	totals["has_history"] = has_month(previous)
	return totals


func has_month(month_key: int) -> bool:
	for transaction in _ledger:
		if transaction.month_key == month_key:
			return true
	return false


## The sum of every live transaction, refunds included.  The number the ledger
## is actually being asked to explain.
func net_movement() -> float:
	var total := 0.0
	for transaction in unreversed_ledger():
		total += transaction.amount
	return Money.round(total)


## What the balance should be if the ledger is complete: opening + net movement.
func projected_balance() -> float:
	return Money.round(opening_balance + net_movement())


## The invariant the test suite guards: nothing moves cash except a ledger row.
func is_consistent() -> bool:
	return absf(projected_balance() - cash) < 0.01


func transaction_for_id(id: int) -> Transaction:
	return _transactions_by_id.get(id)


func to_dict() -> Dictionary:
	var entries: Array = []
	for transaction in _ledger:
		entries.append({
			"id": transaction.id,
			"amount": transaction.amount,
			"category": transaction.category,
			"description": transaction.description,
			"day": transaction.day,
			"month": transaction.month,
			"year": transaction.year,
			"reversed_by": transaction.reversed_by,
		})
	return {
		"company_name": company_name,
		"cash": cash,
		"opening_balance": opening_balance,
		"next_transaction_id": _next_transaction_id,
		"transactions": entries,
	}


func from_dict(data: Dictionary) -> void:
	_ledger.clear()
	_transactions_by_id.clear()
	company_name = String(data.get("company_name", company_name))
	opening_balance = float(data.get("opening_balance", 0.0))
	cash = float(data.get("cash", 0.0))
	_next_transaction_id = int(data.get("next_transaction_id", 1))
	for entry in data.get("transactions", []):
		var transaction := Transaction.new()
		transaction.id = int(entry["id"])
		transaction.amount = float(entry["amount"])
		transaction.category = String(entry["category"])
		transaction.description = String(entry["description"])
		transaction.day = int(entry.get("day", 1))
		transaction.month = int(entry.get("month", 1))
		transaction.year = int(entry.get("year", 1850))
		transaction.reversed_by = int(entry.get("reversed_by", 0))
		_ledger.append(transaction)
		_transactions_by_id[transaction.id] = transaction


func category_label(category: String) -> String:
	return String(CATEGORY_LABELS.get(category, category))


func _record(amount: float, category: String, description: String, _silent: bool) -> Transaction:
	var transaction := Transaction.new()
	transaction.id = _next_transaction_id
	_next_transaction_id += 1
	transaction.amount = Money.round(amount)
	transaction.category = category
	transaction.description = description
	if _date != null:
		transaction.day = _date.day
		transaction.month = _date.month
		transaction.year = _date.year
	_ledger.append(transaction)
	_transactions_by_id[transaction.id] = transaction
	cash = Money.round(cash + transaction.amount)
	money_changed.emit(cash)
	transaction_recorded.emit(transaction)
	return transaction
