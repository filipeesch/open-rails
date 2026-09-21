class_name DebugOverlay
extends PanelContainer

## F3: the counters a reviewer needs to believe the performance claims.
##
## Everything shown here comes from a domain or renderer counter — nothing is
## estimated.  A counter that does not exist is absent rather than guessed.

const TOGGLE_ACTION := "debug_overlay"

var session: GameSession
var terrain: TerrainRenderer
var rail: RailRenderer
var label: RichTextLabel
var _enabled := false
var _sample_seconds := 0.0


func attach(game_session: GameSession, terrain_renderer: TerrainRenderer, rail_renderer: RailRenderer) -> void:
	session = game_session
	terrain = terrain_renderer
	rail = rail_renderer
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(Color(0.04, 0.05, 0.06, 0.92)))
	custom_minimum_size = Vector2(340, 300)
	# Clear of the top bar and the left band, where the reviewer's eye already is.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 392.0
	offset_top = 76.0
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	add_child(label)
	visible = false


func configure(game_session: GameSession, terrain_renderer: TerrainRenderer, rail_renderer: RailRenderer) -> void:
	attach(game_session, terrain_renderer, rail_renderer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()


func toggle() -> void:
	_enabled = not _enabled
	visible = _enabled
	# Fill the panel on the press itself: an overlay that opens blank and waits a
	# quarter of a second to say anything reads as a broken key binding.
	if _enabled and session != null:
		label.text = _report()


func is_enabled() -> bool:
	return _enabled


func _process(delta: float) -> void:
	if not _enabled or session == null:
		return
	_sample_seconds += delta
	if _sample_seconds >= 0.25:
		_sample_seconds = 0.0
		label.text = _report()


func _report() -> String:
	var clock := session.clock
	var budget := clock.tick_time_average_micros()
	var lines: PackedStringArray = []
	lines.append("[b]Frame[/b]")
	var fps := Engine.get_frames_per_second()
	lines.append("FPS %.1f   frame %.2f ms" % [fps, (1000.0 / fps) if fps > 0.0 else 0.0])
	lines.append("draw calls %d   primitives %s" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		_thousands(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))])
	lines.append("")
	lines.append("[b]Simulation[/b]")
	lines.append("tick avg %.0f µs of %.0f µs budget" % [float(budget), 1000000.0 / SimulationClock.TICK_RATE])
	lines.append("speed %s   tick %d   %s" % [clock.speed_label(), clock.tick_count, clock.date.display_full()])
	lines.append("trains %d   stations %d   rail tiles %d" % [
		session.trains.count(), session.stations.count(), session.rail.rail_tiles().size()])
	lines.append("cargo delivered %.0f   revenue %s" % [session.cargo.delivered_total(),
		GameTheme.money(session.cargo.revenue_total())])
	lines.append("ledger consistent: %s   rows %d" % [
		"yes" if session.economy.is_consistent() else "[color=#e07a7a]NO[/color]",
		session.economy.ledger().size()])
	lines.append("")
	lines.append("[b]World[/b]")
	lines.append("scene nodes %d (no per-tile nodes allowed)" % _node_count())
	if terrain != null:
		lines.append("terrain chunks %d   tris %s   rebuilds/s %d" % [
			terrain.live_chunk_nodes(), _thousands(terrain.triangle_total()),
			terrain.rebuilds_this_second()])
	if rail != null:
		lines.append("rail chunks %d   tris %s   rebuilds %d" % [
			rail.live_chunk_nodes(), _thousands(rail.triangle_total()), rail.rebuild_count()])
	lines.append("path finds %d (%.0f ms)   planner searches %d" % [
		session.rail.path_find_calls(), session.rail.path_find_micros_total() / 1000.0,
		session.planner.search_calls()])
	if _node_count() > 6000:
		lines.append("[color=#e07a7a]node count is far above budget[/color]")
	if budget > 20000.0:
		lines.append("[color=#e0c07a]tick uses over 20%% of the frame budget[/color]")
	return "\n".join(lines)


func _node_count() -> int:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return 0
	return _count(tree.root)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _thousands(value: int) -> String:
	return "%dk" % int(roundf(value / 1000.0))
