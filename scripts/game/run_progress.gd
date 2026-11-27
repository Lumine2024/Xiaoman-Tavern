extends RefCounted
## Cycle bookkeeping only. Effects and completion rules await the design document.
var cycle = 1
var highest_cycle = 1
var ability_grants: Array = []

func reset() -> void:
	cycle = 1
	highest_cycle = 1
	ability_grants.clear()

func advance() -> void:
	cycle += 1
	highest_cycle = maxi(highest_cycle, cycle)
	ability_grants.append({"cycle": cycle, "effect": {}})

func snapshot() -> Dictionary:
	return {"cycle": cycle, "highest_cycle": highest_cycle, "ability_grants": ability_grants.duplicate(true)}

func restore(value: Dictionary) -> void:
	cycle = int(value.cycle)
	highest_cycle = int(value.highest_cycle)
	ability_grants = value.ability_grants.duplicate(true)

func effects(_day: int, _rules: Dictionary) -> Dictionary:
	# TODO: implement ability/difficulty formulas only after planning defines them.
	return {"ability": {}, "cycle_difficulty": {}, "stage_difficulty": {}}
