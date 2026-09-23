class_name CompanyPanel
extends PanelContainer

## The company's books: the cash, the running month's revenue, expenses and
## profit, and the last lines of the ledger behind the figures.
##
## Every number on this panel is `EconomyService`'s own answer.  The monthly
## figures come from `current_month_totals()` and the entries are the exact
## `recent()` rows of the ledger, description and amount included: the panel
## adds nothing, subtracts nothing and renames nothing.  That is the point —
## a finance sheet that recomputed money somewhere else is how a player ends
## up trusting a number the ledger never recorded.
##
## Like every drawer here it is built by code, not by a scene: `attach` is the
## wiring a host (or a headless test) drives, and the shipped scene gets the
## same wiring from `game_root.gd`.  It listens to `panel_requested` itself,
## so pressing Company is the whole interaction.

const VISIBLE_TRANSACTIONS := 8

var session: GameSession
var controller: InputController

var month_label: Label
var cash_label: Label
var revenue_label: Label
var expenses_label: Label
var profit_label: Label
var transactions_box: VBoxContainer

var _ledger_key := ""
var _built := false
var _dirty := true


func _ready() -> void:
	_ensure_built()


## Build once, whoever arrives: `_ready` in the shipped scene, `attach` for an
## orphan host.  A panel that builds only in `_ready` cannot be read by
## anything that never enters a tree.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(368, 0)
	# The band hosts one drawer at a time and this sheet is only as tall as its
	# rows, so it hugs the top of the band instead of stretching down it.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build()
	visible = false


func attach(game_session: GameSession, input: InputController) -> void:
	session = game_session
	controller = input
	_ensure_built()
	# The ledger speaks through `EconomyService`; the calendar through the
	# clock.  Both say "something in the books moved" and this panel repaints.
	session.economy.money_changed.connect(_on_changed)
	session.economy.transaction_recorded.connect(_on_changed)
	session.clock.month_changed.connect(_on_changed)
	if controller != null:
		controller.panel_requested.connect(_on_panel_requested)
		controller.tool_changed.connect(_on_tool_changed)
	_dirty = true


## Twin of `attach` for hosts that follow the configure idiom.
func configure(game_session: GameSession, input: InputController) -> void:
	attach(game_session, input)


func is_open() -> bool:
	return visible


func mark_dirty() -> void:
	_dirty = true


func _on_changed(_argument: Variant = null) -> void:
	_dirty = true


## Paint immediately instead of waiting for the refresh tick.  Tests and probes
## use it so a headless run need not wait on a wall-clock timer.
func refresh_now() -> void:
	_dirty = false
	_paint()


## The panel's own clock: signals set the dirty flag, this paints at the UI
## cadence.  Hidden means idle.
func refresh() -> void:
	if not _dirty or session == null:
		return
	_dirty = false
	_paint()


func _on_tool_changed(tool: String) -> void:
	# One drawer per band: an armed build tool owns the left band.
	if tool != InputController.TOOL_NONE and tool != InputController.TOOL_STOP_PICK:
		visible = false


func _on_panel_requested(panel: String) -> void:
	visible = panel == InputController.PANEL_COMPANY


## The ✕ and the Escape ladder arrive at the same place: the sheet goes down, and
## the controller is told which one it was, so the toolbar stops lighting it open.
func _close() -> void:
	visible = false
	if controller != null:
		controller.close_panel(InputController.PANEL_COMPANY)


# --- painting ----------------------------------------------------------


func _paint() -> void:
	month_label.text = "Books for %s" % session.clock.date.display()
	cash_label.text = GameTheme.money(session.economy.cash)
	var totals: Dictionary = session.economy.current_month_totals()
	revenue_label.text = GameTheme.money(float(totals["revenue"]))
	expenses_label.text = GameTheme.money(float(totals["expenses"]))
	var profit := float(totals["profit"])
	profit_label.text = GameTheme.signed_money(profit)
	profit_label.add_theme_color_override("font_color",
			GameTheme.GOOD if profit > 0.0 else (GameTheme.DANGER if profit < 0.0
					else GameTheme.TEXT_DIM))
	_paint_transactions()


## One row per live ledger entry, newest first — the entries `recent()` hands
## out, in that order, with the amount each one actually carries.  Rows are
## rebuilt only when the set of entry ids changes; a repaint of the same rows
## rewrites nothing.
func _paint_transactions() -> void:
	var entries := session.economy.recent(VISIBLE_TRANSACTIONS)
	var signature := ""
	for entry in entries:
		signature += "%d," % entry.id
	if signature == _ledger_key:
		return
	_ledger_key = signature
	for child in transactions_box.get_children():
		GameTheme.release(child)
	for entry in entries:
		transactions_box.add_child(_transaction_row(entry))


func _transaction_row(entry: EconomyService.Transaction) -> Control:
	var amount := entry.amount
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GameTheme.GAP)
	var date := GameTheme.small("%02d/%02d %d" % [entry.month, entry.day, entry.year])
	date.custom_minimum_size = Vector2(64, 0)
	row.add_child(date)
	var what := GameTheme.small(entry.description)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.clip_text = true
	what.tooltip_text = "%s · %s" % [session.economy.category_label(entry.category),
		entry.description]
	row.add_child(what)
	var money := Label.new()
	money.text = GameTheme.money(amount)
	money.add_theme_font_size_override("font_size", GameTheme.FONT_SMALL)
	money.add_theme_color_override("font_color",
			GameTheme.GOOD if amount > 0.0 else (GameTheme.DANGER if amount < 0.0
					else GameTheme.TEXT_DIM))
	row.add_child(money)
	return row


# --- static layout --------------------------------------------------------


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := GameTheme.heading("Company finances")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameTheme.button_for("✕", "Close the books " \
			+ KeyHints.hint_suffix("tool_cancel"))
	close.name = "Close"
	close.pressed.connect(_close)
	head.add_child(close)

	month_label = GameTheme.small("", GameTheme.TEXT_DIM)
	column.add_child(month_label)

	column.add_child(_figure("Cash on hand", "cash"))
	column.add_child(_figure("Revenue this month", "revenue"))
	column.add_child(_figure("Expenses this month", "expenses"))
	column.add_child(_figure("Profit this month", "profit"))
	column.add_child(HSeparator.new())
	column.add_child(GameTheme.small("Recent transactions", GameTheme.TEXT_DIM))
	transactions_box = VBoxContainer.new()
	transactions_box.add_theme_constant_override("separation", 2)
	column.add_child(transactions_box)


## One "key .... value" line, the value label kept for hosts that read it back.
func _figure(caption: String, which: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var key := GameTheme.small(caption, GameTheme.TEXT_DIM)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", GameTheme.FONT_BODY)
	value.add_theme_color_override("font_color", GameTheme.TEXT)
	row.add_child(value)
	match which:
		"cash":
			cash_label = value
		"revenue":
			revenue_label = value
		"expenses":
			expenses_label = value
		"profit":
			profit_label = value
	return row
