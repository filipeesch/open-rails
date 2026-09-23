class_name SoundForge
extends RefCounted

## V1's sound bank, written as arithmetic.
##
## Six cues are all the specification asks for (§"minimal spatial audio"): a UI
## click, a construction strike, a locomotive running, a whistle, an arrival and
## an ambient loop.  Buying or checking in six samples for that would add an
## asset pipeline, a licence question per file, and a binary blob nobody can
## review — while Blender, the project's only offline compiler, compiles meshes
## and not sound.  So each cue is synthesised at load from the parameters below:
## the sound is *data in code*, reviewable, reproducible, and identical on every
## machine.  Nothing here reaches a file, and nothing is sampled from anywhere.
##
## Layer vocabulary: each layer adds into a shared float buffer — a `sine` (with
## an optional glide to `freq_end`), or `noise` (one-pole filtered white noise,
## which is how wind, hiss and a brake squeal are all made).  `decay` is an
## exponential per layer length, `pulses` amplitude-modulates it that many times
## across the layer — which is a chuffle — and `at` places it in seconds.
##
## The random numbers are seeded, per layer.  These cues are presentation and
## outside the simulation, but an unseeded draw would still mean a player's
## valley sounds subtly different after each restart for no reason at all.

const SAMPLE_RATE := 22050
## Peaks land here rather than at full scale: headroom for a locomotive running
## under an ambient loop without clipping the master bus.
const PEAK := 12000.0

const CLICK := "ui_click"
const CONSTRUCTION := "construction"
const LOCOMOTIVE := "locomotive"
const WHISTLE := "whistle"
const ARRIVAL := "arrival"
const AMBIENT := "ambient"


## The one click a UI action makes: a tick, not a fanfare.
static func click() -> AudioStreamWAV:
	var sample := _buffer(0.05)
	_add_sine(sample, {"freq": 1500.0, "seconds": 0.05, "gain": 0.34, "decay": 26.0})
	_add_noise(sample, {"seconds": 0.05, "gain": 0.5, "decay": 30.0, "lp": 0.35, "seed": 11})
	return _wav(sample, false)


## Track laid or a yard raised: a low seating thud, a strike on top, and the ring
## of something metal that just took a hit.
static func construction() -> AudioStreamWAV:
	var sample := _buffer(0.38)
	_add_sine(sample, {"freq": 170.0, "freq_end": 70.0, "seconds": 0.2, "gain": 0.62, "decay": 6.0})
	_add_noise(sample, {"seconds": 0.09, "gain": 0.5, "decay": 14.0, "lp": 0.6, "seed": 23})
	_add_sine(sample, {"at": 0.02, "freq": 1180.0, "seconds": 0.34, "gain": 0.16, "decay": 7.0})
	_add_sine(sample, {"at": 0.02, "freq": 1770.0, "seconds": 0.3, "gain": 0.08, "decay": 9.0})
	return _wav(sample, false)


## A 4-4-0 running: one second of chuffle cycle, looped, so `pitch_scale` is what
## changes its speed at runtime.  Three chuffs per revolution of the drivers, the
## way the era sounds.
static func locomotive() -> AudioStreamWAV:
	var sample := _buffer(1.0)
	_add_noise(sample, {"seconds": 1.0, "gain": 0.3, "decay": 0.0, "lp": 0.22, "pulses": 3.0,
			"pulse_sharpness": 2.4, "seed": 41})
	_add_sine(sample, {"freq": 82.0, "seconds": 1.0, "gain": 0.3, "decay": 0.0,
			"pulses": 3.0, "pulse_sharpness": 3.0})
	_add_sine(sample, {"freq": 246.0, "seconds": 1.0, "gain": 0.09, "decay": 0.0,
			"pulses": 3.0, "pulse_sharpness": 4.0})
	return _wav(sample, true)


## The whistle the valley hears before it sees the train: a two-note steam
## chord, a breath under it, and a slow fade rather than a cut.
static func whistle() -> AudioStreamWAV:
	var sample := _buffer(1.6)
	_add_sine(sample, {"at": 0.05, "freq": 660.0, "seconds": 1.5, "gain": 0.3,
			"attack": 0.07, "decay": 1.3})
	_add_sine(sample, {"at": 0.05, "freq": 880.0, "seconds": 1.5, "gain": 0.2,
			"attack": 0.09, "decay": 1.3})
	_add_sine(sample, {"at": 0.05, "freq": 1320.0, "seconds": 1.4, "gain": 0.06, "decay": 2.0})
	_add_noise(sample, {"seconds": 1.6, "gain": 0.07, "decay": 0.8, "lp": 0.5, "seed": 67})
	return _wav(sample, false)


## Brakes and a bell: the squeal slides up as the wheels slow, and the bell
## speaks once the noise has gone.
static func arrival() -> AudioStreamWAV:
	var sample := _buffer(1.1)
	_add_noise(sample, {"seconds": 0.85, "gain": 0.28, "decay": 2.2, "lp": 0.9, "seed": 89})
	_add_sine(sample, {"freq": 780.0, "freq_end": 1520.0, "seconds": 0.8, "gain": 0.14,
			"decay": 2.6, "vibrato": 14.0, "vibrato_depth": 0.02})
	_add_sine(sample, {"at": 0.6, "freq": 523.0, "seconds": 0.5, "gain": 0.22, "decay": 4.5})
	_add_sine(sample, {"at": 0.6, "freq": 1570.0, "seconds": 0.42, "gain": 0.07, "decay": 6.5})
	return _wav(sample, false)


## The valley with nothing in it: wind under the trees and a bird now and then.
## Looping, with the swell on a period that divides the length so the seam does
## not click, and the birds kept clear of the join.
static func ambient() -> AudioStreamWAV:
	var seconds := 6.0
	var sample := _buffer(seconds)
	_add_noise(sample, {"seconds": seconds, "gain": 0.42, "decay": 0.0, "lp": 0.07,
			"pulses": 3.0, "pulse_sharpness": 1.0, "seed": 101})
	_add_noise(sample, {"seconds": seconds, "gain": 0.16, "decay": 0.0, "lp": 0.4,
			"pulses": 6.0, "pulse_sharpness": 1.0, "seed": 103})
	for chirp in 5:
		var at := 0.4 + float(chirp) * 1.1
		var note := 2300.0 + float(chirp * 7 % 11) * 90.0
		_add_sine(sample, {"at": at, "freq": note, "freq_end": note * 1.35, "seconds": 0.09,
				"gain": 0.3, "attack": 0.015, "decay": 6.0})
		_add_sine(sample, {"at": at + 0.13, "freq": note * 0.86, "seconds": 0.07,
				"gain": 0.2, "attack": 0.015, "decay": 7.0})
	return _wav(sample, true)


## Every cue, by id — the bank the audio service walks at startup.
static func bank() -> Dictionary:
	return {
		CLICK: click(),
		CONSTRUCTION: construction(),
		LOCOMOTIVE: locomotive(),
		WHISTLE: whistle(),
		ARRIVAL: arrival(),
		AMBIENT: ambient(),
	}


# --- the synthesis --------------------------------------------------------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var sample := PackedFloat32Array()
	sample.resize(int(seconds * float(SAMPLE_RATE)))
	return sample


static func _add_sine(sample: PackedFloat32Array, layer: Dictionary) -> void:
	_tone(sample, layer, false)


static func _add_noise(sample: PackedFloat32Array, layer: Dictionary) -> void:
	_tone(sample, layer, true)


static func _tone(sample: PackedFloat32Array, layer: Dictionary, is_noise: bool) -> void:
	var start := int(float(layer.get("at", 0.0)) * float(SAMPLE_RATE))
	var span := int(float(layer.get("seconds", 0.0)) * float(SAMPLE_RATE))
	if span <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layer.get("seed", 17))
	var filter_state := 0.0
	var filter_mix := float(layer.get("lp", 1.0))
	var gain := float(layer.get("gain", 1.0))
	var decay := float(layer.get("decay", 0.0))
	var attack := float(layer.get("attack", 0.0)) * float(SAMPLE_RATE)
	var pulses := float(layer.get("pulses", 0.0))
	var sharpness := float(layer.get("pulse_sharpness", 2.0))
	var frequency := float(layer.get("freq", 220.0))
	var frequency_end := float(layer.get("freq_end", frequency))
	var vibrato := float(layer.get("vibrato", 0.0))
	var vibrato_depth := float(layer.get("vibrato_depth", 0.0))
	var phase := 0.0
	for index in span:
		var position := float(index) / float(span)
		var envelope := exp(-decay * position)
		if attack > 0.0 and float(index) < attack:
			envelope *= float(index) / attack
		if pulses > 0.0:
			# A chuffle is a pressure pulse per driver revolution: raised to a
			# power so the cycle has a knock in it instead of a hum.
			var pulse := sin(PI * position * pulses)
			envelope *= pow(maxf(0.0, pulse), sharpness)
		var value := 0.0
		if is_noise:
			var white := rng.randf() * 2.0 - 1.0
			filter_state += (white - filter_state) * filter_mix
			value = filter_state
		else:
			var glide := frequency + (frequency_end - frequency) * position
			if vibrato > 0.0:
				glide *= 1.0 + vibrato_depth * sin(TAU * vibrato * position * float(span)
						/ float(SAMPLE_RATE))
			phase += TAU * glide / float(SAMPLE_RATE)
			value = sin(phase)
		var target := start + index
		if target >= 0 and target < sample.size():
			sample[target] += value * envelope * gain


static func _wav(sample: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = SAMPLE_RATE
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(sample.size() * 2)
	for index in sample.size():
		var clipped := clampf(sample[index], -1.0, 1.0)
		data.encode_s16(index * 2, int(round(clipped * PEAK)))
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample.size()
	return stream
