class_name MessageBubble
extends Sprite3D
## The small window above an orchestrator (C02): its latest message,
## rendered as Markdown (C03), always facing you. It's part of the world, so
## it gets smaller with distance and terrain hides it. Drawn into a
## SubViewport shown on this billboard sprite. While a reply streams, it
## shows the newest lines.

## The widest the text gets, in pixels (about 40 characters), and the most
## lines shown.
const MAX_WIDTH := 800.0
const MAX_LINES := 4
const FONT_SIZE := 40

var _bbcode := MarkdownBBCode.new()
## Whether lines above the shown ones were cut.
var _cut := false
## The first line shown.
var _first_line := 0

@onready var _viewport: SubViewport = $Viewport
@onready var _panel: PanelContainer = $Viewport/Panel
@onready var _more: Label = $Viewport/Panel/Box/More
@onready var _clip: Control = $Viewport/Panel/Box/Clip
@onready var _text: RichTextLabel = $Viewport/Panel/Box/Clip/Text


func _ready() -> void:
	texture = _viewport.get_texture()
	visible = false
	_bbcode.font_size = FONT_SIZE
	# The bubble is too small for big headings: they're bold only.
	_bbcode.scale_headings = false
	_text.add_theme_font_override("mono_font", MarkdownView.mono_font())
	for name in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_text.add_theme_font_size_override(name, FONT_SIZE)


## What the bubble shows now, without formatting, one wrapped line per
## line, with "…" in front when lines above were cut (empty when hidden).
func shown_text() -> String:
	if not visible:
		return ""
	var parsed := _text.get_parsed_text()
	var lines := PackedStringArray()
	for line in range(_first_line, _text.get_line_count()):
		var r := _text.get_line_range(line)
		lines.append(parsed.substr(r.x, r.y - r.x).strip_edges())
	return ("…" if _cut else "") + "\n".join(lines)


## Shows the end of [param text], rendered as Markdown; empty text hides
## the bubble.
func show_text(text: String) -> void:
	visible = not text.strip_edges().is_empty()
	if not visible:
		_text.text = ""
		return
	# Links can't be clicked in the world; they're only coloured.
	_text.text = _bbcode.flat(_bbcode.parser.parse(text), [])
	# As wide as the longest line, up to MAX_WIDTH, then wrapped.
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	var width := minf(ceilf(_text.get_content_width()), MAX_WIDTH)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size = Vector2(width, _text.size.y)
	var lines := _text.get_line_count()
	var full_height := float(_text.get_content_height())
	_cut = lines > MAX_LINES
	_first_line = lines - MAX_LINES if _cut else 0
	var top := float(_text.get_line_offset(_first_line)) if _cut else 0.0
	# Only the last lines show through the clip.
	_text.size = Vector2(width, full_height)
	_text.position = Vector2(0, -top)
	_clip.custom_minimum_size = Vector2(width, full_height - top)
	_more.visible = _cut
	# Fit the viewport to the panel's new size.
	_panel.reset_size()
	_viewport.size = Vector2i(_panel.get_combined_minimum_size().ceil())
	# The bubble's bottom edge sits on the anchor, so it grows upwards.
	offset.y = _viewport.size.y / 2.0
