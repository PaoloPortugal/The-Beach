extends Control
## Throwaway C03 spike demo. Pick a sample, render it at once or stream it the
## way the Claude provider receives text (MessageDisplay: batches of whole
## lines), and watch how long each re-render takes. The slider sets the chat
## panel's width, to check wrapping and code-block scrolling.

const MdView := preload("res://spikes/markdown/md_view.gd")
const SAMPLES_DIR := "res://spikes/markdown/samples/"
const STREAM_INTERVAL := 0.08
const MdParser := preload("res://spikes/markdown/md_parser.gd")

var _parser := MdParser.new()

var _samples: Dictionary = {}
var _picker: OptionButton
var _stats: Label
var _panel: PanelContainer
var _scroll: ScrollContainer
var _view: VBoxContainer
var _confirm: ConfirmationDialog
var _pending_url := ""

var _stream_lines := PackedStringArray()
var _stream_pos := 0
var _stream_timer: Timer
var _timings: Array[int] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_samples()
	_build_ui()
	if "--bench" in OS.get_cmdline_user_args():
		_bench.call_deferred()
		return
	_render_all()


## `godot --path . res://spikes/markdown/demo.tscn -- --bench` renders every
## sample a few times, prints the timings and quits: numbers without the
## editor's debugger attached.
func _bench() -> void:
	for i in _picker.item_count:
		_picker.select(i)
		for rep in 3:
			await _render_all()
			print("%s #%d: %s" % [_picker.get_item_text(i), rep + 1, _stats.text])
			var by_kind := PackedStringArray()
			for kind in _view.build_usec_by_kind:
				by_kind.append("%s %.1f ms" % [kind, _view.build_usec_by_kind[kind] / 1000.0])
			print("    by kind: ", ", ".join(by_kind))
	get_tree().quit()


func _load_samples() -> void:
	for file in DirAccess.get_files_at(SAMPLES_DIR):
		if file.ends_with(".md"):
			_samples[file.get_basename()] = FileAccess.get_file_as_string(SAMPLES_DIR + file)
	# A long reply, for timing: the typical sample ten times over.
	if _samples.has("1-typical"):
		var parts := PackedStringArray()
		for i in 10:
			parts.append(_samples["1-typical"])
		_samples["3-long (typical x10)"] = "\n\n".join(parts)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0f1318")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	_picker = OptionButton.new()
	var names := _samples.keys()
	names.sort()
	for n in names:
		_picker.add_item(n)
	_picker.item_selected.connect(func(_i: int) -> void: _render_all())
	bar.add_child(_picker)
	var render := Button.new()
	render.text = "Render"
	render.pressed.connect(_render_all)
	bar.add_child(render)
	var stream := Button.new()
	stream.text = "Stream"
	stream.pressed.connect(_start_stream)
	bar.add_child(stream)
	var width_label := Label.new()
	width_label.text = "   Width"
	bar.add_child(width_label)
	var width := HSlider.new()
	width.min_value = 320
	width.max_value = 1400
	width.value = 760
	width.custom_minimum_size.x = 200
	width.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	width.value_changed.connect(func(v: float) -> void: _panel.custom_minimum_size.x = v)
	bar.add_child(width)
	_stats = Label.new()
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.clip_text = true  # long stats must not widen the whole layout
	bar.add_child(_stats)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.use_top_left = false
	_scroll.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = width.value
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e242d")
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	_view = MdView.new()
	_view.link_clicked.connect(_on_link_clicked)
	_panel.add_child(_view)

	# Links from message content are untrusted: never open one without the
	# user seeing the full address and confirming.
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Open link?"
	_confirm.ok_button_text = "Open in browser"
	_confirm.confirmed.connect(func() -> void: OS.shell_open(_pending_url))
	add_child(_confirm)

	_stream_timer = Timer.new()
	_stream_timer.wait_time = STREAM_INTERVAL
	_stream_timer.timeout.connect(_stream_tick)
	add_child(_stream_timer)


func _current_text() -> String:
	if _picker.item_count == 0:
		return "*No samples found in %s*" % SAMPLES_DIR
	return _samples[_picker.get_item_text(_picker.selected)]


func _render_all() -> void:
	_stream_timer.stop()
	_reset_view()
	var t0 := Time.get_ticks_usec()
	var blocks := _parser.parse(_current_text())
	var t1 := Time.get_ticks_usec()
	var r: Dictionary = _view.set_blocks(blocks)
	var t2 := Time.get_ticks_usec()
	_stats.text = "Full render: parse %.2f ms + build %.2f ms, %d segments (layout: next frame)" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, r.built,
	]
	# Layout and text shaping happen on the next frame; time that too.
	await get_tree().process_frame
	var t3 := Time.get_ticks_usec()
	_stats.text += "  | to next frame %.2f ms" % ((t3 - t2) / 1000.0)


func _start_stream() -> void:
	_reset_view()
	_stream_lines = _current_text().split("\n")
	_stream_pos = 0
	_timings.clear()
	_stream_timer.start()


func _stream_tick() -> void:
	# MessageDisplay delivers whole lines in small batches.
	_stream_pos = mini(_stream_pos + _rng.randi_range(1, 3), _stream_lines.size())
	var so_far := "\n".join(_stream_lines.slice(0, _stream_pos))
	var t0 := Time.get_ticks_usec()
	var r: Dictionary = _view.set_markdown(so_far)
	_timings.append(Time.get_ticks_usec() - t0)
	var worst: int = _timings.max()
	var total := 0
	for t in _timings:
		total += t
	_stats.text = "Streaming %d/%d lines: last %.2f ms (kept %d, updated %d, built %d), avg %.2f, worst %.2f ms" % [
		_stream_pos, _stream_lines.size(), _timings.back() / 1000.0,
		r.kept, r.updated, r.built, total / 1000.0 / _timings.size(), worst / 1000.0,
	]
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	if _stream_pos >= _stream_lines.size():
		_stream_timer.stop()


func _reset_view() -> void:
	var fresh := MdView.new()
	fresh.link_clicked.connect(_on_link_clicked)
	_panel.remove_child(_view)
	_view.queue_free()
	_view = fresh
	_panel.add_child(_view)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var page := int(_scroll.size.y * 0.8)
	match key.keycode:
		KEY_PAGEDOWN:
			_scroll.scroll_vertical += page
		KEY_PAGEUP:
			_scroll.scroll_vertical -= page
		KEY_HOME:
			_scroll.scroll_vertical = 0
		KEY_END:
			_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_link_clicked(url: String) -> void:
	_pending_url = url
	_confirm.dialog_text = "This link came from the message. Open it?\n\n%s" % url
	_confirm.popup_centered()
