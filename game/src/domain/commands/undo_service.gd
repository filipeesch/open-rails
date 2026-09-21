class_name UndoService
extends RefCounted

## A bounded stack of reversible construction actions.
##
## Reversal is real, not cosmetic: a command re-applies the world change *and*
## the matching ledger reversal, so undo cannot leave money or track stranded.
## Anything that has become semantically unsafe to reverse (the track was
## reused, the station is now load-bearing) is dropped from the stack rather
## than half-undone.

signal action_committed(label: String)
signal action_undone(label: String)
signal action_expired(label: String)
signal undo_state_changed(can_undo: bool, depth: int)

const DEFAULT_DEPTH := 40

var _stack: Array[Dictionary] = []
var _depth := DEFAULT_DEPTH


func configure_depth(depth: int) -> void:
	_depth = maxi(1, depth)


func can_undo() -> bool:
	return not _stack.is_empty()


func depth() -> int:
	return _stack.size()


func next_label() -> String:
	return String(_stack[_stack.size() - 1].get("label", "")) if not _stack.is_empty() else ""


func labels() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _stack:
		out.append(String(entry["label"]))
	return out


## Record an action that has already been performed, together with the callable
## that reverses it and (optionally) one that says whether reversal is still
## safe.  Undo depth is bounded: the oldest entry simply ages out.
func record(label: String, revert: Callable, is_safe: Callable = Callable()) -> bool:
	if not revert.is_valid():
		return false
	_stack.append({"label": label, "revert": revert, "safe": is_safe})
	while _stack.size() > _depth:
		var expired: Dictionary = _stack.pop_front()
		action_expired.emit(String(expired["label"]))
	action_committed.emit(label)
	_state()
	return true


func undo() -> String:
	if _stack.is_empty():
		return ""
	var entry: Dictionary = _stack[_stack.size() - 1]
	var is_safe: Callable = entry["safe"]
	if is_safe.is_valid() and not bool(is_safe.call()):
		var blocked := String(entry["label"])
		_stack.pop_back()
		action_expired.emit(blocked)
		_state()
		return ""
	_stack.pop_back()
	entry["revert"].call()
	var label := String(entry["label"])
	action_undone.emit(label)
	_state()
	return label


func clear() -> void:
	_stack.clear()
	_state()


func _state() -> void:
	undo_state_changed.emit(not _stack.is_empty(), _stack.size())
