extends SceneTree
## Headless test for C16's groundwork: the extractor (tests/locale/pot.gd)
## on made-up code, locale/messages.pot up to date with the game's code,
## every top-level folder either read for text or known not to hold any,
## the PO checker on made-up files, every shipped .po listed, loading and
## passing it, the made-up ⟦English⟧ language, and Languages: shipped
## languages, their own names, Automatic, applying one, the Language
## setting, content marking and fill; SidecarText's words for the
## sidecar's reasons and kinds (C16 step 6).
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/locale/locale_test.gd

const ErrorWatch := preload("res://tests/error_watch.gd")
const Pot := preload("res://tests/locale/pot.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_extractor()
	_template()
	_folders()
	_checker()
	_shipped()
	_pseudo()
	_languages()
	_setting()
	_content()
	_fill()
	_sidecar_text()
	if not _failed and _errors.ok():
		print("PASS locale_test")
		quit(0)


func _extractor() -> void:
	var gd := "\n".join([
		"extends Node",
		"const NAMES := [\"Beach\", \"graphics/vsync\", \"Ölberg\"] # TRANSLATE: biome",
		"const KEYS := {\"confirm_in_terminal\": \"Confirm it.\"} # TRANSLATE",
		"# TRANSLATORS: a button that starts the game",
		"const PLAY := \"Play\" # TRANSLATE",
		"func _ready() -> void:",
		"\tvar a := tr(\"One\")",
		"\tvar b := tr(\"Close\", \"action\")",
		"\tvar c := tr_n(\"{n} cat\", \"{n} cats\", 3)",
		"\tvar d := TranslationServer.translate_plural(\"{n} dog\", \"{n} dogs\", 2, \"pets\")",
		"\tvar e := atr(\"Esc \\\"quoted\\\"\\nnext\")",
		"\tvar f := tr(some_text)",
		"\tvar g := tr(\"Not \" + \"joined\")",
		"\tvar h := tr(\"Known\", context_var)",
		"\t$Label.text = \"Shown\"",
		"\t$Label.text = \"Not\" if a else \"either\"",
		"\t$Label.tooltip_text = \"Tip\"",
		"\tvar text = \"a local, not a property\"",
		"\tif text == \"Compared\":",
		"\t\tpass",
		"\t$Option.add_item(\"Item\")",
		"\t$Label.text = \"30\"",
		"\t$Label.text = \"Debug only\" # NO_TRANSLATE",
		"\tprint(\"# not a comment\", \"Unmarked\")",
		"\tvar r := r\"raw \\\" stays\" # TRANSLATE",
		"\tvar np := ^\"Path/To\" # TRANSLATE",
		"\tvar long := tr(\"\"\"Several",
		"lines\"\"\")",
		"\tvar u := tr(\"Snow \\u2744\")",
		"\tvar w := tr(\"{month} {day}\", \"time\")",
	])
	var tscn := "\n".join([
		"[gd_scene format=3]",
		"[node name=\"A\" type=\"Label\"]",
		"text = \"From a scene\"",
		"[node name=\"B\" type=\"Label\" parent=\".\"]",
		"auto_translate_mode = 2",
		"text = \"Content in a scene\"",
		"[node name=\"C\" type=\"Label\" parent=\".\"]",
		"placeholder_text = \"Two",
		"lines \\\"quoted\\\"\"",
	])
	var found := Pot.extract({"x/a.gd": gd, "x/b.tscn": tscn, "x/c.gd": "func f():\n\ttr(\"One\")\n\ttr_n(\"{n} cat\", \"{n} cats\", 1)\n"})
	_check(found["errors"].is_empty(), "the made-up code reads without errors (%s)" % [found["errors"]])
	var got := {}
	for e: Dictionary in found["entries"]:
		got[Pot.key_of(e["ctx"], e["id"])] = e
	var want := {
		Pot.key_of("biome", "Beach"): "", Pot.key_of("biome", "Ölberg"): "",
		Pot.key_of("", "Confirm it."): "", Pot.key_of("", "Play"): "",
		Pot.key_of("", "One"): "", Pot.key_of("action", "Close"): "",
		Pot.key_of("", "{n} cat"): "{n} cats", Pot.key_of("pets", "{n} dog"): "{n} dogs",
		Pot.key_of("", "Esc \"quoted\"\nnext"): "", Pot.key_of("", "Shown"): "",
		Pot.key_of("", "Tip"): "", Pot.key_of("", "Item"): "",
		Pot.key_of("", "raw \\\" stays"): "", Pot.key_of("", "Several\nlines"): "",
		Pot.key_of("", "Snow ❄"): "", Pot.key_of("time", "{month} {day}"): "",
		Pot.key_of("", "From a scene"): "", Pot.key_of("", "Two\nlines \"quoted\""): "",
	}
	var missing := want.keys().filter(func(k: String) -> bool: return not got.has(k)).map(func(k: String) -> String: return k.replace("\u0004", "|"))
	var extra := got.keys().filter(func(k: String) -> bool: return not want.has(k)).map(func(k: String) -> String: return k.replace("\u0004", "|"))
	_check(missing.is_empty(), "the extractor takes tr/tr_n/atr/translate_plural literals with contexts and plurals, shown properties, add_item, marked lines (key-like strings left out), escapes, raw and long strings, scene text, and placeholders to order (missing: %s)" % [missing])
	_check(extra.is_empty(), "and nothing else: no variables, joined strings, unknown contexts, conditionals, locals, comparisons, unmarked strings, node paths, NO_TRANSLATE lines, text without letters or nodes with auto-translate off (extra: %s)" % [extra])
	var plural_ok := want.keys().all(func(k: String) -> bool: return not got.has(k) or got[k]["plural"] == want[k])
	_check(plural_ok, "each with its plural")
	var cat: Dictionary = got.get(Pot.key_of("", "{n} cat"), {})
	_check(cat.get("files") == ["x/a.gd", "x/c.gd"], "an entry lists every file it's in, once (%s)" % [cat.get("files")])
	_check(got.get(Pot.key_of("", "Play"), {}).get("comments") == ["a button that starts the game"], "a TRANSLATORS comment goes with the next line's strings")
	var order: Array = found["entries"].map(func(e: Dictionary) -> String: return e["id"])
	_check(order.slice(0, 3) == ["Beach", "Ölberg", "Confirm it."], "entries in the order they come")
	var conflict := Pot.extract({"a.gd": "func f():\n\ttr_n(\"{n} x\", \"{n} xs\", 1)\n\ttr_n(\"{n} x\", \"{n} xes\", 2)\n"})
	_check(conflict["errors"].size() == 1, "two plurals for one text is an error")
	var bad := Pot.extract({"a.gd": "var s := \"never closed\n"})
	_check(bad["errors"].size() == 1, "an unclosed string is an error")
	var pot := Pot.render_pot(found["entries"])
	_check(pot.contains("#. a button that starts the game\n#: x/a.gd\nmsgid \"Play\"\nmsgstr \"\"\n"), "the template: comment, files, text")
	_check(pot.contains("msgctxt \"pets\"\nmsgid \"{n} dog\"\nmsgid_plural \"{n} dogs\"\nmsgstr[0] \"\"\nmsgstr[1] \"\"\n"), "a context and a plural")
	_check(pot.contains("msgid \"\"\n\"Esc \\\"quoted\\\"\\n\"\n\"next\"\n"), "text over several lines, escaped")
	var back := Pot.parse_po(pot)
	var round_trip: bool = back["errors"].is_empty() and back["entries"].size() == found["entries"].size()
	for k in mini(back["entries"].size(), found["entries"].size()):
		var a: Dictionary = back["entries"][k]
		var b: Dictionary = found["entries"][k]
		round_trip = round_trip and a["id"] == b["id"] and a["ctx"] == b["ctx"] and a["plural"] == b["plural"]
	_check(round_trip, "the template reads back as it was written")
	_check(back["header"].get("Content-Type") == "text/plain; charset=UTF-8", "with its header")


func _template() -> void:
	var found := Pot.extract_project()
	_check(found["errors"].is_empty(), "the game's code reads without errors (%s)" % [found["errors"]])
	var on_disk := FileAccess.get_file_as_string(Pot.POT_PATH)
	_check(on_disk == Pot.render_pot(found["entries"]), "locale/messages.pot is up to date with the code (else run tests/locale/write_pot.gd)")
	_check(not on_disk.contains(ProjectSettings.get_setting("application/config/name")), "the template doesn't hold the codename")
	var ids: Array = found["entries"].map(func(e: Dictionary) -> String: return Pot.key_of(e["ctx"], e["id"]))
	_check(Pot.key_of("", "Settings") in ids and Pot.key_of("biome", "Forest") in ids and Pot.key_of(Languages.OWN_NAME_CONTEXT, Languages.OWN_NAME) in ids and Pot.key_of("", "Hold Tab for sessions") in ids, "it has the menus' text, the biomes', the language's own name and the scenes'")
	var debug: Array = found["entries"].filter(func(e: Dictionary) -> bool: return e["files"].any(func(f: String) -> bool: return f.begins_with("world/debug/")))
	_check(debug.is_empty(), "but not the debug commands' (C09)")


func _folders() -> void:
	var unknown := []
	for d in DirAccess.get_directories_at("res://"):
		if not d.begins_with(".") and not d in Pot.ROOTS and not d in Pot.NOT_GAME:
			unknown.append(d)
	_check(unknown.is_empty(), "every top-level folder is read for text or known to hold none (new: %s; add it to pot.gd's ROOTS or NOT_GAME)" % [unknown])


func _checker() -> void:
	var entries := [
		{"ctx": "", "id": "Play", "plural": ""},
		{"ctx": "", "id": "Choose {program}", "plural": ""},
		{"ctx": "", "id": "%d%% done", "plural": ""},
		{"ctx": "", "id": "{n} cat", "plural": "{n} cats"},
		{"ctx": "biome", "id": "Beach", "plural": ""},
		{"ctx": "", "id": "Untouched", "plural": ""},
	]
	var head := "msgid \"\"\nmsgstr \"\"\n\"Language: de\\n\"\n\"Plural-Forms: nplurals=2; plural=(n != 1);\\n\"\n\n"
	var good := head + "\n\n".join([
		"msgid \"Play\"\nmsgstr \"Spielen\"",
		"msgid \"Choose {program}\"\nmsgstr \"{program} wählen\"",
		"msgid \"%d%% done\"\nmsgstr \"%d%% fertig\"",
		"msgid \"{n} cat\"\nmsgid_plural \"{n} cats\"\nmsgstr[0] \"Eine Katze\"\nmsgstr[1] \"{n} Katzen\"",
		"#, fuzzy\nmsgctxt \"biome\"\nmsgid \"Beach\"\nmsgstr \"Strand\"",
		"#~ msgid \"Gone\"\n#~ msgstr \"Weg\"",
	])
	var r := Pot.check_po(good, entries)
	_check(r["errors"].is_empty(), "a good PO file passes (%s)" % [r["errors"]])
	_check(r["translated"] == 4 and r["fuzzy"] == 1 and r["total"] == 6, "coverage: 4 of 6 translated, 1 fuzzy (fuzzy and missing ones show English); obsolete ones are fine")
	var crlf := Pot.check_po(good.replace("\n", "\r\n"), entries)
	var crlf_po := Pot.parse_po(good.replace("\n", "\r\n"))
	_check(crlf["errors"].is_empty() and crlf["translated"] == 4 and crlf_po["header"].get("Language") == "de", "and the same file with Windows line endings (%s)" % [crlf["errors"]])
	var cases := {
		"stale": "msgid \"Gone\"\nmsgstr \"Weg\"",
		"placeholder lost": "msgid \"Choose {program}\"\nmsgstr \"Wählen\"",
		"placeholder added": "msgid \"Play\"\nmsgstr \"Spielen {url}\"",
		"placeholder renamed": "msgid \"Choose {program}\"\nmsgstr \"{programm} wählen\"",
		"% lost": "msgid \"%d%% done\"\nmsgstr \"fertig\"",
		"last plural lost {n}": "msgid \"{n} cat\"\nmsgid_plural \"{n} cats\"\nmsgstr[0] \"{n} Katze\"\nmsgstr[1] \"Katzen\"",
		"plural count": "msgid \"{n} cat\"\nmsgid_plural \"{n} cats\"\nmsgstr[0] \"Katze\"\nmsgstr[1] \"{n} Katzen\"\nmsgstr[2] \"{n} Katzen\"",
		"not quoted": "msgid \"Play\"\nmsgstr Spielen",
	}
	for what: String in cases:
		var bad := Pot.check_po(head + cases[what], entries)
		_check(bad["errors"].size() == 1, "the checker fails a PO file: %s (%s)" % [what, bad["errors"]])
	var no_rule := Pot.check_po("msgid \"\"\nmsgstr \"\"\n\"Language: de\\n\"\n\nmsgid \"{n} cat\"\nmsgid_plural \"{n} cats\"\nmsgstr[0] \"{n} Katze\"\nmsgstr[1] \"{n} Katzen\"", entries)
	_check(no_rule["errors"].size() == 1, "and a plural without the header's Plural-Forms")


# Every .po in locale/ is in the project's translations, loads, and
# passes the checker against the template; their coverage is printed.
func _shipped() -> void:
	_check(ProjectSettings.get_setting("internationalization/locale/fallback") == "en", "the fallback language is English")
	var listed := Array(ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()))
	var template := Pot.parse_po(FileAccess.get_file_as_string(Pot.POT_PATH))
	_check(template["errors"].is_empty(), "the template reads as a PO file")
	var on_disk := []
	for f in DirAccess.get_files_at("res://locale"):
		if f.ends_with(".po"):
			on_disk.append("res://locale/" + f)
	_check(on_disk.all(func(p: String) -> bool: return p in listed) and listed.all(func(p: String) -> bool: return p in on_disk), "every locale/*.po is listed in the project's translations, and only those (%s, %s)" % [on_disk, listed])
	_check(not FileAccess.file_exists("res://locale/en.po"), "no en.po: the template is the English")
	for p: String in on_disk:
		var t: Translation = load(p)
		_check(t != null and not t.get_locale().is_empty(), "%s loads, with its language" % p)
		var r := Pot.check_po(FileAccess.get_file_as_string(p), template["entries"])
		_check(r["errors"].is_empty(), "%s passes the checker (%s)" % [p, r["errors"]])
		print("  %s: %d of %d translated, %d fuzzy" % [p, r["translated"], r["total"], r["fuzzy"]])


func _pseudo() -> void:
	var template: Array = Pot.parse_po(FileAccess.get_file_as_string(Pot.POT_PATH))["entries"]
	var text := Pot.render_pseudo(template)
	var r := Pot.check_po(text, template)
	_check(r["errors"].is_empty() and r["translated"] == template.size(), "the made-up language passes the checker, every entry translated (%s)" % [r["errors"]])
	var t := pseudo_translation()
	_check(t != null and t.get_locale() == Pot.PSEUDO_LOCALE, "and loads as a translation")
	if t == null:
		return
	_check(t.get_message("Settings") == "⟦Settings⟧" and t.get_message("Forest", "biome") == "⟦Forest⟧", "showing ⟦English⟧, under its contexts")
	_check(t.get_plural_message("{n} session is still running:", "{n} sessions are still running:", 3) == "⟦{n} sessions are still running:⟧", "and plurals")


## The made-up language (Pot.PSEUDO_LOCALE): every entry of the template
## as ⟦English⟧, loaded from a PO file as a real language would be. For
## the world test too.
static func pseudo_translation() -> Translation:
	var template: Array = Pot.parse_po(FileAccess.get_file_as_string(Pot.POT_PATH))["entries"]
	var path := "user://test-pseudo-%d.po" % OS.get_process_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(Pot.render_pseudo(template))
	f.close()
	var t: Translation = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return t


func _languages() -> void:
	_check(Array(Languages.shipped()) == ["en"], "only English ships for now")
	_check(Languages.resolve(Languages.AUTOMATIC, "de") == "en" and Languages.resolve("de") == "en", "a language not shipped is English")
	_check(Languages.own_name("en") == "English" and Languages.own_name("fr") == TranslationServer.get_locale_name("fr"), "own names: English's, and Godot's for a language without its own")
	var de := Translation.new()
	de.locale = "de"
	de.add_message(Languages.OWN_NAME, "Deutsch", Languages.OWN_NAME_CONTEXT)
	de.add_message("Play", "Spielen")
	TranslationServer.add_translation(de)
	_check(Array(Languages.shipped()) == ["en", "de"], "a loaded language ships")
	_check(Languages.own_name("de") == "Deutsch", "under its own name, from its PO file")
	_check(Languages.resolve(Languages.AUTOMATIC, "de_AT") == "de" and Languages.resolve(Languages.AUTOMATIC, "de") == "de", "Automatic: the system's language, its region aside")
	_check(Languages.resolve(Languages.AUTOMATIC, "fr_FR") == "en", "else English")
	_check(Languages.resolve("de", "fr") == "de" and Languages.resolve("en", "de") == "en", "a chosen language whatever the system's")
	var node := Node.new()
	Languages.apply("de")
	_check(TranslationServer.get_locale() == "de" and node.tr("Play") == "Spielen", "applying it shows the game in it")
	Languages.apply("en")
	_check(TranslationServer.get_locale() == "en" and node.tr("Play") == "Play", "and back to English")
	node.free()
	TranslationServer.remove_translation(de)
	_check(Array(Languages.shipped()) == ["en"], "(the language removed again)")


func _setting() -> void:
	var path := "user://locale_test_settings_%d.cfg" % OS.get_process_id()
	var s := Settings.new()
	s.path = path
	_check(s.value("game/language") == Languages.AUTOMATIC, "the Language setting is Automatic by default")
	s.set_value("game/language", "de")
	_check(s.value("game/language") == Languages.AUTOMATIC, "a language not shipped can't be chosen")
	s.set_value("game/language", "en")
	_check(s.value("game/language") == "en", "a shipped one can")
	var cfg := ConfigFile.new()
	cfg.set_value("game", "language", "xx")
	cfg.save(path)
	s.load_file()
	_check(s.value("game/language") == Languages.AUTOMATIC, "a saved language no longer shipped is Automatic")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _content() -> void:
	var box := VBoxContainer.new()
	var title := Label.new()
	box.add_child(title)
	var copy := Button.new()
	box.add_child(copy)
	var mine := Label.new()
	copy.add_child(mine)
	Languages.content(box)
	copy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	root.add_child(box)
	_check(Languages.is_content(box) and Languages.is_content(title) and not title.can_auto_translate(), "content isn't auto-translated, nor what's under it")
	_check(not Languages.is_content(copy) and not Languages.is_content(mine) and copy.can_auto_translate(), "but for the game's own text in it, set to always")
	var plain := Label.new()
	Languages.translated(plain)
	root.add_child(plain)
	_check(not Languages.is_content(plain) and not plain.can_auto_translate(), "text translated in code: auto-translate off, not content")
	box.free()
	plain.free()


func _fill() -> void:
	_check(Languages.fill("Choose {program}", {"program": "Claude Code"}) == "Choose Claude Code", "fill: a placeholder filled")
	_check(Languages.fill("{a} and {b}", {"a": "{b}", "b": "x"}) == "{b} and x", "in one pass: a value holding {name} stays as it is")
	_check(Languages.fill("{a} {unknown}", {"a": 1}) == "1 {unknown}", "an unknown name stays")
	_check(Array(Languages.placeholders("{b} then {a}, {b}")) == ["b", "a", "b"], "placeholders, in order")


# C16 step 6: in English, each reason and kind worded by SidecarText reads
# as the sidecar's own English message or label (copied from sidecar/src:
# claude/session.ts, index.ts, find.ts, hooks.ts, prompt-options.ts and
# sidecar/test/prompt-options.test.ts); anything else falls back to it.
func _sidecar_text() -> void:
	var claude := {"provider": "claude", "name": "Claude Code", "capabilities": {"program_path": {"program": "claude"}}}
	var err := func(reason: String, message: String, details := {}) -> String:
		return SidecarText.error({"type": "error", "code": "provider_error", "message": message, "reason": reason, "details": details}, claude)
	var same := {
		"read_only": "This session is read-only here; use its terminal.",
		"conversation_moved": "This conversation moved to another Claude Code session; continue it in the terminal.",
		"unreachable": "The world can't reach this conversation right now (its channel to Claude Code is closed); use the terminal.",
		"option_unavailable": "This prompt can't be answered that way right now. Answer Yes or No, or answer in the terminal.",
		"question_not_waiting": "The question is no longer waiting for an answer.",
		"plan_not_waiting": "The plan is no longer waiting for an answer.",
		"already_open": "That session is already open.",
		"still_running": "That session is still running in a terminal. Continue it there, or type /exit in it and resume it again.",
		"not_found": "That session wasn't found. Claude Code may have deleted it.",
		"no_terminal": "No terminal window could be opened to run Claude Code.",
	}
	var all_same := true
	for reason: String in same:
		# A made-up message, so only our wording can match.
		var said: String = err.call(reason, "(the sidecar's)")
		if said != same[reason]:
			all_same = false
			printerr("  %s: %s" % [reason, said])
	_check(all_same, "SidecarText: each session reason in English reads as the sidecar's message")
	_check(err.call("project_gone", "x", {"path": "C:\\p\\{n}"}) == "Its project folder no longer exists: C:\\p\\{n}", "a detail filled in as written, a path holding {n} too")
	_check(err.call("project_gone", "Its project folder no longer exists: /p") == "Its project folder no longer exists: /p", "a reason whose detail is missing: the sidecar's message")
	_check(err.call("something_new", "The sidecar's words.") == "The sidecar's words.", "an unknown reason: the sidecar's message")
	_check(SidecarText.error({"code": "provider_error", "message": "Free words."}, claude) == "Free words.", "no reason: the message")
	_check(SidecarText.error({"code": "unknown_session", "message": "unknown session s1"}) == "That session has ended.", "no reason, a code of one meaning: ours")
	_check(SidecarText.error({"code": "unknown_session", "reason": "something_new", "message": "Free words."}) == "Free words.", "an unknown reason wins over the code")
	_check(SidecarText.error({"code": "provider_error", "reason": "not_found", "message": "M"}) == "M", "without the provider's name from hello: the message")
	_check(SidecarText.error({"code": "not_supported", "reason": "end_in_terminal", "message": "end the session with /exit in its terminal"}) == "End the session with /exit in its terminal.", "end_in_terminal, as a sentence")
	_check(SidecarText.error({"code": "invalid_project", "reason": "no_such_folder", "message": "project folder does not exist"}) == "The project's folder doesn't exist.", "invalid_project, as a sentence")
	_check(SidecarText.error({"code": "disconnected", "reason": "not_running", "message": "x"}) == "The sidecar isn't running.", "Godot's own disconnected reasons")
	# The program (find.ts).
	var prog := func(reason: String, details := {}) -> String:
		return SidecarText.program({"path": null, "message": "(the sidecar's)", "reason": reason, "details": details}, claude)
	var windows := OS.get_name() == "Windows"
	var programs := {
		"not_full_path": ["That isn't a full path.", {}],
		"network_path": ["Choose a file on a drive of this computer (like C:\\...), not a network path.", {}],
		"no_file": ["There's no program at that path.", {}],
		"wrapper": ["Pick claude.exe itself: a .cmd or other wrapper can't be started without a shell.", {}],
		"not_the_program": ["That program didn't answer as Claude Code (claude --version).", {"version_command": "claude --version"}],
		"too_old": ["Claude Code 2.0.1 is too old; version 2.1.200 or newer is needed. Run `claude update`.", {"version": "2.0.1", "minimum": "2.1.200", "update_command": "claude update"}],
		"not_installed": ["Claude Code for Windows wasn't found. Install it from code.claude.com (the Windows version, not inside WSL) and sign in once in a terminal." if windows \
			else "Claude Code wasn't found. Install it from code.claude.com and sign in once in a terminal.", {"site": "code.claude.com"}],
	}
	all_same = true
	for reason: String in programs:
		var said: String = prog.call(reason, programs[reason][1])
		if said != programs[reason][0]:
			all_same = false
			printerr("  %s: %s" % [reason, said])
	_check(all_same, "each program reason in English reads as the sidecar's message")
	_check(prog.call("set_path_broken", {"why": "too_old", "version": "2.0.1", "minimum": "2.1.200", "update_command": "claude update"}) \
		== "The Claude Code set in Settings doesn't work: Claude Code 2.0.1 is too old; version 2.1.200 or newer is needed. Run `claude update`. Choose it again, or reset it.",
		"set_path_broken: around its why, with why's details")
	_check(prog.call("set_path_broken", {"why": "something_new"}) == "(the sidecar's)" and prog.call("set_path_broken", {"why": "set_path_broken"}) == "(the sidecar's)" \
		and prog.call("too_old", {"version": "2.0.1", "minimum": "2.1.200"}) == "(the sidecar's)" and prog.call("not_the_program") == "(the sidecar's)",
		"an unknown why, a looping one or a missing detail (the provider's command too): the message")
	_check(SidecarText.program({"path": null, "message": "M", "reason": "wrapper"}, {"name": "Claude Code"}) == "M", "{program} needs the provider's program_path")
	# Notices (hooks.ts, index.ts).
	var notices := [
		["signed_out", {"command": "/login"}, "Claude Code needs you to sign in again: run /login in its terminal."],
		["org_not_allowed", {"command": "/login"}, "Your organization doesn't allow this account in Claude Code: run /login in its terminal to sign in with another."],
		["cloud_credentials", {}, "Claude Code couldn't load your cloud provider's credentials: check its terminal."],
		["account_on_hold", {"account": "Claude"}, "Your Claude account is on hold: check Claude Code's terminal."],
		["billing", {}, "Claude Code reports a billing problem with your account: check its terminal."],
	]
	all_same = true
	for n: Array in notices:
		var said := SidecarText.notice({"code": "sign_in_needed", "message": "(the sidecar's)", "reason": n[0], "details": n[1]}, claude)
		if said != n[2]:
			all_same = false
			printerr("  %s: %s" % [n[0], said])
	_check(all_same, "each sign-in reason in English reads as the sidecar's message")
	_check(SidecarText.notice({"code": "outside_sessions_off", "message": "M", "details": {"setting": "agent view"}}, claude) \
		== "Sessions started outside the game can't be shown: agent view is off in Claude Code.", "outside_sessions_off, the setting's name as it is")
	_check(SidecarText.notice({"code": "sign_in_needed", "message": "M", "reason": "signed_out"}, claude) == "M" \
		and SidecarText.notice({"code": "sign_in_needed", "message": "M"}, claude) == "M" \
		and SidecarText.notice({"code": "something_new", "message": "M", "reason": "billing"}, claude) == "M", "a missing detail, no reason or another code: the message")
	# Options (prompt-options.test.ts).
	var cwd := "C:\\Users\\me\\AppData\\Local\\Temp\\garden-live"
	var options := [
		[{"kind": "allow_commands", "parts": {"commands": ["npm test *", "make"]}}, "Yes, and don't ask again for: npm test *, make"],
		[{"kind": "switch_mode", "parts": {"mode": "acceptEdits"}}, "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session"],
		[{"kind": "switch_mode", "parts": {"mode": "auto"}}, "Yes, and switch to auto mode"],
		[{"kind": "read_folders", "parts": {"folders": ["/c/Users/me/outside-live"]}}, "Yes, allow reading from /c/Users/me/outside-live during this session"],
		[{"kind": "allow_folders_and_commands", "parts": {"folders": ["/c/Users/me/outside-live"], "commands": ["node -e \"1\""]}},
			"Yes, and allow access to /c/Users/me/outside-live and \"node -e \\\"1\\\"\" commands"],
		[{"kind": "allow_domain", "parts": {"domain": "example.com"}}, "Yes, and don't ask again for example.com"],
		[{"kind": "allow_web_search", "parts": {"folder": "~\\AppData\\Local\\Temp\\garden-live"}}, "Yes, and don't ask again for Web Search commands in ~\\AppData\\Local\\Temp\\garden-live"],
		[{"kind": "allow_folders", "parts": {"folders": [cwd, "/b"]}}, "Yes, and allow access to %s, /b during this session" % cwd],
	]
	all_same = true
	for o: Array in options:
		var opt: Dictionary = (o[0] as Dictionary).merged({"option": "suggested", "label": "(the sidecar's)"})
		if SidecarText.option(opt) != o[1] or not SidecarText.is_ours(opt):
			all_same = false
			printerr("  %s: %s" % [opt["kind"], SidecarText.option(opt)])
	_check(all_same, "each option kind in English reads as the sidecar's label, its parts word for word")
	_check(SidecarText.option({"option": "suggested", "kind": "switch_mode", "parts": {"mode": "plan"}, "label": "L"}) == "Yes, and switch to Plan mode" \
		and SidecarText.option({"option": "suggested", "kind": "switch_mode", "parts": {"mode": "newMode"}, "label": "L"}) == "Yes, and switch to newMode mode",
		"another mode: our name for it, or its id as it is")
	var label := "Yes, and always allow Bash(make) (saved in this project's .claude/settings.json)"
	_check(SidecarText.option({"option": "suggested", "label": label}) == label and not SidecarText.is_ours({"option": "suggested", "label": label}), "the stopgap, no kind: its label, not ours")
	_check(SidecarText.option({"kind": "something_new", "parts": {"x": "y"}, "label": "L"}) == "L" \
		and SidecarText.option({"kind": "allow_domain", "parts": {}, "label": "L"}) == "L" \
		and SidecarText.option({"kind": "allow_commands", "parts": {"commands": []}, "label": "L"}) == "L" \
		and SidecarText.option({"kind": "allow_commands", "parts": {"commands": [3]}, "label": "L"}) == "L" \
		and SidecarText.option({"kind": "switch_mode", "label": "L"}) == "L", "an unknown kind, missing, empty or odd parts: the label")
	_check(SidecarText.option({"kind": "allow_domain", "parts": {"domain": "{commands}.com"}, "label": "L"}) == "Yes, and don't ask again for {commands}.com", "a part holding a placeholder stays as written")
	# In a language, ours is translated, the provider's words as written.
	var zz := pseudo_translation()
	TranslationServer.add_translation(zz)
	TranslationServer.set_locale(Pot.PSEUDO_LOCALE)
	_check(err.call("project_gone", "x", {"path": "/Settings"}) == "⟦Its project folder no longer exists: /Settings⟧", "translated, a detail as written")
	_check(err.call("something_new", "Settings") == "Settings", "an unknown reason's message as written")
	_check(SidecarText.option({"kind": "allow_domain", "parts": {"domain": "Back"}, "label": "L"}) == "⟦Yes, and don't ask again for Back⟧", "an option translated, its part as written")
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(zz)


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
