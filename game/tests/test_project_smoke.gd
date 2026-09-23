class_name TestProjectSmoke
extends TestBase

## Guards the conventions the whole repository depends on.

const WorldConstantsScript := preload("res://src/domain/world/world_constants.gd")


func test_world_constants_match_canonical_config() -> void:
	check_near(WorldConstants.TILE_SIZE, 1.0, "TILE_SIZE must be 1.0 game units")
	check_near(WorldConstants.HEIGHT_STEP, 0.25, "HEIGHT_STEP must be 0.25 game units")
	check_eq(WorldConstants.CHUNK_SIZE, 32, "terrain chunks are 32 tiles wide")
	check_eq(WorldConstants.MAP_WIDTH, 256, "V1 map is 256 tiles wide")
	check_near(WorldConstants.CAMERA_FIXED_PITCH, 35.264, "isometric pitch is fixed", 0.001)
	check_near(WorldConstants.CAMERA_DEFAULT_YAW, 45.0, "canonical yaw is 45 degrees")
	check_near(WorldConstants.STATION_CATCHMENT, 4.0, "station catchment starts at 4 tiles")
	# Not a decoration: every speed in the game is divided by this, so a silent
	# change here silently changes how fast the valley runs on screen.
	check_near(WorldConstants.TILE_METRES, 16.0,
			"a tile is worth sixteen metres — the anchor the whole speed scale is derived from")


func test_camera_zoom_band_is_ordered() -> void:
	check_lt(WorldConstants.CAMERA_ZOOM_CLOSE, WorldConstants.CAMERA_ZOOM_DEFAULT, "closest zoom is tighter than default")
	check_lt(WorldConstants.CAMERA_ZOOM_DEFAULT, WorldConstants.CAMERA_ZOOM_FAR, "default zoom is tighter than furthest")


func test_data_registry_reload_is_idempotent() -> void:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "first load_all() succeeds")
	var cargo_count: int = registry.cargo_ids().size()
	var stock_count: int = registry.rolling_stock.size()
	check_ge(cargo_count, 3, "V1 ships three cargos")
	check_true(registry.load_all(), "second load_all() succeeds — a re-scan must not flag its own data")
	check_eq(registry.errors.size(), 0, "reload leaves no stale errors")
	check_eq(registry.cargo_ids().size(), cargo_count, "reload yields the same cargo set")
	check_eq(registry.rolling_stock.size(), stock_count, "reload yields the same rolling stock")


func test_main_scene_instantiates() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	check_true(scene != null, "Game.tscn loads")
	if scene == null:
		return
	var instance := scene.instantiate()
	check_true(instance != null, "Game.tscn instantiates")
	check_eq(instance.name, "Game", "root node is named Game")
	check_true(instance.get_node_or_null("World3D") != null, "World3D exists under Game")
	check_true(instance.get_node_or_null("UI") != null, "UI exists under Game")
	check_true(instance.get_node_or_null("GameSession") != null, "GameSession exists under Game")
	instance.free()


## `rr.py game run` has to work with no scene named on the command line, and the
## one way it can silently stop working is the settings file itself: `project.godot`
## is a ConfigFile, not an INI, and `#` is not its comment character — the parser
## swallows the line that follows a `#` run. A `run/main_scene` sitting under three
## perfectly reasonable `#` comments therefore vanished while the file still looked
## right to anyone reading it, and the game became unlaunchable by its own guide.
func test_the_game_starts_without_being_told_which_scene() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	check_true(text != "", "project.godot is readable")
	for line in text.split("\n"):
		check_false(line.strip_edges().begins_with("#"),
				"comments in project.godot start with ';' — a '#' eats the next line: %s" % line)
	var entry := String(ProjectSettings.get_setting("application/run/main_scene"))
	check_true(entry != "", "the project names a main scene of its own")
	check_true(FileAccess.file_exists(entry), "and %s is really there" % entry)
	var menu: PackedScene = load(entry) if entry != "" else null
	check_true(menu != null, "the main scene loads")
	# A PackedScene is a Resource: reference-counted, so it goes when this scope
	# does.  `free()` on one is an error the runner treats as a failed run.


## A session is the one object in the game that cannot simply be freed.
##
## Every reversible action leaves a `Callable` on the undo stack, and that closure
## captured the builder that recorded it, so builder → stack → closure → builder is a
## cycle between two RefCounted services.  Nothing collects cycles: a session dropped
## with a non-empty stack keeps the builder, the rail network, the planner and the
## twenty-six-megabyte grid they stand on for the rest of the process — and in a test
## suite that builds a world per case, it does it fifty times over.  `shutdown()` is
## the release, and this is the guard that somebody remembered why it exists.
func test_a_session_being_thrown_away_releases_the_cycle_it_carries() -> void:
	var session := TestSession.create()
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a built coal line gives the builder something to record")
	check_gt(float(session.undo.depth()), 0.0, "and the reversible half of it is on the undo stack")
	var builder_seen: WeakRef = weakref(session.builder)
	TestSession.dispose(session)
	session = null
	check_true(builder_seen.get_ref() == null,
			"a disposed session leaves nothing behind that holds the builder, its rails and its grid alive")
