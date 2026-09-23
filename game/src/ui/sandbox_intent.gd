class_name SandboxIntent
extends RefCounted

## What the New Sandbox screen decided, carried across the scene change.
##
## A scene swap destroys the screen that asked for it, and the new game boots in
## the frame it enters the tree — so the choice has to live somewhere neither of
## them owns.  This is that somewhere: two fields, written by the screen, read
## once by the arriving session and then wiped.  Wiping matters as much as
## writing: a stale intent replayed at the next launch would rename a company the
## player never named, which is exactly the kind of surprise a save game should
## never contain.

const DEFAULT_MAP := "founders_valley"
const DEFAULT_START_YEAR := 1850

static var map_id: String = DEFAULT_MAP
static var company_name: String = ""
## A saved valley to open instead of a new one.  The menu's Continue and its load
## rows carry it here for the same reason the map choice does: the scene that asked
## for the save is freed by the very hand-off that opens it.
static var save_path: String = ""
static var has_intent := false


static func write(p_map_id: String, p_company_name: String, p_save_path: String = "") -> void:
	map_id = p_map_id if p_map_id != "" else DEFAULT_MAP
	company_name = p_company_name.strip_edges()
	save_path = p_save_path
	has_intent = true


## "Continue" and a row from the load list: no map and no company are chosen,
## because the save names both.
static func write_resume(p_save_path: String) -> void:
	write(DEFAULT_MAP, "", p_save_path)


static func peek() -> Dictionary:
	return {
		"map": map_id,
		"company_name": company_name,
		"save_path": save_path,
		"pending": has_intent,
	}


## Read the choice and clear it, so the next launch starts from nothing.
static func consume() -> Dictionary:
	var request := peek()
	clear()
	return request


static func clear() -> void:
	map_id = DEFAULT_MAP
	company_name = ""
	save_path = ""
	has_intent = false
