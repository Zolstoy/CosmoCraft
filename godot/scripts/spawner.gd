extends Node3D

@onready var body_scene: PackedScene = load("res://scenes/body.tscn")
@onready var star_light_scene: PackedScene = load("res://scenes/star_light.tscn")

@onready var core = get_tree().get_first_node_in_group("core")
@onready var info = get_tree().get_first_node_in_group("info")

var to_instantiate: Dictionary = {}
var timer: float = 0
var cache: Dictionary = {}

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	timer += delta
	info.set_visible(!to_instantiate.is_empty())

	if timer > 1:
		for id in to_instantiate:
			var body_info = to_instantiate[id]
			var body_tree = get_colored_body_node(body_info.type, body_info.coords)
			body_tree.position = body_info.coords
			body_tree.set_name(str(id))
			body_tree.rotating_speed = body_info.rotating_speed
			if body_info.type == "1":
				(body_tree.get_child(0).material as StandardMaterial3D).shading_mode\
					= BaseMaterial3D.SHADING_MODE_UNSHADED
				body_tree.set_process(false)
			else:
				body_tree.gravity_center_id = body_info.gravity_center_id
			cache[id] = body_tree
			add_child(body_tree)
		to_instantiate.clear()
		timer = 0

func stop():
	for node in get_children():
		remove_child(node);
	to_instantiate.clear()
	timer = 0
	set_process(false)

func get_colored_body_node(type: String, coords: Vector3) -> Node:
	var color: Color
	var body_tree: Node3D = body_scene.instantiate()
	var model = body_tree.get_child(0)

	if type == "1":
		model.scale *= 100
		var star_light_tree: Node3D = star_light_scene.instantiate()
		star_light_tree.position = coords
		add_child(star_light_tree)
		color = Color(1, 1, 1)
	elif type == "2":
		model.scale *= 10
		color = Color(0, 0, 1)
	elif type == "3":
		model.scale *= 2
		color = Color(0, 1, 1)
	elif type == "4":
		model.scale *= 0.5
		color = Color(1, 0, 0)
	else:
		assert(false)

	(model.material as StandardMaterial3D).albedo_color = color
	return body_tree
