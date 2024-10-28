extends MarginContainer

var object: Object

func _init(obj: Object, text:String):
	object = obj
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var button := Button.new()
	add_child(button)
	self.set("theme_override_constants/margin_left",5)
	self.set("theme_override_constants/margin_top",5)
	self.set("theme_override_constants/margin_right",5)
	self.set("theme_override_constants/margin_bottom",5)
	
	var emoji: String = ""
	
	match text:
		"Generate Terrain":
			emoji = "⛰️"
	
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.flat = false
	button.text = "%s %s" % [emoji, text]
	button.button_down.connect(object._on_tool_button_pressed.bind(text))
