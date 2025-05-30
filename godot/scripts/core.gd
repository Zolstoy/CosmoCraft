extends Node

@onready var server = get_tree().get_first_node_in_group("server")
@onready var container = get_tree().get_first_node_in_group("container") as Node3D
@onready var network = get_tree().get_first_node_in_group("network")
@onready var player = get_tree().get_first_node_in_group("player")
@onready var ui = get_tree().get_first_node_in_group("ui")
@onready var spawner: Node = get_tree().get_first_node_in_group("spawner")

var login = ""
var state: State.Core = State.Core.WELCOME
var server_process_state = State.Server.NOT_RUNNING
var close_timer = 0
var resync_timer = 0

func back_to_welcome():
	player.visible = false
	player.set_process(false)
	spawner.stop()
	ui.back_to_welcome()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)

func quit_now():
	server.wait_logs_threads()
	get_tree().quit()

func leave():
	if state != State.Core.PLAYING_SOLO && state != State.Core.PLAYING_ONLINE:
		return
	print("Leaving...")
	back_to_welcome()
	if state == State.Core.PLAYING_ONLINE:
		network.socket.close()
	elif state == State.Core.PLAYING_SOLO:
		network.socket.close()
		server.stop_server()

	state = State.Core.LEAVING


func quit() -> void:
	print("Quit called")
	if server.state == State.Server.RUNNING:
		server.stop_server()
		state = State.Core.QUITTING
	else:
		print("Server not running, quitting now!")
		quit_now()

func play_solo(play_mode) -> void:
	var _output = []
	var world_name = ""
	if play_mode == State.LaunchMode.CREATION:
		world_name = ui.world_field.get_text()
	elif play_mode == State.LaunchMode.JOIN:
		world_name = ui.worlds_tree.get_selected().get_text(0)

	assert(!world_name.is_empty())

	ui.modale.visible = false
	ui.loading.visible = true
	server.launch(world_name)

func play_online() -> void:
	login = ui.login_field.get_text()
	if login.is_empty():
		ui.error_placeholder.set_text("Enter your login please")
		print("No login")
		ui.play_button.set_disabled(false)
		return

	var host_str = ui.host_field.get_text()
	if host_str.is_empty():
		host_str = "localhost"

	var port_str = ui.port_field.get_text()
	if port_str.is_empty():
		port_str = "2567"

	ui.modale.visible = false
	network.connect_to_server(host_str, int(port_str), ui.encrypted_switch.is_pressed())
