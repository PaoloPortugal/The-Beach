class_name MarkdownParser
extends RefCounted
## Markdown -> blocks, and inline Markdown -> BBCode (C03). From the M0 spike
## (`spikes/markdown/`, dev log 2026-09-29-markdown-spike).
##
## Safety (NOTES.md → Security rules): every character of message text is
## escaped (`[` -> `[lb]`), so the only BBCode tags in the output are ones
## this file writes. Links become `[url=<index>]` into a caller-owned
## `links` array, so no URL text ever sits inside a tag, and only
## http(s)/mailto links are made clickable at all.
##
## Covers the subset Claude writes: ATX headings, paragraphs, bullet / ordered
## / task lists (nested by indent), fenced code, block quotes (nested), GFM
## tables, rules, and inline code / bold / italic / strike / links /
## autolinks / bare URLs. Not covered: setext headings, indented code blocks,
## HTML, reference links, footnotes.

const SAFE_SCHEMES := ["http://", "https://", "mailto:"]
const MAX_QUOTE_DEPTH := 8
const MAX_LIST_DEPTH := 8
const MAX_LINK_LABEL := 1000
const MAX_LINK_NESTING := 8
const INLINE_CODE_BG := "#ffffff1a"
const LINK_COLOR := "#7cb8ff"

## Block kinds (Dictionaries, compared by value for streaming reuse):
##   {type="heading", level, text}
##   {type="paragraph", text}
##   {type="code", lang, text, closed}
##   {type="list", items=[{depth, ordered, number, task, text}]}
##       task: 0 = not a task, 1 = unchecked, 2 = checked
##   {type="quote", blocks}
##   {type="table", header=[...], rows=[[...]]}
##   {type="rule"}

## Any indent: Claude nests fences under list items at 3, 5 or more spaces.
## (So 4-space indented code blocks are not supported; Claude doesn't use them.)
var _re_fence := RegEx.create_from_string("^( *)(`{3,}|~{3,})[ \\t]*([^`\\s]*)")
var _re_heading := RegEx.create_from_string("^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?(?:[ \\t]+#+)?[ \\t]*$")
var _re_rule := RegEx.create_from_string("^ {0,3}([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$")
var _re_quote := RegEx.create_from_string("^ {0,3}> ?(.*)$")
var _re_list := RegEx.create_from_string("^( *)([-*+]|\\d{1,9}[.)])(?:[ \\t]+(.*)|[ \\t]*$)")
var _re_task := RegEx.create_from_string("^\\[([ xX])\\][ \\t]+(.*)$")
var _re_table_delim := RegEx.create_from_string("^ {0,3}\\|?[ \\t]*:?-+:?[ \\t]*(\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$")
var _re_autolink := RegEx.create_from_string("^<((?:https?://|mailto:)[^\\s<>]*)>")
## Trailing punctuation isn't part of a bare URL; a trailing `)` is trimmed
## afterwards only when unbalanced, so Wikipedia-style `Foo_(bar)` survives.
var _re_bare_url := RegEx.create_from_string("^https?://[^\\s<]*[^\\s<?!.,:;*_~'\"\\]]")


# --- Blocks -----------------------------------------------------------------

func parse(text: String) -> Array:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	return _parse_lines(lines, 0)


func _parse_lines(lines: PackedStringArray, quote_depth: int) -> Array:
	var blocks: Array = []
	var para := PackedStringArray()
	var i := 0
	while i < lines.size():
		var raw := lines[i]
		var line := _expand_leading_tabs(raw)
		if line.strip_edges().is_empty():
			_flush_paragraph(blocks, para)
			i += 1
			continue
		var m := _re_fence.search(line)
		if m:
			_flush_paragraph(blocks, para)
			i = _parse_fence(lines, i, m, blocks)
			continue
		m = _re_heading.search(line)
		if m:
			_flush_paragraph(blocks, para)
			blocks.append({type = "heading", level = m.get_string(1).length(), text = m.get_string(2)})
			i += 1
			continue
		if _re_rule.search(line):
			_flush_paragraph(blocks, para)
			blocks.append({type = "rule"})
			i += 1
			continue
		if _is_table_start(lines, i):
			_flush_paragraph(blocks, para)
			i = _parse_table(lines, i, blocks)
			continue
		if quote_depth < MAX_QUOTE_DEPTH and _re_quote.search(line):
			_flush_paragraph(blocks, para)
			var inner := PackedStringArray()
			while i < lines.size():
				var qm := _re_quote.search(_expand_leading_tabs(lines[i]))
				if not qm:
					break
				inner.append(qm.get_string(1))
				i += 1
			blocks.append({type = "quote", blocks = _parse_lines(inner, quote_depth + 1)})
			continue
		if _re_list.search(line):
			_flush_paragraph(blocks, para)
			i = _parse_list(lines, i, blocks)
			continue
		para.append(line.strip_edges(true, false))
		i += 1
	_flush_paragraph(blocks, para)
	return blocks


func _flush_paragraph(blocks: Array, para: PackedStringArray) -> void:
	if para.is_empty():
		return
	blocks.append({type = "paragraph", text = "\n".join(para)})
	para.clear()


func _parse_fence(lines: PackedStringArray, start: int, m: RegExMatch, blocks: Array) -> int:
	var indent := m.get_string(1).length()
	var fence := m.get_string(2)
	var fence_char := fence[0]
	var body := PackedStringArray()
	var closed := false
	var i := start + 1
	while i < lines.size():
		var l := lines[i]
		var s := l.strip_edges()
		if (
			s.length() >= fence.length()
			and s == fence_char.repeat(s.length())
			and l.length() - l.strip_edges(true, false).length() <= indent + 3
		):
			closed = true
			i += 1
			break
		var k := 0
		while k < indent and k < l.length() and l[k] == " ":
			k += 1
		body.append(l.substr(k))
		i += 1
	# While streaming, the text so far often ends in a newline; don't show it
	# as an empty last line of the still-open block.
	if not closed and not body.is_empty() and body[body.size() - 1].is_empty():
		body.remove_at(body.size() - 1)
	blocks.append({type = "code", lang = m.get_string(3), text = "\n".join(body), closed = closed})
	return i


func _is_table_start(lines: PackedStringArray, i: int) -> bool:
	if i + 1 >= lines.size():
		return false
	var head := lines[i]
	var delim := lines[i + 1]
	if head.find("|") < 0 or delim.find("|") < 0:
		return false
	if not _re_table_delim.search(delim) or delim.find("-") < 0:
		return false
	return _split_row(head).size() == _split_row(delim).size()


func _parse_table(lines: PackedStringArray, start: int, blocks: Array) -> int:
	var header := _split_row(lines[start])
	var cols := header.size()
	var rows: Array = []
	var i := start + 2
	while i < lines.size():
		var l := lines[i]
		if l.strip_edges().is_empty() or l.find("|") < 0 or _re_fence.search(l):
			break
		var cells := _split_row(l)
		cells.resize(cols)  # pads with "" or truncates, per GFM
		rows.append(Array(cells))
		i += 1
	blocks.append({type = "table", header = Array(header), rows = rows})
	return i


## Splits a table row on unescaped pipes. GFM splits inside code spans too,
## and un-escapes `\|` everywhere (code spans included), so do that here.
func _split_row(line: String) -> PackedStringArray:
	var s := line.strip_edges()
	if s.begins_with("|"):
		s = s.substr(1)
	if s.ends_with("|") and not s.ends_with("\\|"):
		s = s.left(-1)
	var cells := PackedStringArray()
	var cur := ""
	var k := 0
	while k < s.length():
		var c := s[k]
		if c == "\\" and k + 1 < s.length() and s[k + 1] == "|":
			cur += "|"
			k += 2
			continue
		if c == "|":
			cells.append(cur.strip_edges())
			cur = ""
		else:
			cur += c
		k += 1
	cells.append(cur.strip_edges())
	return cells


func _parse_list(lines: PackedStringArray, start: int, blocks: Array) -> int:
	var items: Array = []
	var indents: Array[int] = []
	var i := start
	while i < lines.size():
		var line := _expand_leading_tabs(lines[i])
		if line.strip_edges().is_empty():
			# A blank line ends the list unless the next text is another item
			# or an indented continuation of the current one.
			var j := i + 1
			while j < lines.size() and lines[j].strip_edges().is_empty():
				j += 1
			if j >= lines.size():
				return j
			var nxt := _expand_leading_tabs(lines[j])
			if _re_list.search(nxt) and not _re_rule.search(nxt) or _indent_of(nxt) >= 2 and not _re_fence.search(nxt):
				i = j
				continue
			break
		var m := _re_list.search(line)
		if m and not _re_rule.search(line):
			var ind := m.get_string(1).length()
			while not indents.is_empty() and ind < indents.back():
				indents.pop_back()
			if indents.is_empty() or ind >= indents.back() + 2:
				indents.append(ind)
			var marker := m.get_string(2)
			var ordered := marker[0] >= "0" and marker[0] <= "9"
			var text := m.get_string(3)
			var task := 0
			var tm := _re_task.search(text)
			if tm:
				task = 2 if tm.get_string(1) != " " else 1
				text = tm.get_string(2)
			items.append({
				depth = mini(indents.size() - 1, MAX_LIST_DEPTH),
				ordered = ordered,
				number = marker.left(-1).to_int() if ordered else 0,
				task = task,
				text = text,
			})
			i += 1
			continue
		# Anything that starts its own block ends the list (a fence nested
		# under an item becomes a code block after the list).
		if _re_fence.search(line) or _indent_of(line) < 2 and (
			_re_heading.search(line) or _re_quote.search(line) or _is_table_start(lines, i)
		):
			break
		# Continuation line of the current item.
		var last: Dictionary = items.back()
		last.text += "\n" + line.strip_edges()
		i += 1
	blocks.append({type = "list", items = items})
	return i


func _indent_of(line: String) -> int:
	return line.length() - line.strip_edges(true, false).length()


func _expand_leading_tabs(line: String) -> String:
	if not line.begins_with("\t") and not line.begins_with(" \t"):
		return line
	var k := 0
	var col := 0
	while k < line.length() and (line[k] == " " or line[k] == "\t"):
		col = col + 4 - col % 4 if line[k] == "\t" else col + 1
		k += 1
	return " ".repeat(col) + line.substr(k)


# --- Inline -----------------------------------------------------------------

## Escapes message text for BBCode. `[` is the only character that can start
## a tag, and `[lb]` is RichTextLabel's literal-bracket tag.
static func escape(s: String) -> String:
	return s.replace("[", "[lb]")


static func is_safe_url(url: String) -> bool:
	var lower := url.strip_edges().to_lower()
	for scheme in SAFE_SCHEMES:
		if lower.begins_with(scheme) and lower.length() > scheme.length():
			return true
	return false


## Converts one block's inline Markdown to BBCode. Clickable URLs are appended
## to `links`; the output refers to them only by index.
func inline(src: String, links: Array, allow_links := true) -> String:
	var tokens: Array = []
	var text := ""
	var pos := 0
	var n := src.length()
	while pos < n:
		var c := src[pos]
		match c:
			"\\":
				if pos + 1 < n and src[pos + 1] == "\n":
					text = _push_text(tokens, text)
					tokens.append({k = "raw", s = "\n"})
					pos += 2
				elif pos + 1 < n and _is_ascii_punct(src[pos + 1]):
					text += escape(src[pos + 1])
					pos += 2
				else:
					text += "\\"
					pos += 1
			"`":
				var run := _run_length(src, pos, "`")
				var close := _find_backtick_run(src, pos + run, run)
				if close < 0:
					text += "`".repeat(run)
					pos += run
				else:
					var code := src.substr(pos + run, close - pos - run).replace("\n", " ")
					if code.length() > 2 and code.begins_with(" ") and code.ends_with(" ") and not code.strip_edges().is_empty():
						code = code.substr(1, code.length() - 2)
					text = _push_text(tokens, text)
					tokens.append({k = "raw", s = "[bgcolor=%s][code]%s[/code][/bgcolor]" % [INLINE_CODE_BG, escape(code)]})
					pos = close + run
			"*", "_", "~":
				var run := _run_length(src, pos, c)
				var before := src[pos - 1] if pos > 0 else " "
				var after := src[pos + run] if pos + run < n else " "
				var left := not _is_space(after) and (not _is_punct(after) or _is_space(before) or _is_punct(before))
				var right := not _is_space(before) and (not _is_punct(before) or _is_space(after) or _is_punct(after))
				var can_open := left
				var can_close := right
				if c == "_":
					can_open = left and (not right or _is_punct(before))
					can_close = right and (not left or _is_punct(after))
				if c == "~" and run != 2:
					can_open = false
					can_close = false
				text = _push_text(tokens, text)
				tokens.append({k = "delim", ch = c, n = run, orig = run, open = can_open, close = can_close, opens = [], closes = []})
				pos += run
			"!", "[":
				var is_image := c == "!"
				if is_image and (pos + 1 >= n or src[pos + 1] != "["):
					text += "!"
					pos += 1
					continue
				var link := _try_link(src, pos + 1 if is_image else pos)
				if link.is_empty() or not allow_links and not is_image:
					text += escape(c)
					pos += 1
					continue
				text = _push_text(tokens, text)
				tokens.append({k = "raw", s = _render_link(link, is_image, links, allow_links)})
				pos = link.end
			"<":
				var am := _re_autolink.search(src.substr(pos, 2048))
				if am and allow_links:
					text = _push_text(tokens, text)
					tokens.append({k = "raw", s = _link_bbcode(am.get_string(1), escape(am.get_string(1)), links)})
					pos += am.get_end()
				else:
					text += "<"
					pos += 1
			"\n":
				# Chat reads better with GitHub-comment line breaks than with
				# CommonMark soft breaks: a newline in a paragraph is a newline.
				text = _push_text(tokens, text.rstrip(" "))
				tokens.append({k = "raw", s = "\n"})
				pos += 1
			_:
				if c == "h" and allow_links and (pos == 0 or _is_space(src[pos - 1]) or src[pos - 1] == "("):
					var um := _re_bare_url.search(src.substr(pos, 2048))
					if um:
						var url := _trim_unbalanced_paren(um.get_string())
						text = _push_text(tokens, text)
						tokens.append({k = "raw", s = _link_bbcode(url, escape(url), links)})
						pos += url.length()
						continue
				text += "[lb]" if c == "[" else c
				pos += 1
	_push_text(tokens, text)
	_match_emphasis(tokens)
	var out := ""
	for t in tokens:
		if t.k == "delim":
			out += "".join(t.closes) + t.ch.repeat(t.n) + "".join(t.opens)
		else:
			out += t.s
	return out


func _push_text(tokens: Array, text: String) -> String:
	if not text.is_empty():
		tokens.append({k = "raw", s = text})
	return ""


## CommonMark's "process emphasis", simplified: for each closer, find the
## nearest compatible opener; delimiters between them become literal. This
## keeps every emitted tag pair properly nested.
func _match_emphasis(tokens: Array) -> void:
	for ci in tokens.size():
		var closer: Dictionary = tokens[ci]
		if closer.k != "delim" or not closer.close:
			continue
		while closer.n > 0:
			var oi := ci - 1
			while oi >= 0:
				var o: Dictionary = tokens[oi]
				if o.k == "delim" and o.ch == closer.ch and o.open and o.n > 0:
					var rule_of_3: bool = (
						(o.close or closer.open)
						and (o.orig + closer.orig) % 3 == 0
						and not (o.orig % 3 == 0 and closer.orig % 3 == 0)
					)
					if not rule_of_3:
						break
				oi -= 1
			if oi < 0:
				break
			var opener: Dictionary = tokens[oi]
			var use := 2 if closer.n >= 2 and opener.n >= 2 else 1
			var tag := "s" if closer.ch == "~" else ("b" if use == 2 else "i")
			opener.n -= use
			closer.n -= use
			opener.opens.push_front("[%s]" % tag)
			closer.closes.append("[/%s]" % tag)
			for k in range(oi + 1, ci):
				if tokens[k].k == "delim":
					tokens[k].open = false
					tokens[k].close = false


## Parses `[label](dest "title")` starting at the `[`. Returns
## {label, url, end} or {} when it isn't a link.
func _try_link(src: String, start: int) -> Dictionary:
	var n := src.length()
	var depth := 0
	var k := start
	var label_end := -1
	# Caps keep a run of `[` from making this quadratic.
	while k < n and k - start < MAX_LINK_LABEL:
		var c := src[k]
		if c == "\\":
			k += 2
			continue
		if c == "`":
			var run := _run_length(src, k, "`")
			var close := _find_backtick_run(src, k + run, run)
			k = close + run if close >= 0 else k + run
			continue
		if c == "[":
			depth += 1
			if depth > MAX_LINK_NESTING:
				return {}
		elif c == "]":
			depth -= 1
			if depth == 0:
				label_end = k
				break
		k += 1
	if label_end < 0 or label_end + 1 >= n or src[label_end + 1] != "(":
		return {}
	k = label_end + 2
	while k < n and src[k] == " ":
		k += 1
	var url := ""
	if k < n and src[k] == "<":
		var gt := src.find(">", k)
		if gt < 0:
			return {}
		url = src.substr(k + 1, gt - k - 1)
		k = gt + 1
	else:
		var parens := 0
		var url_start := k
		while k < n:
			var c := src[k]
			if c == "\\" and k + 1 < n:
				k += 2
				continue
			if _is_space(c):
				break
			if c == "(":
				parens += 1
			elif c == ")":
				if parens == 0:
					break
				parens -= 1
			k += 1
		url = src.substr(url_start, k - url_start)
	while k < n and src[k] == " ":
		k += 1
	if k < n and (src[k] == "\"" or src[k] == "'"):
		var q := src.find(src[k], k + 1)
		if q < 0:
			return {}
		k = q + 1
		while k < n and src[k] == " ":
			k += 1
	if k >= n or src[k] != ")":
		return {}
	return {label = src.substr(start + 1, label_end - start - 1), url = url, end = k + 1}


func _render_link(link: Dictionary, is_image: bool, links: Array, allow_links: bool) -> String:
	if is_image:
		# Never load images from message content; show the alt text instead.
		var alt: String = "image" if link.label.strip_edges().is_empty() else link.label
		var shown := "[i]%s[/i]" % escape("[image: %s]" % alt)
		return _link_bbcode(link.url, shown, links) if allow_links else shown
	var label := inline(link.label, links, false)
	return _link_bbcode(link.url, label, links)


## A clickable link for safe schemes; otherwise the label followed by the
## address in plain text, so the user still sees where it pointed.
func _link_bbcode(url: String, label_bbcode: String, links: Array) -> String:
	if not is_safe_url(url):
		if url.is_empty():
			return label_bbcode
		return "%s [color=#ffffff80](%s)[/color]" % [label_bbcode, escape(url)]
	links.append(url.strip_edges())
	return "[url=%d][color=%s]%s[/color][/url]" % [links.size() - 1, LINK_COLOR, label_bbcode]


func _run_length(src: String, pos: int, c: String) -> int:
	var k := pos
	while k < src.length() and src[k] == c:
		k += 1
	return k - pos


## Position of the next backtick run of exactly `run` characters, or -1.
func _find_backtick_run(src: String, from: int, run: int) -> int:
	var k := from
	while k < src.length():
		if src[k] == "`":
			var r := _run_length(src, k, "`")
			if r == run:
				return k
			k += r
		else:
			k += 1
	return -1


func _trim_unbalanced_paren(url: String) -> String:
	while url.ends_with(")") and url.count("(") < url.count(")"):
		url = url.left(-1)
	return url


func _is_space(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"


func _is_ascii_punct(c: String) -> bool:
	return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(c)


func _is_punct(c: String) -> bool:
	return _is_ascii_punct(c) or "“”‘’«»–—…¿¡".contains(c)
