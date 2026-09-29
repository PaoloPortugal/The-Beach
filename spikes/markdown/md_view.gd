extends VBoxContainer
## Throwaway C03 spike: renders one chat message's Markdown as a stack of
## controls. Consecutive prose blocks share one RichTextLabel (so selection
## runs across paragraphs); each code block is its own read-only CodeEdit
## panel; quotes nest another view; rules are separators.
##
## Streaming: call set_markdown() with the whole text so far after each batch.
## Leading segments that didn't change are kept, the first changed one is
## updated in place when it's the same kind (no flicker), the rest rebuilt.

signal link_clicked(url: String)

const MdParser := preload("res://spikes/markdown/md_parser.gd")

const HEADING_SIZES := [26, 22, 19, 17, 16, 16]
const BLOCK_GAP := "\n[font_size=6] [/font_size]\n"
const BULLETS := ["•", "◦", "▪"]
const TABLE_BORDER := "#ffffff30"
const TABLE_HEADER_BG := "#ffffff14"
const CODE_BG := Color("#161a21")
const CODE_TEXT := Color("#d4d4d4")
const WHEEL_STEP := 48.0
## Spike switch: lay out prose on a background thread (RichTextLabel.threaded).
static var THREADED_PROSE := "--threaded" in OS.get_cmdline_user_args()

const KEYWORDS := {
	"gdscript": ["func", "var", "const", "if", "elif", "else", "for", "while", "match", "return", "extends", "class_name", "signal", "static", "await", "preload", "and", "or", "not", "in", "is", "as", "true", "false", "null", "self", "pass", "break", "continue", "enum", "super"],
	"python": ["def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "return", "with", "try", "except", "finally", "raise", "lambda", "yield", "async", "await", "and", "or", "not", "in", "is", "None", "True", "False", "pass", "break", "continue", "self"],
	"js": ["function", "const", "let", "var", "if", "else", "for", "while", "return", "class", "extends", "new", "import", "export", "from", "default", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "interface", "type", "true", "false", "null", "undefined", "this", "of", "in"],
	"shell": ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "export", "local", "return", "echo", "cd", "sudo"],
}
const LANG_ALIASES := {
	"gd": "gdscript", "py": "python", "javascript": "js", "ts": "js", "typescript": "js",
	"jsx": "js", "tsx": "js", "mjs": "js", "json": "js", "bash": "shell", "sh": "shell",
	"zsh": "shell", "powershell": "shell", "ps1": "shell", "console": "shell",
}
const HASH_COMMENT_LANGS := ["gdscript", "python", "shell"]

## Shared by every view: a SystemFont per view repeats the system lookup
## and starts an empty glyph cache for each message.
static var _shared_mono: Font

var mono_font: Font
## Spike instrumentation: build time per segment kind in the last set_blocks.
var build_usec_by_kind := {}

var _parser := MdParser.new()
var _segs: Array = []
var _nodes: Array[Control] = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	if _shared_mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "JetBrains Mono", "DejaVu Sans Mono", "Menlo", "Monaco", "monospace"])
		_shared_mono = f
	mono_font = _shared_mono


## Returns {kept, updated, built} segment counts, for the demo's stats.
func set_markdown(text: String) -> Dictionary:
	return set_blocks(_parser.parse(text))


func set_blocks(blocks: Array) -> Dictionary:
	var segs := _segment(blocks)
	var limit := mini(segs.size(), _segs.size())
	var keep := 0
	while keep < limit and segs[keep] == _segs[keep]:
		keep += 1
	var first_new := keep
	var updated := 0
	if keep < limit and segs[keep].kind == _segs[keep].kind and segs[keep].kind in ["prose", "code"]:
		_update(_nodes[keep], segs[keep])
		first_new += 1
		updated = 1
	for j in range(_nodes.size() - 1, first_new - 1, -1):
		var node := _nodes[j]
		remove_child(node)
		node.queue_free()
	_nodes.resize(first_new)
	build_usec_by_kind.clear()
	for j in range(first_new, segs.size()):
		var t0 := Time.get_ticks_usec()
		var node := _build(segs[j])
		add_child(node)
		_nodes.append(node)
		var kind: String = segs[j].kind
		build_usec_by_kind[kind] = build_usec_by_kind.get(kind, 0) + Time.get_ticks_usec() - t0
	_segs = segs
	return {kept = keep, updated = updated, built = segs.size() - first_new}


func _segment(blocks: Array) -> Array:
	var segs: Array = []
	var prose: Array = []
	for b in blocks:
		if b.type in ["heading", "paragraph", "list", "table"]:
			prose.append(b)
			continue
		if not prose.is_empty():
			segs.append({kind = "prose", blocks = prose})
			prose = []
		match b.type:
			"code":
				segs.append({kind = "code", block = b})
			"quote":
				segs.append({kind = "quote", block = b})
			"rule":
				segs.append({kind = "rule"})
	if not prose.is_empty():
		segs.append({kind = "prose", blocks = prose})
	return segs


func _build(seg: Dictionary) -> Control:
	match seg.kind:
		"prose":
			return _build_prose(seg)
		"code":
			return _build_code(seg.block)
		"quote":
			return _build_quote(seg.block)
	return HSeparator.new()


func _update(node: Control, seg: Dictionary) -> void:
	if seg.kind == "prose":
		var links: Array = []
		(node as RichTextLabel).text = _prose_bbcode(seg.blocks, links)
		node.set_meta("links", links)
	else:
		var code: CodeEdit = node.get_meta("code")
		code.text = seg.block.text
		(node.get_meta("lang_label") as Label).text = _lang_caption(seg.block)


# --- Prose ------------------------------------------------------------------

func _build_prose(seg: Dictionary) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.context_menu_enabled = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.threaded = THREADED_PROSE
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.add_theme_font_override("mono_font", mono_font)
	rtl.meta_clicked.connect(func(meta: Variant) -> void:
		var url := _link_for(rtl, meta)
		if not url.is_empty():
			link_clicked.emit(url)
	)
	# Show where a link goes before it's clicked.
	rtl.meta_hover_started.connect(func(meta: Variant) -> void: rtl.tooltip_text = _link_for(rtl, meta))
	rtl.meta_hover_ended.connect(func(_meta: Variant) -> void: rtl.tooltip_text = "")
	var links: Array = []
	var t0 := Time.get_ticks_usec()
	var bbcode := _prose_bbcode(seg.blocks, links)
	var t1 := Time.get_ticks_usec()
	rtl.text = bbcode
	var t2 := Time.get_ticks_usec()
	build_usec_by_kind["prose:to_bbcode"] = build_usec_by_kind.get("prose:to_bbcode", 0) + t1 - t0
	build_usec_by_kind["prose:rtl_text"] = build_usec_by_kind.get("prose:rtl_text", 0) + t2 - t1
	rtl.set_meta("links", links)
	return rtl


func _link_for(rtl: RichTextLabel, meta: Variant) -> String:
	var links: Array = rtl.get_meta("links", [])
	var key := str(meta)
	if not key.is_valid_int():
		return ""
	var idx := key.to_int()
	return links[idx] if idx >= 0 and idx < links.size() else ""


func _prose_bbcode(blocks: Array, links: Array) -> String:
	var parts := PackedStringArray()
	for b in blocks:
		match b.type:
			"heading":
				parts.append("[font_size=%d][b]%s[/b][/font_size]" % [HEADING_SIZES[b.level - 1], _parser.inline(b.text, links)])
			"paragraph":
				parts.append(_parser.inline(b.text, links))
			"list":
				parts.append(_list_bbcode(b.items, links))
			"table":
				parts.append(_table_bbcode(b, links))
	return BLOCK_GAP.join(parts)


## One [ul] per item, with our own marker, so numbering can continue across a
## list that a code block split in two ("1." ... code ... "2."), and task
## items get a box instead of a bullet. An item's [ul] stays open while its
## children are written, which nests them with a proper hanging indent.
## (Compared in list_lab.tscn: [indent] around [ul] lost the marker and added
## blank lines; an empty wrapper [ul] added a blank line per nested item.)
func _list_bbcode(items: Array, links: Array) -> String:
	var out := ""
	var open_depths: Array[int] = []
	var counters := {}
	var prev_ordered_at := {}
	for item in items:
		var d: int = item.depth
		for deeper in counters.keys():
			if deeper > d:
				counters.erase(deeper)
				prev_ordered_at.erase(deeper)
		var marker: String
		if item.task == 1:
			marker = "☐"
		elif item.task == 2:
			marker = "☑"
		elif item.ordered:
			var n: int = counters[d] + 1 if prev_ordered_at.get(d, false) else item.number
			counters[d] = n
			marker = "%d." % n
		else:
			marker = BULLETS[d % BULLETS.size()]
		prev_ordered_at[d] = item.ordered
		if not item.ordered:
			counters.erase(d)
		# A newline inside [ul] starts a new item, so fold continuation lines.
		var body := _parser.inline(item.text.replace("\n", " "), links)
		if item.task == 2:
			body = "[color=#ffffff99]%s[/color]" % body
		while not open_depths.is_empty() and open_depths.back() >= d:
			out += "[/ul]"
			open_depths.pop_back()
		if not out.is_empty():
			out += "\n"
		out += "[ul bullet=%s]%s" % [marker, body]
		open_depths.append(d)
	return out + "[/ul]".repeat(open_depths.size())


func _table_bbcode(b: Dictionary, links: Array) -> String:
	var cols: int = b.header.size()
	var s := "[table=%d]" % cols
	for cell in b.header:
		s += "[cell bg=%s border=%s padding=6,3,6,3][b]%s[/b][/cell]" % [TABLE_HEADER_BG, TABLE_BORDER, _parser.inline(cell, links)]
	for row in b.rows:
		for cell in row:
			s += "[cell border=%s padding=6,3,6,3]%s[/cell]" % [TABLE_BORDER, _parser.inline(cell, links)]
	return s + "[/table]"


# --- Code -------------------------------------------------------------------

func _build_code(block: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CODE_BG
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var lang := Label.new()
	lang.text = _lang_caption(block)
	lang.modulate = Color(1, 1, 1, 0.55)
	head.add_child(lang)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var copy := Button.new()
	copy.text = "Copy"
	copy.flat = true
	head.add_child(copy)

	var code := CodeEdit.new()
	code.editable = false
	code.text = block.text
	code.scroll_fit_content_height = true
	code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	code.highlight_current_line = false
	code.context_menu_enabled = true
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_font_override("font", mono_font)
	code.add_theme_color_override("font_color", CODE_TEXT)
	code.add_theme_color_override("font_readonly_color", CODE_TEXT)
	code.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	code.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# scroll_fit_content_height doesn't leave room for the horizontal
	# scrollbar, which then covers the last line: pad while it's shown.
	var hbar := code.get_h_scroll_bar()
	var fit_scrollbar := func() -> void:
		var sb_ro := StyleBoxEmpty.new()
		if hbar.visible:
			sb_ro.content_margin_bottom = hbar.get_combined_minimum_size().y + 4
		code.add_theme_stylebox_override("read_only", sb_ro)
	hbar.visibility_changed.connect(fit_scrollbar)
	fit_scrollbar.call()
	code.syntax_highlighter = _highlighter_for(block.lang)
	code.gui_input.connect(_forward_wheel.bind(code))
	vb.add_child(code)

	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code.text)
		copy.text = "Copied"
		get_tree().create_timer(1.2).timeout.connect(func() -> void: copy.text = "Copy")
	)
	panel.set_meta("code", code)
	panel.set_meta("lang_label", lang)
	return panel


func _lang_caption(block: Dictionary) -> String:
	var caption: String = block.lang if not block.lang.is_empty() else "text"
	return caption if block.closed else caption + "  ·  writing…"


## A CodeEdit eats vertical wheel events even when it has nothing to scroll,
## which stops the chat from scrolling while the pointer is over code. Pass
## plain vertical wheel to the enclosing ScrollContainer; keep shift+wheel
## and horizontal wheel for the code's own horizontal scroll.
func _forward_wheel(event: InputEvent, code: CodeEdit) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.shift_pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var sc := _scroll_parent()
	if sc == null:
		return
	if mb.pressed:
		var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		sc.scroll_vertical += int(dir * WHEEL_STEP * maxf(mb.factor, 1.0))
	code.accept_event()


func _scroll_parent() -> ScrollContainer:
	var n := get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _highlighter_for(lang: String) -> SyntaxHighlighter:
	var key := lang.to_lower()
	key = LANG_ALIASES.get(key, key)
	if not KEYWORDS.has(key):
		return null
	var h := CodeHighlighter.new()
	h.number_color = Color("#b5cea8")
	h.symbol_color = Color("#c8c8c8")
	h.function_color = Color("#dcdcaa")
	h.member_variable_color = Color("#9cdcfe")
	for kw in KEYWORDS[key]:
		h.add_keyword_color(kw, Color("#569cd6"))
	h.add_color_region("\"", "\"", Color("#ce9178"))
	h.add_color_region("'", "'", Color("#ce9178"))
	if key in HASH_COMMENT_LANGS:
		h.add_color_region("#", "", Color("#6a9955"), true)
	else:
		h.add_color_region("//", "", Color("#6a9955"), true)
		h.add_color_region("/*", "*/", Color("#6a9955"))
	return h


# --- Quote ------------------------------------------------------------------

func _build_quote(block: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.03)
	sb.border_width_left = 3
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.content_margin_left = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	var inner = get_script().new()
	inner.mono_font = mono_font
	inner.link_clicked.connect(func(url: String) -> void: link_clicked.emit(url))
	panel.add_child(inner)
	inner.set_blocks(block.blocks)
	return panel
