class_name GameTheme
extends RefCounted

## One theme for the whole interface.
##
## Restrained by design: soft dark panels, one accent, and typography doing most
## of the work.  Every widget builds from here so a spacing or colour change is
## a one-line edit rather than a sweep.

const BACKGROUND := Color(0.090, 0.098, 0.110, 0.94)
const PANEL := Color(0.140, 0.150, 0.168, 0.96)
const PANEL_SOFT := Color(0.180, 0.192, 0.212, 0.92)
const RAISED := Color(0.225, 0.240, 0.262, 1.0)
const BORDER := Color(0.32, 0.34, 0.38, 0.85)
const TEXT := Color(0.93, 0.93, 0.92)
const TEXT_DIM := Color(0.66, 0.68, 0.70)
const ACCENT := Color(0.86, 0.55, 0.22)
const GOOD := Color(0.46, 0.76, 0.44)
const WARNING := Color(0.93, 0.78, 0.30)
const DANGER := Color(0.86, 0.34, 0.30)

const FONT_SMALL := 11
const FONT_BODY := 13
const FONT_STRONG := 15
const FONT_TITLE := 19
const GAP := 8
const PAD := 10


static func build() -> Theme:
	var theme := Theme.new()
	theme.set_default_font_size(FONT_BODY)
	theme.set_stylebox("panel", "PanelContainer", panel(PANEL))
	theme.set_stylebox("panel", "Panel", panel(PANEL))
	theme.set_stylebox("normal", "Button", button(RAISED))
	theme.set_stylebox("hover", "Button", button(RAISED.lightened(0.10)))
	theme.set_stylebox("pressed", "Button", button(ACCENT.darkened(0.2)))
	theme.set_stylebox("disabled", "Button", button(PANEL_SOFT.darkened(0.2)))
	for control in ["Button", "Label", "LineEdit", "ItemList", "Label"]:
		theme.set_color("font_color", control, TEXT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_font_size("font_size", "Button", FONT_BODY)
	theme.set_constant("h_separation", "HBoxContainer", GAP)
	theme.set_constant("v_separation", "VBoxContainer", GAP)
	return theme


static func panel(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(PAD)
	box.shadow_size = 6
	box.shadow_color = Color(0, 0, 0, 0.35)
	return box


static func button(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = PAD
	box.content_margin_right = PAD
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box


static func row(active: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_SOFT if active else PANEL
	box.border_color = ACCENT if active else BORDER
	box.set_border_width_all(1 if active else 0)
	box.set_corner_radius_all(5)
	box.set_content_margin_all(GAP)
	return box


## A recessed meter track, paired with `meter_fill`.
static func meter_track() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BACKGROUND
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box


static func meter_fill(colour: Color = ACCENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(3)
	box.set_content_margin_all(0)
	return box


## Small inline stamp — a state or a cargo tag.
static func stamp(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour.r, colour.g, colour.b, 0.18)
	box.border_color = colour
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	return box


## Header/footer strip inside a panel: no border, so sections read as one slab.
static func section(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(0)
	box.set_content_margin_all(GAP)
	return box


static func stamp_label(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.add_theme_stylebox_override("normal", stamp(colour))
	return label


## A one-line note.  Deliberately not wrapping: an autowrap label inside a
## container reports a minimum height computed at its *minimum* width, which is
## how a drawer ends up asking for three thousand pixels.  Long text goes through
## `paragraph`, which pins the width it wraps at.
static func small(text: String, colour: Color = TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## Wrapping body text whose height must stay predictable: the wrap width is
## declared, so the panel's minimum size does not depend on who asks for it.
static func paragraph(text: String, colour: Color = TEXT_DIM,
		width: float = 320.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.custom_minimum_size = Vector2(width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func toggle(text: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	return button


static func labelled(text: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var key := Label.new()
	key.text = text
	key.add_theme_color_override("font_color", TEXT_DIM)
	key.add_theme_font_size_override("font_size", FONT_BODY)
	var field := Label.new()
	field.text = value
	field.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(key)
	row.add_child(field)
	return row


static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_STRONG)
	label.add_theme_color_override("font_color", ACCENT)
	return label


static func body(text: String, colour: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	return label


static func button_for(text: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	return button


## One honest percentage — a meter and its number must never disagree.
static func percent(fraction: float) -> String:
	return "%d%%" % int(roundf(clampf(fraction, 0.0, 1.0) * 100.0))


## A mass in tons — the unit the rolling-stock definitions are quoted in.
## Whole tons print whole, so a consist reads "40 t" rather than "40.0 t".
static func tons(value: float) -> String:
	var tenths := int(roundf(value * 10.0))
	if tenths % 10 == 0:
		return "%d t" % int(float(tenths) / 10.0)
	return "%.1f t" % (float(tenths) / 10.0)


## A speed in km/h, the unit the player reasons in.  Every km/h figure in the
## interface comes through here so the drawer and the yard cannot drift apart.
static func kmh(value: float) -> String:
	return "%d km/h" % int(roundf(value))


static func money(amount: float) -> String:
	# One money formatter in the codebase, and it lives with the money. A panel that
	# rounds differently from the ledger is how a player ends up trusting a number
	# that is not the one they were charged.
	return Money.format(amount)


## For the top bar only, where the number has to fit: it abbreviates instead of
## lying about the cent value it can no longer show.
static func money_compact(amount: float) -> String:
	return Money.format_compact(amount)


static func signed_money(amount: float) -> String:
	return ("+" if amount >= 0.0 else "") + money_compact(amount)
