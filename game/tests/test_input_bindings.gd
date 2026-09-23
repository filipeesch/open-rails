class_name TestInputBindings
extends TestBase

## The keys and gestures the interface advertises, checked against the engine.
##
## Three separate slips surfaced in one afternoon of playing the real window, and
## they are the same slip seen from three sides: something on the screen claimed a
## thing the game did not do.  A tool button printed a letter no key had ever been
## bound to.  The help named `Home` and `F3` while the engine answered `Tab` and
## `F4`.  And the camera could not be zoomed from the machine the game was being
## played on at all, because the only zoom input ever written down was a mouse
## wheel — a thing a MacBook does not have.  A trackpad reports a two-finger
## scroll as `InputEventPanGesture` and a pinch as `InputEventMagnifyGesture`, and
## neither of them ever arrives as a mouse button, so a listener for wheel buttons
## alone stays silent through every gesture its player makes.
##
## No case here opens a window.  The events are the same classes the operating
## system hands the engine, fed to the handler that reads them, and the verdict is
## read off the camera rather than off the handler — so a handler that computes a
## lovely number and never spends it fails, and so does one that spends it the
## wrong way round.

const ZOOM_START := 28.0
## What a two-finger swipe is being held to: the same rule a middle-drag already
## follows, ground going where the fingers go.
const SWIPE := Vector2(18.0, -7.0)

var _view: TestView
var _controller: InputController


func setup() -> void:
	_view = TestView.stage()
	_controller = InputController.new()
	_controller.attach(_view.session, _view.rig, _view.selection)
	_controller.viewport_size = TestView.VIEWPORT_SIZE
	_view.zoom_to(ZOOM_START)


func teardown() -> void:
	if _controller != null:
		_controller.free()
		_controller = null
	if _view != null:
		_view.dispose()
		_view = null


# --- what the interface promises --------------------------------------------

func test_every_shortcut_a_button_advertises_is_bound_in_the_engine() -> void:
	for entry in BottomToolbar.ENTRIES:
		var label := String(entry["label"])
		var action := String(entry["action"])
		if action == "":
			# Silence is allowed.  A letter the engine has never heard of is not,
			# because a hint is a lesson, and a wrong lesson is worse than none.
			check_eq(KeyHints.hint_suffix(action), "",
					"%s advertises no shortcut, because it has none" % label)
			continue
		check_true(InputMap.has_action(action),
				"%s offers %s, the action its hint is built from" % [label, action])
		check_gt(InputMap.action_get_events(action).size(), 0,
				"and %s is bound to a real key, not merely declared" % action)
		check_neq(KeyHints.hint_suffix(action), "",
				"so the button is allowed to name the key, and names one")


func test_the_tool_bar_promises_a_key_the_input_map_will_honour() -> void:
	# The expected key is worked out here, straight from the InputMap, rather than
	# asked of `KeyHints` — a tooltip graded against the class that writes it can
	# only ever agree.  What is being compared is the string the button shows a
	# player against the binding the handlers will actually test.
	var toolbar := BottomToolbar.new()
	toolbar.attach(_view.session, _controller)
	var advertised := 0
	for button in _buttons_of(toolbar):
		var entry := _entry_named(button.text)
		check_true(not entry.is_empty(), "the tool bar holds an entry for its %s button" % button.text)
		var action := String(entry["action"])
		if action == "":
			continue
		advertised += 1
		var events: Array = InputMap.action_get_events(action)
		var key := OS.get_keycode_string((events[0] as InputEventKey).physical_keycode)
		check_has(button.tooltip_text, key,
				"the %s button's tooltip names %s, which is the key the engine binds" % [
					button.text, key])
	check_eq(advertised, 3, "three of the five entries carry a shortcut to check")
	toolbar.free()


func test_the_keys_the_help_names_are_the_keys_the_engine_answers_to() -> void:
	# Written by hand on purpose, from the docs and the help screen: this is the
	# fixture that fails when a binding moves out from under the manual.  The
	# original drift was exactly this — the help promised `Home` and `F3`, the
	# engine answered `Tab` and `F4`, and nothing in the suite was comparing the
	# two, because the numbers only ever lived in `project.godot`.
	var answers := {
		"cam_reset": [KEY_HOME],
		"debug_overlay": [KEY_F3, KEY_F4],
		"build_mode": [KEY_B],
		"company_panel": [KEY_C],
		InputController.ZOOM_IN_ACTION: [KEY_EQUAL, KEY_KP_ADD],
		InputController.ZOOM_OUT_ACTION: [KEY_MINUS, KEY_KP_SUBTRACT],
	}
	for action in answers.keys():
		check_true(InputMap.has_action(action), "%s is a declared action" % action)
		var bound := {}
		for event in InputMap.action_get_events(action):
			bound[(event as InputEventKey).physical_keycode] = true
		for keycode in Array(answers[action]):
			check_true(bound.has(int(keycode)),
					"%s answers to %s" % [action, OS.get_keycode_string(int(keycode))])

	# `Tab` used to be bound to the camera reset as well, and it never fired: Tab is
	# the engine's own focus-walk key, and every control in this interface takes
	# focus, so a button that has been clicked once eats the press before the valley
	# ever sees it.  A binding that cannot arrive is a lie about a shortcut.
	var reset_keys := {}
	for event in InputMap.action_get_events("cam_reset"):
		reset_keys[(event as InputEventKey).physical_keycode] = true
	check_false(reset_keys.has(int(KEY_TAB)),
			"the camera reset does not claim the engine's focus key")


func test_a_hint_is_the_glyph_a_player_reads_not_the_engines_own_word() -> void:
	# `OS.get_keycode_string` is honest and useless: it says "Equal", "Kp Add",
	# "Escape".  A button has to say what is printed on the keycap.
	check_eq(KeyHints.label_for_keycode(KEY_EQUAL), "=",
			"the zoom key is shown as the glyph on the key")
	check_eq(KeyHints.label_for_keycode(KEY_KP_ADD), "+",
			"and the keypad's own zoom key is distinguishable from the minus key")
	check_eq(KeyHints.label_for_keycode(KEY_MINUS), "-", "the out step reads as a minus")
	check_eq(KeyHints.label_for_keycode(KEY_B), "B", "a letter needs no translation")
	check_eq(KeyHints.label_for_keycode(KEY_NONE), "",
			"and a key that is not a key earns no hint at all")


# --- the gestures a trackpad actually sends -------------------------------

func test_a_pinch_on_a_trackpad_zooms_because_a_mac_book_sends_no_wheel_buttons() -> void:
	var rig := _view.rig
	var before := rig.desired_ortho_size
	_pinch(1.2)
	check_lt(rig.desired_ortho_size, before,
			"spreading the fingers magnifies — less valley in frame, ground closer")
	_view.settle()
	check_near(rig.orthographic_tiles(), rig.desired_ortho_size,
			"and the rig actually travels to where the pinch aimed it", 0.5)

	_pinch(0.8)
	check_near(rig.desired_ortho_size, before,
			"closing the fingers brings the same view back", 0.5)
	# A gesture of factor 1.0 is the engine saying "nothing changed"; it must not
	# spend a notch of zoom on its own account.
	var held := rig.desired_ortho_size
	_pinch(1.0)
	check_near(rig.desired_ortho_size, held, "a pinch that does not pinch leaves the view alone", 0.001)


func test_a_two_finger_swipe_moves_the_ground_the_way_a_middle_drag_does() -> void:
	var rig := _view.rig
	var here := rig.desired_target
	var swipe := InputEventPanGesture.new()
	swipe.delta = SWIPE
	_controller._unhandled_input(swipe)
	var by_gesture := rig.desired_target
	check_neq(by_gesture, here,
			"a two-finger swipe moves the valley, which is the input a trackpad sends "
			+ "and the one the game used to ignore entirely")

	# The same travel asked of the mouse: a middle-drag whose fingers moved exactly
	# as far in the same direction.  Both handlers exist to obey one rule — ground
	# goes where the fingers go, 1:1, never at the panning *speed* — and a player
	# who switches between the two must not find the valley answering differently.
	rig.desired_target = here
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	middle.position = _view.centre_pixel()
	_controller._unhandled_input(middle)
	var drag := InputEventMouseMotion.new()
	drag.position = _view.centre_pixel() + SWIPE
	drag.relative = SWIPE
	_controller._unhandled_input(drag)
	_controller.is_panning = false
	var by_drag := rig.desired_target

	check_near(by_gesture.x, by_drag.x,
			"the swipe and a middle-drag of the same travel agree on the x axis", 0.001)
	check_near(by_gesture.y, by_drag.y,
			"and on the y axis, so no hand has to relearn either one", 0.001)


# --- the keys, spent the same way the wheel spends them -------------------

func test_the_zoom_keys_spend_one_wheel_notch_and_in_the_same_direction() -> void:
	var rig := _view.rig
	var from := ZOOM_START

	rig.desired_ortho_size = from
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	_controller._unhandled_input(wheel)
	var by_wheel := rig.desired_ortho_size
	check_lt(by_wheel, from,
			"scrolling up brings the ground closer — the one convention every wheel has")

	rig.desired_ortho_size = from
	_press(KEY_EQUAL)
	check_near(rig.desired_ortho_size, by_wheel,
			"and the = key spends exactly the same notch, so wheel and keyboard cannot "
			+ "disagree about how far a step goes", 0.001)

	rig.desired_ortho_size = from
	_press(KEY_MINUS)
	check_gt(rig.desired_ortho_size, from, "while the - key opens the view back out")


func test_the_b_key_builds_and_the_c_key_opens_the_company() -> void:
	# The two advertised letters the toolbar had been printing for the longest
	# time without anything answering them.  Both are graded on the state the verb
	# changes, not on a call being made.
	var tools: Array[String] = []
	_controller.tool_changed.connect(func(tool: String) -> void: tools.append(tool))
	var panels: Array[String] = []
	_controller.panel_requested.connect(func(panel: String) -> void: panels.append(panel))

	_press(KEY_B)
	check_eq(_controller.tool, InputController.TOOL_RAIL, "B arms the rail tool, as the button says")
	_press(KEY_B)
	check_eq(_controller.tool, InputController.TOOL_NONE,
			"and pressing it again puts it down, since it is the same verb as the button")

	_press(KEY_C)
	check_eq(_controller.active_panel, InputController.PANEL_COMPANY,
			"C opens the company panel, as its button says")
	check_eq(panels.size(), 1, "and the shell is told once")
	_press(KEY_C)
	check_eq(_controller.active_panel, "", "and closes it again")
	check_eq(tools.size(), 2, "the keypresses never invented a third tool change on the way")


# --- fixtures -------------------------------------------------------------

func _pinch(factor: float) -> void:
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = factor
	_controller._unhandled_input(pinch)


func _press(keycode: int) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	# A real key press carries both spellings, and the bindings in `project.godot`
	# are written as physical keys — leave this one out and no action matches,
	# which is the shape of a test that passes for the wrong reason.
	key.physical_keycode = keycode
	key.pressed = true
	_controller._unhandled_input(key)


func _buttons_of(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_buttons_of(child))
	return out


func _entry_named(label: String) -> Dictionary:
	for entry in BottomToolbar.ENTRIES:
		if String(entry["label"]) == label:
			return entry
	return {}
