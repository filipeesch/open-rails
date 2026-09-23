class_name CursorState
extends Node

## The pointer is the one piece of UI a player never stops looking at, so the
## mode they are in has to show there — a rail in hand and an eraser in hand
## must not feel identical because some label far away changed.  The shapes are
## drawn from code rather than shipped as assets because the cursor is a state
## indicator, not content: routing it through the asset pipeline would let the
## compiler own a UI state and buy a file per glyph for two lines of pixels.


signal cursor_changed(state: String)

const STATE_NORMAL := "normal"
const STATE_BUILD := "build"
const STATE_REMOVE := "remove"

const SHAPE_ARROW := "arrow"
const SHAPE_BUILD := "build"
const SHAPE_REMOVE := "remove"

## Square edge of the drawn glyphs; the hotspot is their centre, so the tool
## points at exactly the tile the click will land on.
const SIDE := 19


var input: InputController
var _state := STATE_NORMAL
var _applied := SHAPE_ARROW


func attach(controller: InputController) -> void:
	input = controller
	controller.tool_changed.connect(_on_tool)


func configure(controller: InputController) -> void:
	attach(controller)


## Which mode the pointer speaks for: "normal", "build" or "remove".
func state() -> String:
	return _state


## The name of the shape last handed to the OS — "arrow" after a restore, the
## glyph after an arm.  A headless run cannot read the hardware cursor back, so
## this is the record of what was applied, asserted without a window.
func applied() -> String:
	return _applied


## Give the pointer back to the system.  Called when this node leaves the tree
## so a freed tool can never leave its glyph stuck on the screen.
func restore_normal() -> void:
	_apply(STATE_NORMAL)


func _on_tool(tool: String) -> void:
	match tool:
		InputController.TOOL_RAIL, InputController.TOOL_STATION:
			_apply(STATE_BUILD)
		InputController.TOOL_REMOVE:
			_apply(STATE_REMOVE)
		_:
			_apply(STATE_NORMAL)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and input != null:
		restore_normal()


func _apply(next_state: String) -> void:
	if _state == next_state:
		return
	_state = next_state
	var shape := SHAPE_BUILD if next_state == STATE_BUILD else \
		SHAPE_REMOVE if next_state == STATE_REMOVE else SHAPE_ARROW
	_applied = shape
	# `null` restores the system arrow instead of drawing a home-made one: the
	# normal cursor belongs to the player's platform, not to this game.
	Input.set_custom_mouse_cursor(shape_image(shape), Input.CURSOR_ARROW,
		Vector2.ZERO if shape == SHAPE_ARROW else Vector2(SIDE / 2, SIDE / 2))
	cursor_changed.emit(_state)


## The glyph's pixels: a hollow-outlined plus for building (it adds, and its
## centre is the tile), a filled X for removal (it takes away, and the eye
## reads the crossing as negation).  Transparent elsewhere, so whatever is
## under the cursor stays visible.
static func shape_image(shape: String) -> ImageTexture:
	if shape == SHAPE_ARROW:
		return null
	var mid := SIDE / 2
	var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	var ink := GameTheme.ACCENT if shape == SHAPE_BUILD else GameTheme.DANGER
	var outline := Color(0.05, 0.05, 0.05, 1.0)
	for y in SIDE:
		for x in SIDE:
			var colour := _pixel(shape, x - mid, y - mid, ink, outline)
			if colour.a > 0.0:
				image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)


## One pixel of a glyph, in centre-relative coordinates.  Kept free of nodes
## and of `Input` so the shapes themselves are testable with no cursor and no
## scene: the two glyphs must never agree on the tile's own pixel *and* its
## corners, or the player cannot tell them apart at a glance.
static func _pixel(shape: String, dx: int, dy: int, ink: Color, outline: Color) -> Color:
	if shape == SHAPE_BUILD:
		var arm := absi(dx) <= 7 or absi(dy) <= 7
		var spine := absi(dx) <= 2 and absi(dy) <= 7 or absi(dy) <= 2 and absi(dx) <= 7
		var spine_wide := absi(dx) <= 3 and absi(dy) <= 8 or absi(dy) <= 3 and absi(dx) <= 8
		if spine:
			return ink
		if spine_wide and arm:
			return outline
		return Color(0.0, 0.0, 0.0, 0.0)
	if maxi(absi(dx), absi(dy)) > 7:
		return Color(0.0, 0.0, 0.0, 0.0)
	if absi(dx - dy) <= 2 or absi(dx + dy) <= 2:
		return ink
	if absi(dx - dy) <= 3 or absi(dx + dy) <= 3:
		return outline
	return Color(0.0, 0.0, 0.0, 0.0)
