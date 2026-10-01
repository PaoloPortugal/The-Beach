class_name MarkdownBBCode
extends RefCounted
## Turns [MarkdownParser] blocks into BBCode for a RichTextLabel (C03).
## [method prose] is for the chat panel, where code blocks and quotes are
## their own controls ([MarkdownView]); [method flat] puts a whole message
## in one label, for the bubble above an orchestrator ([MessageBubble]).
## Message text only ever reaches the output through the parser's escaping.

const BLOCK_GAP := "\n[font_size=%d] [/font_size]\n"
## Heading sizes, as multiples of the base font size, for levels 1 to 6.
const HEADING_SCALE := [1.45, 1.25, 1.1, 1.0, 1.0, 1.0]
const BULLETS := ["•", "◦", "▪"]
const TABLE_BORDER := "#ffffff30"
const TABLE_HEADER_BG := "#ffffff14"
const QUOTE_COLOR := "#ffffffb0"
const RULE_COLOR := "#ffffff60"
const CODE_BG := "#00000055"

var parser := MarkdownParser.new()
## The label's normal font size; headings are scaled from it.
var font_size := 18
## Headings bigger than the text. Off in the bubble, where they're bold only.
var scale_headings := true


## Headings, paragraphs, lists and tables, with a small gap between blocks.
## Clickable URLs are appended to [param links].
func prose(blocks: Array, links: Array) -> String:
	var parts := PackedStringArray()
	for b in blocks:
		match b.type:
			"heading":
				parts.append(_heading(b, links))
			"paragraph":
				parts.append(parser.inline(b.text, links))
			"list":
				parts.append(_list(b.items, links))
			"table":
				parts.append(_table(b, links))
	return (BLOCK_GAP % maxi(1, font_size / 3)).join(parts)


## Every block, code and quotes included, one per line and no gaps.
func flat(blocks: Array, links: Array) -> String:
	var parts := PackedStringArray()
	for b in blocks:
		match b.type:
			"code":
				# The bubble is too small to spend lines on blank ones.
				var lines := Array(b.text.split("\n")).filter(func(l: String) -> bool: return not l.strip_edges().is_empty())
				if not lines.is_empty():
					parts.append("[bgcolor=%s][code]%s[/code][/bgcolor]" % [CODE_BG, MarkdownParser.escape("\n".join(lines))])
			"quote":
				var inner := flat(b.blocks, links)
				if not inner.is_empty():
					parts.append("[indent][color=%s]%s[/color][/indent]" % [QUOTE_COLOR, inner])
			"rule":
				parts.append("[color=%s]———[/color]" % RULE_COLOR)
			_:
				parts.append(prose([b], links))
	return "\n".join(parts)


func _heading(b: Dictionary, links: Array) -> String:
	var text := "[b]%s[/b]" % parser.inline(b.text, links)
	if not scale_headings:
		return text
	return "[font_size=%d]%s[/font_size]" % [roundi(font_size * HEADING_SCALE[b.level - 1]), text]


## One [ul] per item, with our own marker, so numbering can continue across a
## list that a code block split in two ("1." ... code ... "2."), and task
## items get a box instead of a bullet. An item's [ul] stays open while its
## children are written, which nests them with a proper hanging indent.
## (Compared in the spike: [indent] around [ul] lost the marker and added
## blank lines; an empty wrapper [ul] added a blank line per nested item.)
func _list(items: Array, links: Array) -> String:
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
		var body := parser.inline(item.text.replace("\n", " "), links)
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


func _table(b: Dictionary, links: Array) -> String:
	var cols: int = b.header.size()
	var s := "[table=%d]" % cols
	for cell in b.header:
		s += "[cell bg=%s border=%s padding=6,3,6,3][b]%s[/b][/cell]" % [TABLE_HEADER_BG, TABLE_BORDER, parser.inline(cell, links)]
	for row in b.rows:
		for cell in row:
			s += "[cell border=%s padding=6,3,6,3]%s[/cell]" % [TABLE_BORDER, parser.inline(cell, links)]
	return s + "[/table]"
