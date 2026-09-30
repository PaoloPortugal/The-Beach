class_name MessageBubble
extends Sprite3D
## The small window above an orchestrator (C02): its latest message, plain
## text, always facing you. It's part of the world, so it gets smaller with
## distance and terrain hides it. Drawn into a SubViewport shown on this
## billboard sprite. While a reply streams, it shows the newest lines.

## Wrap width in characters and the most lines shown.
const WIDTH := 40
const MAX_LINES := 4

@onready var _viewport: SubViewport = $Viewport
@onready var _panel: PanelContainer = $Viewport/Panel
@onready var _label: Label = $Viewport/Panel/Label


func _ready() -> void:
	texture = _viewport.get_texture()
	visible = false


## What the bubble shows now (empty when hidden).
func shown_text() -> String:
	return _label.text if visible else ""


## Shows the end of [param text]; empty text hides the bubble.
func show_text(text: String) -> void:
	var shown := MessageBubble.tail_lines(text, WIDTH, MAX_LINES)
	visible = not shown.is_empty()
	_label.text = shown
	if not visible:
		return
	# Fit the viewport to the panel's new size.
	_panel.reset_size()
	_viewport.size = Vector2i(_panel.get_combined_minimum_size().ceil())
	# The bubble's bottom edge sits on the anchor, so it grows upwards.
	offset.y = _viewport.size.y / 2.0


## The text's last [param max_lines] lines, word-wrapped at [param width]
## characters, with "…" in front when anything was cut. Blank lines are
## dropped: the bubble is too small to spend lines on them.
static func tail_lines(text: String, width: int, max_lines: int) -> String:
	var lines: PackedStringArray = []
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.strip_edges().split(" ", false):
			# A word longer than a whole line is cut into pieces.
			while word.length() > width:
				if not line.is_empty():
					lines.append(line)
					line = ""
				lines.append(word.substr(0, width))
				word = word.substr(width)
			if line.is_empty():
				line = word
			elif line.length() + 1 + word.length() <= width:
				line += " " + word
			else:
				lines.append(line)
				line = word
		if not line.is_empty():
			lines.append(line)
	if lines.size() <= max_lines:
		return "\n".join(lines)
	var tail := lines.slice(lines.size() - max_lines)
	tail[0] = "…" + tail[0]
	return "\n".join(tail)
