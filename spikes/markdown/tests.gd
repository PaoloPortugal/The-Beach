extends SceneTree
## Throwaway C03 spike tests. Run headless from the repo root:
##   godot --headless --path . --script res://spikes/markdown/tests.gd
## Exit code 0 = all passed.

const MdParser := preload("res://spikes/markdown/md_parser.gd")
const MdView := preload("res://spikes/markdown/md_view.gd")

## Every tag the parser and view may emit. Anything else in the output means
## message content got through as BBCode.
const ALLOWED_TAGS := ["b", "i", "s", "u", "code", "bgcolor", "url", "color", "font_size", "ul", "indent", "table", "cell", "lb"]

var _p := MdParser.new()
var _failed := 0
var _passed := 0
var _rtl: RichTextLabel


func _initialize() -> void:
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = true
	root.add_child(_rtl)

	_test_escaping()
	_test_links()
	_test_emphasis()
	_test_inline_misc()
	_test_blocks()
	_test_fuzz_only_our_tags()
	_test_deep_nesting()
	_test_list_bbcode()
	_test_view_builds()

	print("\n%d passed, %d failed" % [_passed, _failed])
	# A script that failed to compile runs nothing: count that as a failure.
	quit(1 if _failed > 0 or _passed == 0 else 0)


func _check(name: String, cond: bool, detail: Variant = "") -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL %s  %s" % [name, str(detail)])


## What a RichTextLabel actually displays for this BBCode.
func _shown(bbcode: String) -> String:
	_rtl.text = bbcode
	return _rtl.get_parsed_text()


func _test_escaping() -> void:
	for src in [
		"[b]x[/b]",
		"[img]https://example.com/x.png[/img]",
		"[url=https://evil]y[/url]",
		"[color=red]z",
		"[lb] [rb] [/b]",
		"[font_size=90]huge[/font_size]",
	]:
		var links := []
		var out := _p.inline(src, links)
		_check("escape shows literally: " + src, _shown(out) == src, [out, _shown(out)])
		_check("escape makes no links: " + src, links.is_empty(), links)
	var links := []
	var out := _p.inline("`[b]x[/b]`", links)
	_check("code span content literal", _shown(out) == "[b]x[/b]", _shown(out))


func _test_links() -> void:
	var links := []
	var out := _p.inline("[docs](https://docs.godotengine.org)", links)
	_check("safe link kept", links == ["https://docs.godotengine.org"], links)
	_check("link rendered by index", out.contains("[url=0]"), out)
	_check("link label shown", _shown(out) == "docs", _shown(out))

	for bad in ["javascript:alert(1)", "file:///C:/x", "../README.md", "data:text/html,hi", "JAVASCRIPT:alert(1)"]:
		links = []
		out = _p.inline("[x](%s)" % bad, links)
		_check("unsafe not clickable: " + bad, links.is_empty() and not out.contains("[url"), [links, out])

	links = []
	out = _p.inline("[t](https://e.com/a]b[img]c)", links)
	_check("bracket in url: stays in links table", links.size() == 1 and links[0].contains("[img]"), links)
	_check("bracket in url: not in bbcode", not out.contains("img"), out)

	links = []
	out = _p.inline("see https://en.wikipedia.org/wiki/Markdown_(x). and (https://e.com/in)", links)
	_check("bare urls", links == ["https://en.wikipedia.org/wiki/Markdown_(x)", "https://e.com/in"], links)

	links = []
	out = _p.inline("<https://e.com/auto> <not a link>", links)
	_check("autolink", links == ["https://e.com/auto"], links)
	_check("non-link angle text kept", _shown(out).ends_with("<not a link>"), _shown(out))

	links = []
	out = _p.inline("![alt text](https://e.com/p.png)", links)
	_check("image never loaded", not out.contains("[img"), out)
	_check("image shows alt", _shown(out) == "[image: alt text]", _shown(out))

	links = []
	out = _p.inline("[a [nested](https://x.com) b](https://y.com)", links)
	_check("no links inside link labels", links == ["https://y.com"], links)


func _test_emphasis() -> void:
	var cases := {
		"*a*": "[i]a[/i]",
		"_a_": "[i]a[/i]",
		"**a**": "[b]a[/b]",
		"__a__": "[b]a[/b]",
		"***a***": "[i][b]a[/b][/i]",
		"~~a~~": "[s]a[/s]",
		"**a *b* c**": "[b]a [i]b[/i] c[/b]",
		"snake_case_name": "snake_case_name",
		"__init__": "[b]init[/b]",
		"2*3*4": "2[i]3[/i]4",
		"a * b * c": "a * b * c",
		"**unclosed": "**unclosed",
		"\\*lit\\*": "*lit*",
		"~single~": "~single~",
	}
	for src in cases:
		var out := _p.inline(src, [])
		_check("emphasis %s" % src, out == cases[src], out)


func _test_inline_misc() -> void:
	var out := _p.inline("a  \nb", [])
	_check("hard break", _shown(out) == "a\nb", _shown(out))
	out = _p.inline("a\nb", [])
	_check("newline is a line break", _shown(out) == "a\nb", _shown(out))
	out = _p.inline("``a ` b``", [])
	_check("double-backtick span", _shown(out) == "a ` b", _shown(out))
	out = _p.inline("`unclosed", [])
	_check("unclosed backtick literal", _shown(out) == "`unclosed", _shown(out))


func _test_blocks() -> void:
	var b := _p.parse("# Title\n\nPara one\nstill one\n\n```py\nx = 1\n```\n")
	_check("blocks: count", b.size() == 3, b)
	_check("blocks: heading", b[0] == {type = "heading", level = 1, text = "Title"}, b[0])
	_check("blocks: paragraph", b[1].type == "paragraph" and b[1].text == "Para one\nstill one", b[1])
	_check("blocks: code", b[2] == {type = "code", lang = "py", text = "x = 1", closed = true}, b[2])

	b = _p.parse("```js\nlet a;\n")
	_check("unclosed fence", b.size() == 1 and b[0].closed == false and b[0].text == "let a;", b)

	b = _p.parse("Intro:\n- a\n  - b\n    1. c\n- [x] done\n- [ ] todo")
	_check("list interrupts paragraph", b.size() == 2 and b[1].type == "list", b)
	var items: Array = b[1].items
	_check("list depths", items.map(func(i): return i.depth) == [0, 1, 2, 0, 0], items)
	_check("list ordered", items[2].ordered and items[2].number == 1, items[2])
	_check("task items", items[3].task == 2 and items[4].task == 1 and items[4].text == "todo", items)

	b = _p.parse("1. one\n\n   ```bash\n   ls\n   ```\n2. two")
	_check("fence splits list", b.size() == 3 and b[1].type == "code" and b[1].text == "ls" and b[2].items[0].number == 2, b)

	b = _p.parse("| a | b |\n|:-|-:|\n| `x \\| y` | 2 |\n| only |")
	_check("table", b.size() == 1 and b[0].type == "table", b)
	if b.size() == 1 and b[0].type == "table":
		_check("table header", b[0].header == ["a", "b"], b[0].header)
		_check("table escaped pipe", b[0].rows[0] == ["`x | y`", "2"], b[0].rows)
		_check("table short row padded", b[0].rows[1] == ["only", ""], b[0].rows)

	b = _p.parse("> one\n> > two\n>\n> back")
	_check("quote nests", b.size() == 1 and b[0].type == "quote" and b[0].blocks[1].type == "quote", b)

	b = _p.parse("a\n\n---\n\n* * *\nb")
	_check("rules", b.size() == 4 and b[1].type == "rule" and b[2].type == "rule", b)

	b = _p.parse("  ```\n  indented fence\n  ```")
	_check("indented fence", b.size() == 1 and b[0].type == "code" and b[0].text == "indented fence", b)


## Random Markdown-ish input must never produce a tag outside ALLOWED_TAGS,
## and every [url=N] must point into the links table.
func _test_fuzz_only_our_tags() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var alphabet := "[]()*_~`\\<>!:/ab |#-=\n"
	var words := ["[url=", "[img]", "https://", "javascript:", "[b]", "](", "``", "**", "[lb]", "[/url]"]
	var tag_re := RegEx.create_from_string("\\[/?([a-z_]+)")
	var url_re := RegEx.create_from_string("\\[url=(\\d+)\\]")
	var view := MdView.new()
	var bad := 0
	for iter in 3000:
		var s := ""
		for k in rng.randi_range(1, 60):
			s += words[rng.randi() % words.size()] if rng.randf() < 0.2 else alphabet[rng.randi() % alphabet.length()]
		var links := []
		var out := view._prose_bbcode(_p.parse(s).filter(func(x): return x.type != "code" and x.type != "quote" and x.type != "rule"), links)
		for m in tag_re.search_all(out):
			if not m.get_string(1) in ALLOWED_TAGS:
				bad += 1
				if bad <= 3:
					print("  fuzz input: ", JSON.stringify(s), "\n  output: ", out)
		for m in url_re.search_all(out):
			if m.get_string(1).to_int() >= links.size():
				bad += 1
	view.free()
	_check("fuzz: only our tags, valid link indices", bad == 0, "%d bad" % bad)


func _test_deep_nesting() -> void:
	var t0 := Time.get_ticks_msec()
	_p.parse(">".repeat(2000) + " deep")
	_p.inline("*".repeat(5000) + "a" + "*".repeat(5000), [])
	_p.inline("[".repeat(3000) + "a" + "]".repeat(3000), [])
	_p.parse("\n".join(PackedStringArray(range(200).map(func(i): return " ".repeat(i * 2) + "- x"))))
	_check("pathological input finishes quickly", Time.get_ticks_msec() - t0 < 5000, Time.get_ticks_msec() - t0)


func _test_list_bbcode() -> void:
	var view := MdView.new()
	var items: Array = _p.parse("- a\n  - b\n  - [ ] c\n- d\n\n```\nx\n```\n3. three")[0].items
	var out: String = view._list_bbcode(items, [])
	_check("nested list bbcode", out == "[ul bullet=•]a\n[ul bullet=◦]b[/ul]\n[ul bullet=☐]c[/ul][/ul]\n[ul bullet=•]d[/ul]", out)
	var after_code: Array = _p.parse("1. one\n```\nx\n```\n2. two\n3. three")[2].items
	out = view._list_bbcode(after_code, [])
	_check("numbering continues after a code block", out == "[ul bullet=2.]two[/ul]\n[ul bullet=3.]three[/ul]", out)
	view.free()


func _test_view_builds() -> void:
	var view := MdView.new()
	root.add_child(view)
	for file in DirAccess.get_files_at("res://spikes/markdown/samples/"):
		if not file.ends_with(".md"):
			continue
		var text := FileAccess.get_file_as_string("res://spikes/markdown/samples/" + file)
		var r: Dictionary = view.set_markdown(text)
		_check("view builds " + file, view.get_child_count() == r.kept + r.updated + r.built, r)
		# Streaming line by line ends in the same state as one full render.
		var lines := text.split("\n")
		var streamed := MdView.new()
		root.add_child(streamed)
		for n in range(1, lines.size() + 1):
			streamed.set_markdown("\n".join(lines.slice(0, n)))
		_check("stream matches full render " + file, streamed._segs == view._segs)
		var r2: Dictionary = streamed.set_markdown(text)
		_check("re-render of same text reuses everything " + file, r2.built == 0 and r2.updated == 0, r2)
		streamed.queue_free()
	view.queue_free()
