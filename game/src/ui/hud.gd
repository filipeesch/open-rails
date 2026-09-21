class_name Hud
extends PanelContainer

## The permanent top bar: date, cash, monthly profit and the speed controls.
##
## It reads the domain and nothing else.  No signal from here ever reaches a
## simulation service — the speed buttons drive the clock, which is the one piece
## of state the shell is allowed to push.

var session: GameSession
var date_label: Label
var cash_label: Label
var profit_label: Label
var speed_buttons: Array[Button] = []
var _buttons: HBoxContainer
var _tick: Timer
var _last_cash := 0.0
var _last_profit := 0.0
var _last_date := ""


func attach(game_session: GameSession) -> void:
	session = game_session
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	date_label = GameTheme.body("Jan 1850", GameTheme.TEXT)
	date_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	date_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(date_label)

	row.add_child(VSeparator.new())

	cash_label = GameTheme.body(GameTheme.money_compact(0.0))
	cash_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	cash_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(cash_label)

	profit_label = GameTheme.body("…/mo", GameTheme.TEXT_DIM)
	profit_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(profit_label)

	row.add_child(VSeparator.new())

	_buttons = HBoxContainer.new()
	row.add_child(_buttons)
	for index in session.clock.SPEED_LABELS.size():
		var button := Button.new()
		button.text = session.clock.SPEED_LABELS[index]
		# Toggle mode is what lets a dial hold a position.  A plain Button refuses
		# to stay pressed, so without this the row could never show which speed is
		# in force — `_refresh` wrote `button_pressed` every pass and the engine
		# dropped it on the floor.
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.tooltip_text = ["Pause", "Normal speed", "Fast", "Very fast"][index]
		button.custom_minimum_size = Vector2(38, 0)
		button.pressed.connect(_on_speed.bind(index))
		_buttons.add_child(button)
		speed_buttons.append(button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var company := GameTheme.body(session.economy.company_name, GameTheme.TEXT_DIM)
	row.add_child(company)

	session.economy.money_changed.connect(_on_money)
	session.clock.month_changed.connect(func(_date): _refresh())
	# Nothing on this bar changes faster than a month or a payment, so it is
	# driven by those signals plus one slow timer that only exists to notice a
	# speed change made somewhere else.  Polling the domain per frame was the
	# old way and it bought nothing.
	_tick = Timer.new()
	_tick.name = "RefreshTick"
	_tick.wait_time = 0.25
	_tick.autostart = true
	_tick.timeout.connect(_refresh)
	add_child(_tick)
	_refresh()


func configure(game_session: GameSession) -> void:
	attach(game_session)


func _on_speed(index: int) -> void:
	session.clock.set_speed_index(index)
	_refresh()


func _on_money(_amount: float = 0.0, _cash: float = 0.0, _label: String = "") -> void:
	_refresh()


func _refresh() -> void:
	if session == null:
		return
	var date_text := session.clock.date.display()
	if date_text != _last_date:
		date_label.text = date_text
		_last_date = date_text
	var cash := session.economy.cash
	if absf(cash - _last_cash) > 0.001:
		cash_label.text = GameTheme.money_compact(cash)
		cash_label.add_theme_color_override("font_color",
			GameTheme.DANGER if cash < 0.0 else GameTheme.TEXT)
		_last_cash = cash
	var totals := session.economy.current_month_totals()
	var profit := float(totals["profit"])
	if absf(profit - _last_profit) > 0.001:
		profit_label.text = "%s/mo" % GameTheme.signed_money(profit)
		profit_label.add_theme_color_override("font_color",
			GameTheme.GOOD if profit > 0.0 else (GameTheme.DANGER if profit < 0.0 else GameTheme.TEXT_DIM))
		_last_profit = profit
	for index in speed_buttons.size():
		speed_buttons[index].button_pressed = index == session.clock.speed_index
		speed_buttons[index].add_theme_color_override("font_color",
			GameTheme.ACCENT if index == session.clock.speed_index else GameTheme.TEXT)
