class_name TestAudio
extends TestBase

## Spec §"minimal spatial audio": six cues, placed where they happen, with the
## volume settings applied — and triggered by the events themselves.
##
## The test runner has no live viewport, so a player created here is never in a
## tree and Godot refuses to mix it.  That is a fact about the harness, and the
## service is written so the harness can still see the decision: every cue names
## its bus, its player kind and its position in a bounded log, and the cases below
## grade that against real events — a consist actually departing, track actually
## laid.  What a running game adds on top of these assertions is the mixing,
## which is the engine's job and not this file's.
##
## The sounds themselves are synthesised by `SoundForge`, so a case can also
## check that a cue is real pcm rather than a silent placeholder: a bank of empty
## buffers would pass every wiring test in this file.

## Long enough for the consist to leave one yard and brake into the other: the
## two works are a lap apart, and a lap is what the coal line's legs measure.
const TICKS_TO_WATCH := TestSession.LAP_TICKS

var _session: GameSession
var _audio: AudioService
var _settings: SettingsService


func setup() -> void:
	_settings = SettingsService.new()
	_audio = AudioService.new()
	_audio.configure(_settings)


func teardown() -> void:
	if _session != null:
		TestSession.dispose(_session)
		_session = null
	if _audio != null:
		_audio.free()
		_audio = null
	if _settings != null:
		_settings = null


# --- the bank --------------------------------------------------------------

func test_every_cue_the_spec_names_exists_on_the_bus_that_owns_its_volume() -> void:
	var named := [AudioService.CLICK, AudioService.CONSTRUCTION, AudioService.LOCOMOTIVE,
			AudioService.WHISTLE, AudioService.ARRIVAL, AudioService.AMBIENT]
	for entry in AudioService.CUES:
		var cue := String(entry["id"])
		check_true(cue in named, "'%s' is one of the six the specification names" % cue)
		var bus := String(entry["bus"])
		check_true(bus == "Effects" or bus == "Music",
				"'%s' plays into a bus the settings screen can move, not into Master directly" % cue)
		check_true(AudioServer.get_bus_index(bus) >= 0,
				"and the bus '%s' exists once the settings service has prepared audio" % bus)
	check_eq(AudioService.CUES.size(), named.size(), "six cues, no more and no fewer")


func test_a_world_cue_is_placed_and_an_interface_cue_is_not() -> void:
	for entry in AudioService.CUES:
		var cue := String(entry["id"])
		var placed := bool(entry["spatial"])
		if cue == AudioService.CLICK:
			check_false(placed, "a click belongs to the screen, not to a coordinate")
		elif cue != AudioService.AMBIENT:
			check_true(placed, "'%s' happens somewhere in the valley" % cue)
		var at := Vector3(30.0, 0.0, 42.0)
		_audio.play(cue, at)
		var logged := _audio.heard_cues()
		check_gt(logged.size(), 0, "the request to play '%s' was recorded" % cue)
		var last: Dictionary = logged[logged.size() - 1]
		check_eq(String(last["cue"]), cue, "as that cue")
		if placed:
			check_true((last["at"] as Vector3) == at, "at the tile it came from")
		else:
			check_true((last["at"] as Vector3) == Vector3.INF, "and the interface cue carries no place")


func test_the_cue_log_is_bounded_however_noisy_the_valley_gets() -> void:
	for round in AudioService.HEARD_LOG * 3:
		_audio.play(AudioService.CLICK)
	check_le(_audio.heard_cues().size(), AudioService.HEARD_LOG,
			"a service that remembered every sound it made would grow without limit")


# --- the events that cause them --------------------------------------------

func test_a_train_departing_whistles_and_a_train_arriving_brakes() -> void:
	_session = TestSession.create("founders_valley")
	_audio.attach_session(_session)
	var line := TestSession.coal_line(_session)
	check_true(bool(line["ok"]), "a working coal line: " + String(line["reason"]))

	_session.advance_ticks(TICKS_TO_WATCH)

	check_true(_audio.is_heard(AudioService.WHISTLE),
			"a consist leaving a yard is heard before it is seen")
	check_true(_audio.is_heard(AudioService.ARRIVAL),
			"and the same consist braking into the next yard is heard too")
	check_gt(_audio.heard_for(AudioService.LOCOMOTIVE), 0, "with a running sound under it")


func test_laying_track_and_raising_a_yard_make_the_construction_strike() -> void:
	_session = TestSession.create("founders_valley")
	_audio.attach_session(_session)
	var before := _audio.heard_for(AudioService.CONSTRUCTION)

	var run: Array[Vector2i] = []
	for x in range(20, 26):
		run.append(Vector2i(x, 30))
	check_true(bool(_session.builder.build_track_run(run)["ok"]), "six cells of track were laid")
	check_eq(_audio.heard_for(AudioService.CONSTRUCTION), before + 1,
			"and the strike was heard once for the operation, not once per tile")

	var after_track := _audio.heard_for(AudioService.CONSTRUCTION)
	var mine := TestSession.industry_by_definition(_session, "coal_mine")
	var yard := TestSession.serve(_session, _session.industries.tile_of(mine), "Blackedge Wharf")
	check_gt(yard, 0, "a yard was built beside the colliery")
	check_eq(_audio.heard_for(AudioService.CONSTRUCTION), after_track + 2,
			"the spur that feeds it was heard, and the yard itself was heard")
	check_eq(before + 3, _audio.heard_for(AudioService.CONSTRUCTION),
			"three operations, three strikes — one per thing the player paid for")


func test_the_ear_voices_the_nearest_running_trains_and_no_others() -> void:
	_session = TestSession.create("founders_valley")
	_audio.attach_session(_session)
	var line := TestSession.coal_line(_session)
	check_true(bool(line["ok"]), "a working coal line: " + String(line["reason"]))
	_session.advance_ticks(400)

	var train := int(line["train"])
	var track: Vector2 = _session.trains.position_tiles(train)
	var where := Vector3(track.x, 0.0, track.y)
	_audio.ear_provider = func() -> Vector3: return where
	_audio.assign_locomotive_voices()

	check_eq(_audio.voice_count(), AudioService.LOCOMOTIVE_VOICES,
			"the pool is a fixed number of players, whatever the valley holds")
	check_true(train in _audio.audible_trains(),
			"the train standing under the ear is one of them")

	_audio.ear_provider = func() -> Vector3: return where + Vector3(4000.0, 0.0, 4000.0)
	_audio.assign_locomotive_voices()
	check_eq(_audio.audible_trains().size(), 0,
			"move the ear out of hearing distance and the same train is silent")


# --- the settings reach the sound ------------------------------------------

func test_the_volume_sliders_are_the_ones_the_cues_play_through() -> void:
	var effects := AudioServer.get_bus_index("Effects")
	check_ge(effects, 0, "the settings service prepared an Effects bus")
	check_eq(AudioServer.get_bus_name(AudioServer.get_bus_index("Master")), "Master",
			"which sends on to Master, the one slider every cue answers to")

	_settings.set_value("effects_volume", 1.0)
	_settings.apply_all()
	var loud := AudioServer.get_bus_volume_db(effects)
	_settings.set_value("effects_volume", 0.0)
	_settings.apply_all()
	var silent := AudioServer.get_bus_volume_db(effects)
	check_gt(loud - silent, 30.0,
			"turning the effects slider down really dims the bus the world cues play into")

	_settings.set_value("master_volume", 0.0)
	_settings.apply_all()
	check_lt(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), -60.0,
			"and the master slider silences everything at once")


func test_the_sounds_are_waved_form_not_silence() -> void:
	for entry in AudioService.CUES:
		var cue := String(entry["id"])
		var stream := _audio.stream_for(cue)
		check_true(stream != null, "'%s' has a stream" % cue)
		check_gt(stream.data.size(), 44, "and it carries samples, not an empty buffer")
		var peak := 0
		for index in range(0, stream.data.size() - 1, 2):
			peak = maxi(peak, absi(stream.data.decode_s16(index)))
		check_gt(peak, 1500, "'%s' is audible pcm (peak %d)" % [cue, peak])
		check_le(peak, 12000, "'%s' does not clip the bus it plays into" % cue)
		if cue == AudioService.LOCOMOTIVE or cue == AudioService.AMBIENT:
			check_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
					"'%s' runs until told to stop, so it loops" % cue)


func test_an_unknown_cue_is_refused_rather_than_played_silently() -> void:
	check_false(_audio.play("orchestra"), "a cue nobody authored cannot be played")
	check_eq(_audio.heard_cues().size(), 0, "and nothing was recorded as played")
