@tool
extends Window

@onready var http_request_client: HTTPRequest = $HttpRequestClient
@onready var update_checker_timer: Timer = $UpdateCheckerTimer
@onready var header: Label = $Panel/GridContainer/PanelContainer/header
@onready var content: RichTextLabel = $Panel/GridContainer/PanelContainer2/ScrollContainer/MarginContainer/content

@onready var update_button: Button = $Panel/GridContainer/Panel/HBoxContainer/update
@onready var show_next_button: CheckBox = $Panel/GridContainer/Panel/HBoxContainer/show_next
@onready var close_button: Button = $Panel/GridContainer/Panel/HBoxContainer/close

const UpdateProgressBar: PackedScene = preload("update_progress_bar.tscn")

var debug_mode: = false
var current_version: MyPluginVersion = MyPluginVersion.current()
var download_zip_url: String
var available_latest_version: Dictionary = {}


func _notification(what :int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(http_request_client):
			http_request_client.queue_free()


func _enter_tree() -> void:
	hide()

	title = "%s Update Notification" % MyPluginSettings.PluginName
	mode = MODE_WINDOWED
	initial_position = WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	
	_prepare_update_interval_checker_timer()


func _ready() -> void:
	update_button.disabled = true
	show_next_button.button_pressed = MyPluginSettings.is_update_notification_enabled()
	header.text = ""
	content.clear()
	content.text = ""

	# wait 20s to allow the editor to initialize itself
	await get_tree().create_timer(20).timeout
	check_for_update()
	
	
func check_for_update() -> void:
	if is_instance_valid(http_request_client) and http_request_client.is_inside_tree() and MyPluginSettings.is_update_notification_enabled():
		var error: Error = http_request_client.request(MyPluginSettings.RemoteReleasesUrl)
		
		if error != OK:
			push_warning("An error %d happened, update information cannot be retrieved from GitHub!" % error)
			return


func latest_release_version(releases: Array, _current_version: MyPluginVersion = current_version) -> Dictionary:
	var versions = releases.filter(func(release: Dictionary): return MyPluginVersion.parse(release.tag_name).is_greater(_current_version))
	
	if versions.size() > 0:
		return versions.front()
	
	return {}


func _create_update_progress_bar() -> void:
	var update_progress_bar = UpdateProgressBar.instantiate()
	update_progress_bar.download_url = available_latest_version.zipball_url
	(Engine.get_main_loop() as SceneTree).root.add_child(update_progress_bar)
	update_progress_bar.popup_centered()
	update_progress_bar.canceled.connect(func(): update_button.disabled = false)
	update_progress_bar.update_finished.connect(func(): 
		EditorInterface.restart_editor(true)
		queue_free()
	)


func _prepare_update_interval_checker_timer():
	if update_checker_timer:
		update_checker_timer.process_callback = Timer.TIMER_PROCESS_IDLE
		update_checker_timer.autostart = true
		update_checker_timer.one_shot = false
		update_checker_timer.wait_time = (60 * 60 * 12) # Check for updates two times in a day
		
		if not update_checker_timer.timeout.is_connected(check_for_update):
			update_checker_timer.timeout.connect(check_for_update)


func on_close_button_pressed() -> void:
	hide()


func on_update_button_pressed() -> void:
	if available_latest_version is Dictionary:
		update_button.disabled = true
		ScriptEditorControls.close_open_editor_scripts()
		_create_update_progress_bar()


func on_show_next_button_toggled(enabled: bool) -> void:
	MyPluginSettings.set_update_notification(enabled)


func on_http_request_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("An http error %d happened, update information cannot be retrieved from GitHub!" % result)
		return
	
	var response = JSON.parse_string(body.get_string_from_utf8())

	if response and typeof(response) == TYPE_ARRAY:
		available_latest_version = latest_release_version(response as Array, current_version)
		
		if available_latest_version.size() > 0:
			update_button.disabled = false
			content.clear()
			content.text = ""
			content.append_text(available_latest_version.body)
			header.text = "A new version %s is available to update" % MyPluginVersion.parse(available_latest_version.tag_name)
			show()
