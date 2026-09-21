class_name IdFactory
extends RefCounted

## Stable 64-bit identities for persistent entities.
##
## Ids are allocated by the active session and are written into saves verbatim.
## Nothing in the codebase persists a scene node path as an identity.

var _next: int = 1000


func reset(from_value: int = 1000) -> void:
	_next = from_value


func adopt_highest(used: int) -> void:
	if used >= _next:
		_next = used + 1


func next_id() -> int:
	var id := _next
	_next += 1
	return id


func peek() -> int:
	return _next
