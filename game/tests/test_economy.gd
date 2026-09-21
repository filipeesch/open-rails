class_name TestEconomy
extends TestBase

## One boundary for money, and a ledger that always explains the balance.

var economy: EconomyService
var date: GameDate


func _prepare() -> void:
	date = GameDate.new(1850, 1, 1)
	economy = EconomyService.new()
	economy.configure(100000.0, date, "Founder's Railway")


func test_opening_balance_is_the_starting_cash() -> void:
	_prepare()
	check_near(economy.cash, 100000.0, "cash starts at the configured amount")
	check_near(economy.opening_balance, 100000.0, "and the opening balance remembers it")


func test_every_mutation_appends_a_ledger_row() -> void:
	_prepare()
	economy.spend(1500.0, EconomyService.CATEGORY_TRACK, "Track: 1 tile")
	economy.earn(900.0, EconomyService.CATEGORY_REVENUE, "Coal delivery")
	economy.spend(20000.0, EconomyService.CATEGORY_STATION, "Station")
	check_eq(economy.ledger().size(), 3, "three transactions")
	check_near(economy.cash, 100000.0 - 1500.0 + 900.0 - 20000.0, "the balance reflects all three")


func test_balance_equals_opening_plus_ledger() -> void:
	_prepare()
	for month in 6:
		economy.earn(4200.0 + float(month) * 130.0, EconomyService.CATEGORY_REVENUE, "Deliveries")
		economy.spend(1800.0, EconomyService.CATEGORY_MAINTENANCE, "Track maintenance")
		economy.spend_allowing_deficit(900.0, EconomyService.CATEGORY_OPERATING, "Locomotive running")
		date.advance_days()
	check_true(economy.is_consistent(), "opening balance + Σ ledger equals cash")
	check_near(economy.net_movement(), economy.cash - economy.opening_balance,
		"the ledger's net movement equals the change in cash", 0.02)
	check_near(economy.projected_balance(), economy.cash, "the projection is the balance", 0.02)


func test_construction_is_blocked_without_a_negative_balance() -> void:
	_prepare()
	var blocked := economy.spend(250000.0, EconomyService.CATEGORY_STATION, "Station")
	check_true(blocked == null, "an unaffordable purchase is refused")
	check_near(economy.cash, 100000.0, "and the balance is untouched")
	check_eq(economy.ledger().size(), 0, "no ledger row was written")


func test_recurring_costs_may_dip_below_zero() -> void:
	_prepare()
	economy.spend_allowing_deficit(120000.0, EconomyService.CATEGORY_OPERATING, "A very expensive month")
	check_lt(economy.cash, 0.0, "recurring costs can push the company into deficit")
	check_true(economy.is_consistent(), "and the ledger still explains it")
	var blocked := economy.spend(1.0, EconomyService.CATEGORY_TRACK, "Track")
	check_true(blocked == null, "but construction is still blocked while overdrawn")


func test_undo_reverses_the_original_transaction() -> void:
	_prepare()
	var purchase := economy.spend(26000.0, EconomyService.CATEGORY_TRAIN, "Train: 4-4-0")
	check_true(purchase != null, "the purchase went through")
	var reversal := economy.refund(purchase.id)
	check_true(reversal != null, "it was reversed")
	check_near(economy.cash, 100000.0, "the balance came back")
	check_eq(economy.unreversed_ledger().size(), 0, "both rows are excluded from the active ledger")
	check_eq(economy.ledger().size(), 2, "both rows are still recorded — history is not deleted")


func test_a_transaction_can_only_be_reversed_once() -> void:
	_prepare()
	var purchase := economy.spend(4800.0, EconomyService.CATEGORY_WAGON, "Coal Hopper")
	economy.refund(purchase.id)
	var second := economy.refund(purchase.id)
	check_true(second == null, "a second reversal of the same transaction is refused")
	check_near(economy.cash, 100000.0, "so the balance cannot be inflated by double-undo")


func test_month_totals_separate_revenue_from_expense() -> void:
	_prepare()
	economy.earn(12000.0, EconomyService.CATEGORY_REVENUE, "Deliveries")
	economy.spend(3000.0, EconomyService.CATEGORY_TRACK, "Track")
	for _day in 31:
		date.advance_days()
	economy.earn(9000.0, EconomyService.CATEGORY_REVENUE, "Later deliveries")
	economy.spend(2000.0, EconomyService.CATEGORY_MAINTENANCE, "Maintenance")
	var january := economy.month_totals(1850 * 100 + 1)
	var february := economy.month_totals(1850 * 100 + 2)
	check_near(float(january["revenue"]), 12000.0, "January revenue is only January's")
	check_near(float(january["expenses"]), 3000.0, "and its expenses are its own")
	check_near(float(february["revenue"]), 9000.0, "February is separate")
	check_near(float(january["profit"]) + float(february["profit"]), 16000.0, "profits add up")


func test_amounts_are_rounded_to_cents() -> void:
	_prepare()
	economy.earn(123.4567, EconomyService.CATEGORY_REVENUE, "Rounding check")
	check_near(economy.cash, 100123.46, "money is stored to two decimals", 0.0001)


func test_can_afford_matches_the_balance() -> void:
	_prepare()
	check_true(economy.can_afford(100000.0), "spending the whole balance is allowed")
	check_false(economy.can_afford(100000.01), "one cent more is not")
