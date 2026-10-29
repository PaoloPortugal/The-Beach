extends RefCounted
## The game's translation template and PO files (C16), for the tests and
## [code]write_pot.gd[/code]. Godot 4.7 can't write a template headless
## (its generator is the editor's), so this reads the code itself.
##
## What it takes, from the [constant ROOTS] ([code].gd[/code] and
## [code].tscn[/code], without [constant SKIPPED]):
## - the literal arguments of [code]tr[/code], [code]tr_n[/code],
##   [code]atr[/code], [code]atr_n[/code], [code]translate[/code] and
##   [code]translate_plural[/code] (the context: [code]tr[/code]'s second,
##   [code]tr_n[/code]'s fourth);
## - [code]text = "…"[/code] and the other shown properties
##   ([constant PROPERTIES]) set to a literal, then the statement's end,
##   [code])[/code] or [code],[/code]; and [code]add_item("…")[/code];
## - every string literal on a line marked [code]# TRANSLATE[/code]
##   ([code]# TRANSLATE: ctx[/code] gives them a context), except those
##   that look like keys: no uppercase letter, no space, nothing outside
##   ASCII ("graphics/vsync", "confirm_in_terminal");
## - in a [code].tscn[/code], the shown properties' lines, but for a node
##   with auto-translate off.
## A line marked [code]# NO_TRANSLATE[/code] gives nothing. A
## [code]# TRANSLATORS: …[/code] comment (its own line, or the line's)
## becomes the entry's [code]#.[/code] comment for the next line's
## strings. Text without a letter ("…", "30") is never taken: there is
## nothing to translate. A placeholder's name counts, so a layout of
## placeholders ("{month} {day}", "{percent} %") is: a language may
## reorder or space them.
##
## The template lists each entry's files ([code]#: world/x.gd[/code]),
## without line numbers, so moving code doesn't change it.

const ROOTS := ["agents", "chat", "core", "world"]
const SKIPPED := ["world/debug"] # C09's debug commands stay English
## Top-level folders that hold no game text: tools, data, other languages.
const NOT_GAME := ["addons", "assets", "docs", "locale", "protocol", "sidecar", "tests"]
const POT_PATH := "res://locale/messages.pot"
const PROPERTIES := ["text", "title", "tooltip_text", "placeholder_text", "ok_button_text", "cancel_button_text", "dialog_text"]
## Calls whose arguments are translated: the message's index, the plural's
## (-1 for none) and the context's.
const CALLS := {
	"tr": [0, -1, 1], "atr": [0, -1, 1], "translate": [0, -1, 1],
	"tr_n": [0, 1, 3], "atr_n": [0, 1, 3], "translate_plural": [0, 1, 3],
}
## The made-up language that shows every string as ⟦English⟧.
const PSEUDO_LOCALE := "zz"
const OPEN := "⟦"
const CLOSE := "⟧"

const _HEADER := "msgid \"\"\nmsgstr \"\"\n\"MIME-Version: 1.0\\n\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n\"Content-Transfer-Encoding: 8-bit\\n\"\n"


# --- Reading the code --------------------------------------------------

## Every entry in the code under [constant ROOTS], in order: files by
## path, then as they come. Returns {entries: Array of {ctx, id, plural,
## files, comments}, errors: Array of String}.
static func extract_project() -> Dictionary:
	var files := []
	for root: String in ROOTS:
		_find(root, files)
	files.sort()
	var sources := {}
	for path: String in files:
		sources[path] = FileAccess.get_file_as_string("res://" + path)
	return extract(sources)


## The entries of [param sources] (path → its text), as for
## [method extract_project].
static func extract(sources: Dictionary) -> Dictionary:
	var out := {"entries": [], "errors": []}
	var by_key := {}
	for path: String in sources:
		var found := _from_tscn(sources[path]) if path.ends_with(".tscn") else _from_gd(sources[path], path, out["errors"])
		for e: Dictionary in found:
			var key := key_of(e["ctx"], e["id"])
			if not by_key.has(key):
				var entry := {"ctx": e["ctx"], "id": e["id"], "plural": e["plural"], "files": [], "comments": []}
				by_key[key] = entry
				out["entries"].append(entry)
			var entry: Dictionary = by_key[key]
			if not e["plural"].is_empty():
				if entry["plural"].is_empty():
					entry["plural"] = e["plural"]
				elif entry["plural"] != e["plural"]:
					out["errors"].append("%s: \"%s\" has two plurals: \"%s\" and \"%s\"" % [path, e["id"], entry["plural"], e["plural"]])
			if not path in entry["files"]:
				entry["files"].append(path)
			if not e["comment"].is_empty() and not e["comment"] in entry["comments"]:
				entry["comments"].append(e["comment"])
	return out


## The key a translation is looked up by: its context and its text.
static func key_of(ctx: String, id: String) -> String:
	return ctx + "\u0004" + id


static func _find(dir: String, into: Array) -> void:
	if dir in SKIPPED:
		return
	var d := DirAccess.open("res://" + dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			into.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_find(dir.path_join(sub), into)


# The marks and translators' comments of a script, by line.
static func _marks(comments: Dictionary, code_lines: Dictionary) -> Dictionary:
	var marks := {} # line → "" (no context), its context, or null (NO_TRANSLATE)
	var notes := {} # line → the translators' comment for its strings
	var last_code := 0
	for line: int in code_lines:
		last_code = maxi(last_code, line)
	for line: int in comments:
		var c: String = comments[line].lstrip("#").strip_edges()
		if c == "TRANSLATE":
			marks[line] = ""
		elif c.begins_with("TRANSLATE:"):
			marks[line] = c.trim_prefix("TRANSLATE:").strip_edges()
		elif c == "NO_TRANSLATE":
			marks[line] = null
		elif c.begins_with("TRANSLATORS:"):
			var target := line
			while not code_lines.has(target) and target <= last_code:
				target += 1
			var note := c.trim_prefix("TRANSLATORS:").strip_edges()
			notes[target] = notes[target] + " " + note if notes.has(target) else note
	return {"marks": marks, "notes": notes}


static func _from_gd(text: String, path: String, errors: Array) -> Array:
	var lexed := tokenize(text)
	if not lexed["error"].is_empty():
		errors.append("%s: %s" % [path, lexed["error"]])
	var tokens: Array = lexed["tokens"]
	var code_lines := {}
	for t: Dictionary in tokens:
		if t["kind"] != "nl":
			code_lines[t["line"]] = true
	var m := _marks(lexed["comments"], code_lines)
	var marks: Dictionary = m["marks"]
	var notes: Dictionary = m["notes"]
	var found := []
	var add := func(id: String, plural: String, ctx: String, line: int) -> void:
		if marks.has(line) and marks[line] == null:
			return
		if _has_letter(id):
			found.append({"id": id, "plural": plural, "ctx": ctx, "comment": notes.get(line, "")})
	for i in tokens.size():
		var t: Dictionary = tokens[i]
		var next: Dictionary = tokens[i + 1] if i + 1 < tokens.size() else {"kind": "nl", "text": ""}
		if t["kind"] == "id" and CALLS.has(t["text"]) and next["text"] == "(" and next["kind"] == "op":
			var args := _args(tokens, i + 1)
			var which: Array = CALLS[t["text"]]
			var msg: Variant = _literal(args, which[0])
			if msg != null:
				var plural: Variant = _literal(args, which[1]) if which[1] >= 0 else ""
				var ctx: Variant = _literal(args, which[2])
				# A context that isn't a literal: its text can't be known here.
				if plural != null and (ctx != null or which[2] >= args.size()):
					add.call(msg["text"], plural["text"] if plural is Dictionary else "", ctx["text"] if ctx != null else "", msg["line"])
		elif t["kind"] == "id" and t["text"] in PROPERTIES and next["kind"] == "op" and next["text"] == "=" and (i == 0 or tokens[i - 1]["text"] != "var"):
			var value: Dictionary = tokens[i + 2] if i + 2 < tokens.size() else {}
			var after: Dictionary = tokens[i + 3] if i + 3 < tokens.size() else {"kind": "nl", "text": ""}
			if value.get("kind") == "str" and (after["kind"] == "nl" or after["text"] in [")", ",", ";", "]", "}"]):
				add.call(value["text"], "", "", value["line"])
		elif t["kind"] == "id" and t["text"] == "add_item" and next["text"] == "(":
			var value: Dictionary = tokens[i + 2] if i + 2 < tokens.size() else {}
			var after: Dictionary = tokens[i + 3] if i + 3 < tokens.size() else {}
			if value.get("kind") == "str" and after.get("text") in [")", ","]:
				add.call(value["text"], "", "", value["line"])
		elif t["kind"] == "str" and marks.has(t["line"]) and marks[t["line"]] != null and not _looks_like_key(t["text"]):
			add.call(t["text"], "", marks[t["line"]], t["line"])
	return found


# The arguments of the call whose "(" is tokens[open]: each a list of
# tokens, newlines left out.
static func _args(tokens: Array, open: int) -> Array:
	var args := [[]]
	var depth := 0
	for j in range(open + 1, tokens.size()):
		var t: Dictionary = tokens[j]
		if t["kind"] == "op" and t["text"] in ["(", "[", "{"]:
			depth += 1
		elif t["kind"] == "op" and t["text"] in [")", "]", "}"]:
			if depth == 0:
				break
			depth -= 1
		elif t["kind"] == "op" and t["text"] == "," and depth == 0:
			args.append([])
			continue
		if t["kind"] != "nl":
			args[-1].append(t)
	return args


# Argument [param index] if it is one string literal (its token), else null.
static func _literal(args: Array, index: int) -> Variant:
	if index < 0 or index >= args.size():
		return null
	var arg: Array = args[index]
	if arg.size() == 1 and arg[0]["kind"] == "str":
		return arg[0]
	return null


## Whether [param s] looks like a key, not text: no uppercase letter, no
## space and nothing outside ASCII.
static func _looks_like_key(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c > 127 or c == 32 or (c >= 65 and c <= 90):
			return false
	return true


static func _has_letter(s: String) -> bool:
	for i in s.length():
		var ch := s[i]
		if ch.to_upper() != ch.to_lower():
			return true
	return false


static func _from_tscn(text: String) -> Array:
	var found := []
	var lines := text.split("\n")
	var section := []
	var off := false
	for i in lines.size():
		var line := lines[i]
		if line.begins_with("["):
			if not off:
				found.append_array(section)
			section = []
			off = false
		elif line.begins_with("auto_translate_mode = 2"): # disabled
			off = true
		else:
			for p: String in PROPERTIES:
				if line.begins_with(p + " = \""):
					# The value may run over several lines.
					var lexed := _string("\n".join(lines.slice(i)), p.length() + 3, false, false)
					if lexed.has("text") and _has_letter(lexed["text"]):
						section.append({"id": lexed["text"], "plural": "", "ctx": "", "comment": ""})
					break
	if not off:
		found.append_array(section)
	return found


## GDScript's tokens, enough for the extractor: {tokens: Array of {kind:
## "id"|"str"|"num"|"op"|"nl", text, line}, comments: line → its comment,
## error}. A string's line is where it starts; ^"node/path" isn't a string.
static func tokenize(src: String) -> Dictionary:
	var tokens := []
	var comments := {}
	var line := 1
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "\n":
			tokens.append({"kind": "nl", "text": "", "line": line})
			line += 1
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			i += 1
		elif c == "\\" and i + 1 < n and (src[i + 1] == "\n" or src[i + 1] == "\r"):
			i += 1 # a line continued
			while i < n and src[i] != "\n":
				i += 1
			i += 1
			line += 1
		elif c == "#":
			var end := src.find("\n", i)
			if end == -1:
				end = n
			comments[line] = src.substr(i, end - i)
			i = end
		elif c == "\"" or c == "'" or ((c == "&" or c == "^" or c == "r") and i + 1 < n and (src[i + 1] == "\"" or src[i + 1] == "'")):
			var prefix := ""
			if c != "\"" and c != "'":
				prefix = c
				i += 1
			var lexed := _string(src, i, prefix == "r", true)
			if lexed.has("error"):
				return {"tokens": tokens, "comments": comments, "error": "line %d: %s" % [line, lexed["error"]]}
			if prefix != "^":
				tokens.append({"kind": "str", "text": lexed["text"], "line": line})
			line += src.substr(i, lexed["end"] - i).count("\n")
			i = lexed["end"]
		elif _is_word(c):
			var start := i
			while i < n and (_is_word(src[i]) or src[i].is_valid_int()):
				i += 1
			tokens.append({"kind": "id", "text": src.substr(start, i - start), "line": line})
		elif c.is_valid_int():
			var start := i
			while i < n and (_is_word(src[i]) or src[i].is_valid_int() or src[i] == "."):
				i += 1
			tokens.append({"kind": "num", "text": src.substr(start, i - start), "line": line})
		elif c in "()[]{},;.":
			tokens.append({"kind": "op", "text": c, "line": line})
			i += 1
		else:
			# An operator: "=" alone, or with the others ("==", ":=", "+=").
			var start := i
			while i < n and src[i] in "=!<>:+-*/%&|^~@$?" and not (i > start and src[i] in "&^" and i + 1 < n and src[i + 1] in "\"'"):
				i += 1
			if i == start:
				i += 1
			tokens.append({"kind": "op", "text": src.substr(start, i - start), "line": line})
	return {"tokens": tokens, "comments": comments, "error": ""}


static func _is_word(c: String) -> bool:
	return c == "_" or c.to_upper() != c.to_lower() or (c.unicode_at(0) > 127 and not c in OPEN + CLOSE)


# The string literal whose opening quote is at src[at]: {text, end} (end
# just past its closing quote), or {error}. [param raw]: r"…", no escapes;
# [param triple]: """…""" allowed.
static func _string(src: String, at: int, raw: bool, triple: bool) -> Dictionary:
	var q := src[at]
	var long := triple and src.substr(at, 3) == q + q + q
	var i := at + (3 if long else 1)
	var out := ""
	var n := src.length()
	while i < n:
		var c := src[i]
		if long and src.substr(i, 3) == q + q + q:
			return {"text": out, "end": i + 3}
		if not long and c == q:
			return {"text": out, "end": i + 1}
		if c == "\\" and i + 1 < n:
			var e := src[i + 1]
			if raw:
				out += c + e # kept as written; \" doesn't end it
				i += 2
				continue
			i += 2
			match e:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				"a": out += char(7)
				"b": out += char(8)
				"f": out += char(12)
				"v": out += char(11)
				"\\", "\"", "'": out += e
				"\n": pass # continued on the next line
				"u", "U":
					var digits := 4 if e == "u" else 6
					var hex := src.substr(i, digits)
					if hex.length() != digits or not hex.is_valid_hex_number():
						return {"error": "a bad \\%s escape" % e}
					out += char(hex.hex_to_int())
					i += digits
				_: out += "\\" + e
			continue
		out += c
		i += 1
	return {"error": "a string never closed"}


# --- The template ------------------------------------------------------

## The template's text for [param entries] (from [method extract]).
static func render_pot(entries: Array) -> String:
	var out := "# The game's text in English: the template each locale/<lang>.po\n# translates (NOTES.md → C16). Written by tests/locale/write_pot.gd\n# from the code; don't edit it by hand.\n" + _HEADER
	for e: Dictionary in entries:
		out += "\n"
		for c: String in e["comments"]:
			out += "#. %s\n" % c
		for f: String in e["files"]:
			out += "#: %s\n" % f
		if not e["ctx"].is_empty():
			out += _field("msgctxt", e["ctx"])
		out += _field("msgid", e["id"])
		if e["plural"].is_empty():
			out += "msgstr \"\"\n"
		else:
			out += _field("msgid_plural", e["plural"])
			out += "msgstr[0] \"\"\nmsgstr[1] \"\"\n"
	return out


## The made-up language's PO file ([constant PSEUDO_LOCALE]): every entry
## of [param entries] as ⟦English⟧, its placeholders kept.
static func render_pseudo(entries: Array) -> String:
	var out := _HEADER + "\"Language: %s\\n\"\n\"Plural-Forms: nplurals=2; plural=(n != 1);\\n\"\n" % PSEUDO_LOCALE
	for e: Dictionary in entries:
		out += "\n"
		if not e["ctx"].is_empty():
			out += _field("msgctxt", e["ctx"])
		out += _field("msgid", e["id"])
		if e["plural"].is_empty():
			out += _field("msgstr", OPEN + e["id"] + CLOSE)
		else:
			out += _field("msgid_plural", e["plural"])
			out += _field("msgstr[0]", OPEN + e["id"] + CLOSE)
			out += _field("msgstr[1]", OPEN + e["plural"] + CLOSE)
	return out


# A PO field: one line, or "" then a line per "\n" for text with several.
static func _field(name: String, text: String) -> String:
	var parts := text.split("\n")
	if parts.size() == 1:
		return "%s \"%s\"\n" % [name, _escape(text)]
	var out := "%s \"\"\n" % name
	for k in parts.size():
		var part := parts[k] + ("\n" if k < parts.size() - 1 else "")
		if not part.is_empty():
			out += "\"%s\"\n" % _escape(part)
	return out


static func _escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")


# --- PO files ----------------------------------------------------------

## A PO (or POT) file's entries: {header: name → value, entries: Array of
## {ctx, id, plural, strs: Array of String, fuzzy, line}, obsolete: how
## many "#~" entries, errors: Array of String}.
static func parse_po(text: String) -> Dictionary:
	var out := {"header": {}, "entries": [], "obsolete": 0, "errors": []}
	var lines := text.replace("\r\n", "\n").split("\n")
	var e := {}
	var field := "" # the field the next "…" line continues
	for k in lines.size():
		var line := lines[k].strip_edges()
		if line.is_empty():
			_finish(e, out)
			e = {}
			field = ""
			continue
		if e.is_empty():
			e = {"ctx": "", "plural": "", "strs": [], "fuzzy": false, "obsolete": false, "line": k + 1}
		if line.begins_with("#~"):
			e["obsolete"] = true
			continue
		if line.begins_with("#,"):
			for flag in line.substr(2).split(","):
				e["fuzzy"] = e["fuzzy"] or flag.strip_edges() == "fuzzy"
			continue
		if line.begins_with("#"):
			continue
		var name := field if line.begins_with("\"") else line.get_slice(" ", 0)
		var value := line if line.begins_with("\"") else line.substr(name.length()).strip_edges()
		var s: Variant = _unquote(value)
		if s == null:
			out["errors"].append("line %d: not a quoted string: %s" % [k + 1, line])
			continue
		var more := name == field # a line continuing the field
		if name == "msgctxt":
			e["ctx"] = (e["ctx"] if more else "") + s
		elif name == "msgid":
			e["id"] = (e.get("id", "") if more else "") + s
		elif name == "msgid_plural":
			e["plural"] = (e["plural"] if more else "") + s
		elif name == "msgstr" or name.begins_with("msgstr["):
			var index := 0 if name == "msgstr" else name.trim_prefix("msgstr[").trim_suffix("]").to_int()
			var strs: Array = e["strs"]
			while strs.size() <= index:
				strs.append("")
			strs[index] = (strs[index] if more else "") + s
		else:
			out["errors"].append("line %d: unknown field %s" % [k + 1, name])
			continue
		field = name
	_finish(e, out)
	return out


# Adds the entry [param e] (once read) to [param out]: the header's fields,
# or an entry; an obsolete one only counted.
static func _finish(e: Dictionary, out: Dictionary) -> void:
	if e.is_empty():
		return
	if e["obsolete"]:
		out["obsolete"] += 1
	elif not e.has("id"):
		out["errors"].append("line %d: an entry without msgid" % e["line"])
	elif e["id"].is_empty() and e["ctx"].is_empty():
		var body: String = e["strs"][0] if not e["strs"].is_empty() else ""
		for h in body.split("\n", false):
			var colon := h.find(":")
			if colon > 0:
				out["header"][h.substr(0, colon).strip_edges()] = h.substr(colon + 1).strip_edges()
	else:
		e.erase("obsolete")
		out["entries"].append(e)


static func _unquote(v: String) -> Variant:
	if v.length() < 2 or not v.begins_with("\"") or not v.ends_with("\""):
		return null
	var lexed := _string(v, 0, false, false)
	if not lexed.has("text") or lexed["end"] != v.length():
		return null
	return lexed["text"]


## Checks a language's PO text against the template's [param entries]:
## {errors, translated, total, fuzzy}. Errors: its own parse errors, a
## plural entry with the wrong number of forms (the header's nplurals),
## a translation without the English placeholders ({name} and % ones) or
## with others, and stale entries (not in the template; "#~" ones are
## fine). Untranslated and fuzzy ones are coverage, not errors: they show
## English. A plural's forms may leave a placeholder out, but the last.
static func check_po(text: String, entries: Array) -> Dictionary:
	var po := parse_po(text)
	var errors: Array = po["errors"].duplicate()
	var known := {}
	for e: Dictionary in entries:
		known[key_of(e["ctx"], e["id"])] = e
	var plurals := -1
	var rule: String = po["header"].get("Plural-Forms", "")
	var m := RegEx.create_from_string("nplurals\\s*=\\s*(\\d+)").search(rule)
	if m:
		plurals = m.get_string(1).to_int()
	var translated := 0
	var fuzzy := 0
	for e: Dictionary in po["entries"]:
		var where := "line %d (\"%s\")" % [e["line"], e["id"]]
		var english: Variant = known.get(key_of(e["ctx"], e["id"]))
		if english == null:
			errors.append("%s: stale, not in the template" % where)
			continue
		var strs: Array = e["strs"]
		if not english["plural"].is_empty():
			if plurals < 0:
				errors.append("%s: a plural, but the header has no nplurals" % where)
				continue
			if strs.size() != plurals and not (strs.size() == 1 and strs[0].is_empty()):
				errors.append("%s: %d plural forms, the header says %d" % [where, strs.size(), plurals])
				continue
		if strs.is_empty() or strs.all(func(s: String) -> bool: return s.is_empty()):
			continue
		if e["fuzzy"]:
			fuzzy += 1
			continue
		var wanted := _specs(english["id"]) if english["plural"].is_empty() else _specs(english["plural"])
		var bad := false
		for k in strs.size():
			var got := _specs(strs[k])
			var last := k == strs.size() - 1
			if english["plural"].is_empty() or last:
				bad = bad or got != wanted
			else:
				bad = bad or not got.all(func(p: String) -> bool: return p in wanted)
		if bad:
			errors.append("%s: its placeholders differ from English's (%s)" % [where, ", ".join(wanted)])
			continue
		translated += 1
	return {"errors": errors, "translated": translated, "total": entries.size(), "fuzzy": fuzzy}


# A text's placeholders: {name} ones sorted (a language may reorder them),
# then % ones in order (they can't be).
static func _specs(text: String) -> Array:
	var names := Array(Languages.placeholders(text))
	names.sort()
	var out := names.map(func(p: String) -> String: return "{%s}" % p)
	for found in RegEx.create_from_string("%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[sdifxXoc%v]").search_all(text):
		if found.get_string() != "%%":
			out.append(found.get_string())
	return out
