extends Node3D

@onready var core = get_tree().get_first_node_in_group("core")
@onready var ship = get_tree().get_first_node_in_group("ship") as Node3D
@onready var reticle = get_tree().get_first_node_in_group("reticle")
@onready var point = get_tree().get_first_node_in_group("point")
@onready var f3_infos = get_tree().get_first_node_in_group("f3_infos")

var target_position = Vector2()
var timer = 0

func _ready():
	set_process(false)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		reticle.position = core.ui.screen_size / 2

		target_position = event.position / core.ui.screen_size
		target_position -= Vector2.ONE * 0.5

		point.position = target_position * 400

func _process(delta: float) -> void:
	timer += delta
	if Input.is_key_pressed(KEY_F3):
		f3_infos.set_text("%s" % position)
		f3_infos.set_visible(true)
	else:
		f3_infos.set_visible(false)

	if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) && !Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		reticle.set_visible(false)
	else:
		reticle.set_visible(true)

		var action = Dictionary()
		action["ShipState"] = Dictionary()
		action["ShipState"]["throttle_up"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		action["ShipState"]["direction"] = [0, 0, 0]

		var direction = (Vector3(target_position.x, target_position.y, 0) + Vector3.FORWARD * 10);

		var target = Node3D.new()
		add_child(target)
		target.position = Vector3.ZERO

		target.translate_object_local(direction)

		var vec = target.global_position - position

		look_at(target.global_position, vec.cross(-basis.x))

		action["ShipState"]["direction"][0] = - vec.x
		action["ShipState"]["direction"][1] = - vec.y
		action["ShipState"]["direction"][2] = - vec.z

		remove_child(target)

		ship.rotation = Vector3.ZERO
		var clamp_val = 0.7
		var turn_factor = 2
		ship.rotate(Vector3.RIGHT, clampf(target_position.y, -clamp_val / 2, clamp_val / 2))
		ship.rotate(Vector3.DOWN, clampf(target_position.x, -clamp_val, clamp_val))
		ship.rotate(Vector3.BACK, clampf(target_position.x * turn_factor,
			- clamp_val * turn_factor, clamp_val * turn_factor))

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			translate(-vec.normalized() * 10 * delta)
		#if timer > 0.25:
			#timer = 0
		if core.network.socket.send_text(JSON.stringify(action)) != OK:
			print("Send error")
