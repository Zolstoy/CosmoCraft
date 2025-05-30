extends Node



@onready var core = get_tree().get_first_node_in_group("core")

var state = State.Server.NOT_RUNNING
var process = null
var regex = RegEx.new()
var mutex: Mutex = Mutex.new()
var port = 0
var server_logs_out_thread: Thread
var server_logs_err_thread: Thread
var server_url: String = ""
var stop_timer = 0

func wait_logs_threads():
	if state != State.Server.NOT_RUNNING:
		print("Waiting threads")
		server_logs_err_thread.wait_to_finish()
		server_logs_out_thread.wait_to_finish()

func _ready():
	regex.compile("^.*Server loop starts, listenning on (\\d+)$")
	set_process(false)

func _process(delta):
	if state == State.Server.WAITING_PORT:
		mutex.lock()
		var locked_port = port
		mutex.unlock()

		if !locked_port:
			return

		server_url += ":%d" % locked_port

		if OS.has_feature("release"):
			wait_logs_threads()
		state = State.Server.RUNNING
		core.network.connect_to_server("localhost", locked_port, false)

	if core.state == State.Core.STOPPING_GAME || core.state == State.Core.QUITTING:
		stop_timer += delta;

		if !OS.is_process_running(process["pid"]):
			if core.state == State.Core.QUITTING:
				core.quit_now();
			else:
				process = Dictionary()
				state = State.Server.NOT_RUNNING
				stop_timer = 0
				return

		if stop_timer < 3:
			return ;

		stop_timer = 0

		print("Killing server!")
		OS.kill(process["pid"])
		state = State.Server.NOT_RUNNING

		if core.state == State.Core.QUITTING:
			core.quit_now()

		process = Dictionary()
		return

	if state == State.Server.RUNNING:
		if !process.is_empty() && !OS.is_process_running(process["pid"]):
			state = State.Server.NOT_RUNNING
			#refresh(State.WELCOME, _state)
			server_logs_err_thread.wait_to_finish()
			server_logs_out_thread.wait_to_finish()

func _server_logs(key):
	var pipe = process[key] as FileAccess
	var line_empty_cnt = 0

	while state == State.Server.RUNNING || state == State.Server.WAITING_PORT:
		var line = pipe.get_line()
		if pipe.eof_reached():
			break

		if line.is_empty():
			line_empty_cnt += 1
			if line_empty_cnt == 10:
				print("Got %d empty lines, reader thread (%s) quitting now..." % [line_empty_cnt, key])
				break

		if key == "stderr":
			var search_result = regex.search(line)
			if search_result:
				var port_str = search_result.get_string(1)
				assert(!port_str.is_empty())
				print("Found port: %s" % port_str)
				mutex.lock()
				port = int(port_str)
				mutex.unlock()
				if OS.has_feature("release"):
					break
		if !line.is_empty():
			print("> %s" % line)

	print("Server log (%s) thread quitting now!" % key)


func launch(world_name):
	if !OS.has_feature("release"):
		var server_path = ProjectSettings.globalize_path("res://server")
		var instance_path = ProjectSettings.globalize_path("user://%s.db" % world_name)

		var args = ["0",
			"--instance", instance_path, "--trace-level", "INFO"]
		process = OS.execute_with_pipe(server_path, args)
	else:
		var args = ["0", "--instance", ProjectSettings.globalize_path("user://%s.db" % world_name), "--trace-level", "INFO"]
		process = OS.execute_with_pipe("./spacebuild-server", args)

	if process.is_empty():
		printerr("Failed to run server")
		core.ui.error_placeholder.set_text("Local server not found or could not be executed")
		core.ui.play_button.set_disabled(false)
		return

	port = 0
	if server_logs_err_thread && server_logs_err_thread.is_started():
		server_logs_err_thread.wait_to_finish()
	server_logs_err_thread = Thread.new()
	server_logs_err_thread.start(_server_logs.bind("stderr"))
	if server_logs_out_thread && server_logs_out_thread.is_started():
		server_logs_out_thread.wait_to_finish()
	server_logs_out_thread = Thread.new()
	server_logs_out_thread.start(_server_logs.bind("stdio"))

	state = State.Server.WAITING_PORT
	set_process(true)

func stop_server():
	print("Stopping server gracefully...")
	(process["stdio"] as FileAccess).store_line("stop")
	(process["stdio"] as FileAccess).flush()
	core.state = State.Core.STOPPING_GAME
	#set_process(false)
