class_name AudioService
extends Node

## The valley's six sounds, where they come from, and what they are allowed to
## cost.
##
## Spec §"minimal spatial audio" names six cues and asks that volume settings
## apply to them.  Three decisions carry the design:
##
## *The sounds are synthesised, not sampled* — see `SoundForge`.  Six cues do not
## justify an audio asset pipeline, and a generated stream has no licence, no
## import step and no binary in the repository.
##
## *World sounds are placed, interface sounds are not.*  A locomotive belongs at
## the track, so its player is an `AudioStreamPlayer3D` with a real position and
## a bounded hearing radius; a click belongs to the screen.  Distance falloff is
## the engine's, from the camera rig's ear, which is why the service takes an
## `ear` position rather than a camera reference — the simulation side never
## learns that a renderer exists.
##
## *Locomotives are pooled.*  Nothing in §112 is more important than not
## creating a node per thing, and a hundred trains is a hundred potential audio
## sources.  So `LOCOMOTIVE_VOICES` players exist, always, and each tick they are
## handed to the nearest trains within earshot.  The hundred-and-first train is
## silent, and that is the correct behaviour rather than a limitation: it is what
## standing in one place in a valley sounds like.
##
## The volume settings apply through the buses, not per player: everything here
## plays into Effects or Music, and `SettingsService` already owns those buses'
## levels and their send to Master.  A cue therefore cannot be loud while the
## player has turned the effects dial down, which is the promise §114 makes.

const SoundForgeScript := preload("res://src/infrastructure/audio/sound_forge.gd")

## Interface sounds, placed in the world.
const CLICK := "ui_click"
const CONSTRUCTION := "construction"
const LOCOMOTIVE := "locomotive"
const WHISTLE := "whistle"
const ARRIVAL := "arrival"
const AMBIENT := "ambient"

## How many trains can be heard at once, and how far away a train can be and
## still be heard.  Both are budgets, and both are what a valley sounds like.
const LOCOMOTIVE_VOICES := 4
const HEARING_DISTANCE := 46.0
## The run that puts a chuff at the top of its dial, in km/h — the same unit the
## inspector quotes, so the knock and the number agree.  A pooled voice is pitched
## by how fast the consist it was handed is really going, and a bare divisor here
## is how an audio cue quietly stops matching the speed scale.
const CHUFF_TOP_KMH := 78.0
## The cue log a test reads: bounded, because a service that remembers every
## sound it ever made is a memory leak with a nice name.
const HEARD_LOG := 64

## The bank: which bus a cue belongs to, whether it is placed, and the level it
## plays at before its bus is applied.
const CUES: Array[Dictionary] = [
	{"id": CLICK, "label": "Interface click", "bus": "Effects", "spatial": false, "volume_db": -2.0},
	{"id": CONSTRUCTION, "label": "Construction", "bus": "Effects", "spatial": true, "volume_db": -1.0},
	{"id": LOCOMOTIVE, "label": "Locomotive running", "bus": "Effects", "spatial": true, "volume_db": -8.0},
	{"id": WHISTLE, "label": "Whistle", "bus": "Effects", "spatial": true, "volume_db": -4.0},
	{"id": ARRIVAL, "label": "Arrival", "bus": "Effects", "spatial": true, "volume_db": -5.0},
	# The ambience is a bed, not a place: it is the valley being there, so it is
	# not positioned and it rides the Music bus, which the settings screen owns.
	{"id": AMBIENT, "label": "Ambient valley", "bus": "Music", "spatial": false, "volume_db": -14.0},
]

signal cue_played(cue: String, world_position: Vector3)
signal voices_changed(train_ids: Array[int])

var session: GameSession
## The camera's position, pulled rather than pushed: the service asks for the ear
## when it needs it, so nothing has to remember to tell it.
var ear_provider: Callable = Callable()
## Whether a cue may start.  Off is for a player who muted the game in the
## settings, and for a stress run that has no business mixing audio.
var enabled := true

var _streams := {}
var _players := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_trains: Array[int] = []
var _ambience: AudioStreamPlayer
var _heard: Array[Dictionary] = []
var _settings: SettingsService = null


## Build the bank and its players.  `settings_service` is optional: without it
## the cues play into whatever buses exist.
func configure(settings_service: SettingsService = null) -> void:
	_settings = settings_service
	if _settings != null:
		_settings.ensure_audio_buses()
	_streams = SoundForgeScript.bank()
	for entry in CUES:
		var cue := String(entry["id"])
		var player = _make_player(bool(entry["spatial"]), String(entry["bus"]),
				float(entry["volume_db"]))
		player.stream = _streams[cue]
		_players[cue] = player
		add_child(player)
	_ambience = _players[AMBIENT]
	for voice in LOCOMOTIVE_VOICES:
		var runner := AudioStreamPlayer3D.new()
		runner.name = "LocomotiveVoice%d" % voice
		runner.bus = String(CUES[2]["bus"])
		runner.volume_db = float(CUES[2]["volume_db"])
		runner.max_distance = HEARING_DISTANCE
		runner.stream = _streams[LOCOMOTIVE]
		add_child(runner)
		_voices.append(runner)
		_voice_trains.append(0)


## A `2D` player is a `Node` and a `3D` one is a `Node3D` — siblings, not parent
## and child — so the factory hands back the shared base and a caller that needs
## a placed cue branches on which one it got.
func _make_player(spatial: bool, bus: String, volume_db: float) -> Node:
	var player: Node
	if spatial:
		var placed := AudioStreamPlayer3D.new()
		placed.max_distance = HEARING_DISTANCE
		player = placed
	else:
		player = AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = volume_db
	return player


## Listen to the game's own events.  Every cue below is caused by something
## happening in the valley, not by a UI widget noticing it looked good.
func attach_session(game_session: GameSession) -> void:
	session = game_session
	session.train_departed.connect(_on_departed)
	session.train_arrived.connect(_on_arrived)
	session.station_created.connect(_on_station)
	session.rail.track_changed.connect(_on_track)


## Start a cue.  Returns whether it was asked to play at all, which is the
## decision a test can see: an orphan player records the request and stays
## silent, exactly as it does in a game whose window was never opened.
func play(cue: String, world_position := Vector3.INF) -> bool:
	if not enabled:
		return false
	if not _players.has(cue):
		push_warning("audio: no cue named '%s'" % cue)
		return false
	var player = _players[cue]
	if player == null:
		return false
	var placed := player is AudioStreamPlayer3D
	var at := world_position if placed else Vector3.INF
	if placed and at == Vector3.INF:
		at = _ear()
	if placed:
		# The same tree rule as below: with no tree there is no global frame to
		# write, and the engine answers with an error per cue.  Local position is
		# the identical answer once the host is in a tree, and the honest one
		# while it is not.
		if player.is_inside_tree():
			player.global_position = at
		else:
			player.position = at
	# A player that is not in a tree cannot mix, and Godot says so loudly.  The
	# request is still recorded, because what a test grades is the decision.
	if player.is_inside_tree():
		player.play()
	_heard.append({"cue": cue, "at": at, "bus": player.bus, "position": at})
	if _heard.size() > HEARD_LOG:
		_heard.pop_front()
	cue_played.emit(cue, at)
	return true


## The synthesised stream behind a cue — the sound itself, for anything that has
## to know what a cue actually is rather than when it fired.
func stream_for(cue: String) -> AudioStreamWAV:
	return _streams.get(cue) as AudioStreamWAV


func stop(cue: String) -> void:
	if _players.has(cue):
		var player = _players[cue]
		player.stop()


func stop_all() -> void:
	for cue in _players.keys():
		var player = _players[cue]
		player.stop()
	for voice in _voices:
		voice.stop()


## The one-shot sounds the valley makes for itself.
func ui_click() -> bool:
	return play(CLICK)


func is_heard(cue: String) -> bool:
	return heard_for(cue) > 0


func heard_for(cue: String) -> int:
	var count := 0
	for entry in _heard:
		if String(entry["cue"]) == cue:
			count += 1
	return count


## The log itself, oldest first.
func heard_cues() -> Array[Dictionary]:
	return _heard.duplicate(true)


# --- what the valley sounds like ------------------------------------------

func _on_departed(train_id: int, _station_id: int) -> void:
	play(WHISTLE, _train_position(train_id))
	play(LOCOMOTIVE, _train_position(train_id))


func _on_arrived(train_id: int, _station_id: int) -> void:
	play(ARRIVAL, _train_position(train_id))


func _on_station(station_id: int) -> void:
	if session == null:
		return
	var tile: Vector2i = session.stations.tile_of(station_id)
	play(CONSTRUCTION, Vector3(float(tile.x) + 0.5, 0.0, float(tile.y) + 0.5))


func _on_track(tiles: Array[Vector2i]) -> void:
	if tiles.is_empty():
		return
	var first: Vector2i = tiles[tiles.size() - 1]
	play(CONSTRUCTION, Vector3(float(first.x) + 0.5, 0.0, float(first.y) + 0.5))


## Re-decide who is loud enough to hear.  Called once per frame by the root, with
## no work at all when nothing moved: the nearest four of the trains in earshot,
## pitched by how fast each is actually going.
func assign_locomotive_voices() -> void:
	if session == null or _voices.is_empty():
		return
	var ear := _ear()
	var candidates: Array[Dictionary] = []
	for train_id in session.trains.trains():
		var at := _train_position(train_id)
		var distance := ear.distance_to(at)
		if distance > HEARING_DISTANCE:
			continue
		if session.trains.state_of(train_id) == TrainService.State.IDLE:
			continue
		candidates.append({"id": train_id, "distance": distance, "at": at,
				"speed": session.trains.speed_kmh(train_id)})
	candidates.sort_custom(_nearer_first)
	var assigned: Array[int] = []
	for voice in _voices.size():
		var player := _voices[voice]
		if voice >= candidates.size():
			if player.playing:
				player.stop()
			_voice_trains[voice] = 0
			continue
		var pick: Dictionary = candidates[voice]
		var train_id := int(pick["id"])
		var at: Vector3 = pick["at"] as Vector3
		# The placed position is the whole point of a 3D player, but a service
		# staged outside a scene tree — a headless test, a session built before
		# its host is added — has no global frame to write into, and asking for
		# one logs an engine error per voice per frame.  Local is the right
		# answer there and the identical answer once the host is in the tree.
		if player.is_inside_tree():
			player.global_position = at
		else:
			player.position = at
		# A stationary consist is not chuffing; a crawling one knocks slowly.
		player.pitch_scale = clampf(0.55 + float(pick["speed"]) / CHUFF_TOP_KMH * 0.9, 0.45, 1.9)
		if not player.playing and player.is_inside_tree():
			player.play()
		_voice_trains[voice] = train_id
		assigned.append(train_id)
	voices_changed.emit(assigned)


## Which trains the pool is currently voicing, nearest first.
func audible_trains() -> Array[int]:
	var out: Array[int] = []
	for train_id in _voice_trains:
		if train_id != 0:
			out.append(train_id)
	return out


func voice_count() -> int:
	return _voices.size()


## Start the bed.  Deliberately not automatic: a player who has not asked to hear
## the valley yet should not hear it on the menu.
func start_ambience() -> void:
	if _ambience == null or not enabled:
		return
	if _ambience.is_inside_tree():
		_ambience.play()


func stop_ambience() -> void:
	if _ambience != null:
		_ambience.stop()


func _nearer_first(a: Dictionary, b: Dictionary) -> bool:
	return float(a["distance"]) < float(b["distance"])


func _train_position(train_id: int) -> Vector3:
	if session == null:
		return Vector3.ZERO
	var tile: Vector2 = session.trains.position_tiles(train_id)
	return Vector3(tile.x, 0.0, tile.y)


func _ear() -> Vector3:
	if ear_provider.is_valid():
		return ear_provider.call() as Vector3
	return Vector3.ZERO
