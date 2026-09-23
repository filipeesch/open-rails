class_name KeyHints
extends RefCounted

## Turns a bound key into the word a player reads, from the InputMap itself.
##
## The interface has always wanted to advertise its shortcuts, and every place that
## did so wrote the letter out by hand.  Hand-written hints drift: a binding moves
## in `project.godot` and the tooltip keeps promising the old key, or a hint names a
## key that was never bound at all and the player learns that the game lies to them.
## A hint derived from the same `InputMap` the handlers ask cannot drift, because
## there is nothing left to drift from — no binding, no hint.
##
## This is also the one lookup the help and settings screens are meant to read, so
## "what does this key do" has exactly one answer in the codebase.


## The friendly glyph for a key, or "" when the physical key has no useful name.
## `OS.get_keycode_string` speaks for the engine ("Equal", "Kp Add"), which is
## correct in a log and useless on a button.
const FRIENDLY := {
	"Equal": "=",
	"Minus": "-",
	"Kp Add": "+",
	"Kp Subtract": "-",
	"Escape": "Esc",
}


## The primary key for an action — the first one bound — as a short label, or ""
## when nothing is bound.  A tooltip names one key because a reminder is not a
## reference; `keys_for` is the reference.
static func key_for(action: String) -> String:
	var keys := keys_for(action)
	return "" if keys.is_empty() else keys[0]


## Every key bound to an action, in binding order, each with its modifiers.
static func keys_for(action: String) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		var label := label_for(event)
		if label != "" and not out.has(label):
			out.append(label)
	return out


## A display label for one input event, or "" for anything that is not a key —
## a mouse button is not a shortcut worth spelling out in a tooltip.
static func label_for(event: InputEvent) -> String:
	if not (event is InputEventKey):
		return ""
	var key := event as InputEventKey
	var glyph := label_for_keycode(key.physical_keycode)
	if glyph == "":
		return ""
	var prefix := ""
	if key.ctrl_pressed:
		prefix += "Ctrl+"
	if key.meta_pressed:
		prefix += "Cmd+"
	if key.shift_pressed:
		prefix += "Shift+"
	return prefix + glyph


## The friendly glyph for a physical keycode.  Public because a test asserts the
## advertised hint and the engine's own key agree letter for letter.
static func label_for_keycode(keycode: int) -> String:
	if keycode == KEY_NONE:
		return ""
	var raw := OS.get_keycode_string(keycode)
	if raw == "":
		return ""
	return String(FRIENDLY.get(raw, raw))


## A tooltip suffix: " (B)" when the action has a key, "" when it does not.  The
## point of returning "" rather than a placeholder is that the sentence stays
## true either way.
static func hint_suffix(action: String) -> String:
	var key := key_for(action)
	return "" if key == "" else " (%s)" % key
