extends SceneTree
## Headless test for C16's groundwork: the extractor (tests/locale/pot.gd)
## on made-up code, locale/messages.pot up to date with the game's code,
## every top-level folder either read for text or known not to hold any,
## the PO checker on made-up files, every shipped .po listed, loading and
## passing it, the made-up ⟦English⟧ language, and Languages: shipped
## languages, their own names, Automatic, applying one, the Language
## setting, content marking and fill.
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
		Pot.key_of("", "Snow ❄"): "",
		Pot.key_of("", "From a scene"): "", Pot.key_of("", "Two\nlines \"quoted\""): "",
	}
	var missing := want.keys().filter(func(k: String) -> bool: return not got.has(k)).map(func(k: String) -> String: return k.replace("\u0004", "|"))
	var extra := got.keys().filter(func(k: String) -> bool: return not want.has(k)).map(func(k: String) -> String: return k.replace("\u0004", "|"))
	_check(missing.is_empty(), "the extractor takes tr/tr_n/atr/translate_plural literals with contexts and plurals, shown properties, add_item, marked lines (key-like strings left out), escapes, raw and long strings, and scene text (missing: %s)" % [missing])
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


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
