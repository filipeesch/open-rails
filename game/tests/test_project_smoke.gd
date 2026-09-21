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
