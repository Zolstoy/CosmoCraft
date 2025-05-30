extends Node


var login_hash = {
	"Login": {
		"nickname": ""
	}
}

@onready var core = get_tree().get_first_node_in_group("core")


var state = State.Network.IDLE
var socket: WebSocketPeer = null
# var close_timer: float = 0
var bodies = []
var timer = 0
var body_ref_id = 0

func _ready():
	set_process(false)

func _process(delta):
	var new_network_state = null
	var new_state = null
	socket.poll()

	var socket_state = socket.get_ready_state()

	if socket_state == WebSocketPeer.STATE_CLOSED:
		socket = WebSocketPeer.new()
		new_network_state = State.Network.IDLE
		set_process(false)

	if socket_state == WebSocketPeer.STATE_OPEN:
		timer += delta;
		if state == State.Network.CONNECTING:
			print("Authenticating...")
			if core.ui.state == State.UI.MODAL_ONLINE:
				login_hash["Login"]["nickname"] = core.ui.login_field.get_text()
			else:
				login_hash["Login"]["nickname"] = "Player"
			if socket.send_text(JSON.stringify(login_hash)) != OK:
				print("Send error")
			else:
				new_network_state = State.Network.AUTHENTICATING

		elif state == State.Network.AUTHENTICATING:
			if socket.get_available_packet_count():
				var variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())

				if variant["success"] == false:
					print("Login failure: %s" % variant["message"])
					core.ui.error_placeholder.set_text("Authentication failed: %s" % variant["message"])
					core.leave()
				else:
					print("Login success, id is %s" % variant["message"])
					core.spawner.set_process(true)
					core.player.set_process(true)
					core.player.set_process_input(true)
					core.ui.connecting.visible = false
					core.player.visible = true
					core.ui.title.visible = false
					new_network_state = State.Network.WAITING_GAMEINFO
					if core.server.state == State.Server.RUNNING:
						new_state = State.Core.PLAYING_SOLO
					else:
						new_state = State.Core.PLAYING_ONLINE
		elif state == State.Network.WAITING_GAMEINFO:
			if timer > 2:
				timer = 0
				var keys = core.spawner.cache.keys()
				if keys.size() > 0:
					if body_ref_id == 0 || keys.count(body_ref_id) == 0:
						body_ref_id = keys.back()
					var msg = {
						"Ping" = [body_ref_id, core.spawner.cache[body_ref_id].current_rotation]
					}
					socket.send_text(JSON.stringify(msg))
			while socket.get_available_packet_count():
				var variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
				if variant.has("Player"):
					var coords = variant["Player"]["coords"]
					core.player.position = Vector3(coords[0], coords[1], coords[2])
				elif variant.has("Pong"):
					print(variant)
				elif variant.has("Env"):
					var elements = variant["Env"] as Array
					for element in elements:
						var id = int(element["id"])
						assert(id > 0)
						#var body_node = core.spawner.get_node_or_null(str(id))
						#var body_node = core.spawner.find_child(str(id), true, false)
						var new_coords = Vector3(element["coords"][0], element["coords"][1], element["coords"][2])
						if core.spawner.cache.has(id):
							var body_node = core.spawner.cache[id]
							body_node.global_position = Vector3(element["coords"][0], element["coords"][1], element["coords"][2])
						elif !core.spawner.to_instantiate.has(id):
							core.spawner.to_instantiate[id] = {
								"type": element["body_type"],
								"coords": new_coords,
								"rotating_speed": element["rotating_speed"],
								"gravity_center_id": int(element["gravity_center"])
							}
						else:
							core.spawner.to_instantiate[id].coords = new_coords
	if new_network_state:
		state = new_network_state
	if new_state:
		core.state = new_state

func connect_to_server(host: String, port: int, secure: bool):
	socket = WebSocketPeer.new()

	var url: String
	if secure:
		url = "wss://"
	else:
		url = "ws://"
	url += "%s:%s" % [host, port]

	if socket.connect_to_url(url, null) != OK:
		printerr("Could not connect")
		core.ui.error_placeholder.set_text("Could not connect")
		core.ui.play_button.set_disabled(false)
		return

	print("Connecting to %s" % url)
	core.ui.loading.visible = false
	core.ui.connecting.visible = true
	state = State.Network.CONNECTING
	set_process(true)
