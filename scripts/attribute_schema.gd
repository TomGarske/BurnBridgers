class_name AttributeDefinition
extends RefCounted

var name: String = ""
var category: String = ""
var cost_per_point: int = 1
var base_value: int = 0
var is_custom: bool = false
var description: String = ""


static func _make(p_name: String, p_category: String, p_cost: int, p_base: int,
		p_custom: bool = false, p_desc: String = "") -> AttributeDefinition:
	var a := AttributeDefinition.new()
	a.name = p_name
	a.category = p_category
	a.cost_per_point = p_cost
	a.base_value = p_base
	a.is_custom = p_custom
	a.description = p_desc
	return a


static func get_default_attributes() -> Array[AttributeDefinition]:
	var result: Array[AttributeDefinition] = []
	# Movement category
	result.append(_make("Land",                    "Movement", 1, 0))
	result.append(_make("Air",                     "Movement", 1, 0))
	result.append(_make("Water",                   "Movement", 1, 0))
	result.append(_make("Deep Ocean Underwater",   "Movement", 1, 0))
	# Combat category
	result.append(_make("Health",                  "Combat",   1, 0))
	result.append(_make("Attack",                  "Combat",   1, 0))
	result.append(_make("Defense",                 "Combat",   1, 0))
	# Special category
	result.append(_make("Vision",                  "Special",  1, 3))
	result.append(_make("Movement Speed",          "Special",  0, 1))
	return result
