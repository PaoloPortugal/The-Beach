extends SceneTree
## Throwaway: where does the view's build time go? Run headless:
##   godot --headless --path . --script res://spikes/markdown/bench.gd

const MdView := preload("res://spikes/markdown/md_view.gd")


func _initialize() -> void:
	var view := MdView.new()
	root.add_child(view)
	var text := FileAccess.get_file_as_string("res://spikes/markdown/samples/1-typical.md")
	view.set_markdown(text)  # warm-up: fonts, scripts
	var segs: Array = view._segs
	var totals := {}
	var counts := {}
	for rep in 20:
		for seg in segs:
			var t0 := Time.get_ticks_usec()
			var node: Control = view._build(seg)
			view.add_child(node)
			var dt := Time.get_ticks_usec() - t0
			totals[seg.kind] = totals.get(seg.kind, 0) + dt
			counts[seg.kind] = counts.get(seg.kind, 0) + 1
			view.remove_child(node)
			node.free()
	for kind in totals:
		print("%-6s avg %.2f ms per segment (%d built)" % [kind, totals[kind] / 1000.0 / counts[kind], counts[kind]])

	# The pieces of a code block, one at a time.
	var code_text: String = segs.filter(func(s): return s.kind == "code")[0].block.text
	_time("CodeEdit bare", func():
		var c := CodeEdit.new()
		c.text = code_text
		return c)
	_time("CodeEdit + highlighter", func():
		var c := CodeEdit.new()
		c.syntax_highlighter = view._highlighter_for("gdscript")
		c.text = code_text
		return c)
	_time("TextEdit bare", func():
		var c := TextEdit.new()
		c.text = code_text
		return c)
	_time("Label mono", func():
		var l := Label.new()
		l.add_theme_font_override("font", view.mono_font)
		l.text = code_text
		return l)
	_time("RichTextLabel code", func():
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.add_theme_font_override("normal_font", view.mono_font)
		r.text = MdView.new()._parser.escape(code_text)
		return r)
	quit()


func _time(label: String, make: Callable) -> void:
	var total := 0
	for rep in 20:
		var t0 := Time.get_ticks_usec()
		var node: Control = make.call()
		root.add_child(node)
		total += Time.get_ticks_usec() - t0
		root.remove_child(node)
		node.free()
	print("%-24s avg %.2f ms" % [label, total / 1000.0 / 20])
