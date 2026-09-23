class_name NotificationCenter
extends PanelContainer

## Toasts for the things a player must not miss.  Domain events arrive through
## GameSession's signals; nothing here emits back into the simulation.

const MAX_VISIBLE := 5
const LIFETIME := 5.0
## The toast column is a fixed box, anchored to the bottom-right corner of the
## window and standing clear of the tool bar.  A toast has to be somewhere the
## player's own work is not: the top band is the ledger, the left band is the tool
## drawer, and the right band above this one is the inspector — so the corner
## above the tool bar is the one patch no other layer claims.  Sizing it for
## `MAX_VISIBLE` toasts rather than for one means a message cannot shove the ones
## already reading, and the box itself draws nothing: only the toasts have a panel.
const WIDTH := 320.0
const EDGE := 8.0
const ROW := 40.0
const GAP := 4.0

var session: GameSession
var column: VBoxContainer
var _rows: Array[Dictionary] = []


func attach(game_session: GameSession) -> void:
	session = game_session
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the corner rather than laid out by its parent: the `Notifications`
	# control it lives under spans the whole window, and a code-built `Control` left
	# at its default anchors collapses into the top-left — which is where the ledger
	# is drawn, so an unplaced toast would land on the date.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(WIDTH + EDGE)
	offset_right = -EDGE
	offset_bottom = -(float(GameTheme.CHROME_BAND) + EDGE)
	offset_top = offset_bottom - box_height()
	custom_minimum_size = Vector2(WIDTH, 0)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	session.notice.connect(push)
	session.economy.insufficient_funds.connect(_on_insufficient)
	session.industries.industry_storage_full.connect(_on_storage_full)
	session.station_created.connect(func(id): push("Opened %s" % session.stations.name_of(id), "good"))
	session.cargo_delivered.connect(_on_delivered)
	session.clock.month_changed.connect(_on_month)


func configure(game_session: GameSession) -> void:
	attach(game_session)


func push(message: String, severity: String = "info") -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.panel(_tint(severity)))
	var label := GameTheme.body(message, _text_colour(severity))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(panel)
	_rows.append({"node": panel, "expires": float(Time.get_ticks_msec()) / 1000.0 + LIFETIME})
	while _rows.size() > MAX_VISIBLE:
		var oldest: Dictionary = _rows.pop_front()
		oldest["node"].free()


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	while not _rows.is_empty() and float(_rows[0]["expires"]) <= now:
		var row: Dictionary = _rows.pop_front()
		if is_instance_valid(row["node"]):
			row["node"].free()


func visible_count() -> int:
	return _rows.size()


## The height the column reserves for its toasts, at the most it will ever show.
func box_height() -> float:
	return float(MAX_VISIBLE) * ROW + float(MAX_VISIBLE - 1) * GAP


func _on_insufficient(cost: float, cash: float, label: String) -> void:
	push("Cannot afford %s: %s needed, %s available" % [label, GameTheme.money(cost), GameTheme.money(cash)], "bad")


func _on_storage_full(industry_id: int, cargo_id: String) -> void:
	push("%s has no room for more %s" % [session.industries.name_of(industry_id),
		session.data.cargo_display(cargo_id)], "warning")


func _on_delivered(station_id: int, cargo_id: String, quantity: float, revenue: float) -> void:
	if revenue < 1.0:
		return
	push("%s delivered %d %s · %s" % [session.stations.name_of(station_id), int(quantity),
		session.data.cargo_display(cargo_id), GameTheme.money(revenue)], "good")


func _on_month(date: GameDate) -> void:
	var totals := session.economy.current_month_totals()
	push("%s: %s revenue, %s expenses" % [date.display(), GameTheme.money(float(totals["revenue"])),
		GameTheme.money(float(totals["expenses"]))], "info")


func _tint(severity: String) -> Color:
	match severity:
		"good":
			return Color(GameTheme.GOOD.r, GameTheme.GOOD.g, GameTheme.GOOD.b, 0.22)
		"bad":
			return Color(GameTheme.DANGER.r, GameTheme.DANGER.g, GameTheme.DANGER.b, 0.26)
		"warning":
			return Color(GameTheme.WARNING.r, GameTheme.WARNING.g, GameTheme.WARNING.b, 0.22)
	return GameTheme.PANEL


func _text_colour(severity: String) -> Color:
	match severity:
		"good":
			return GameTheme.GOOD.lightened(0.35)
		"bad":
			return GameTheme.DANGER.lightened(0.35)
		"warning":
			return GameTheme.WARNING.lightened(0.3)
	return GameTheme.TEXT
