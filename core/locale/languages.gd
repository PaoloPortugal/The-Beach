class_name Languages
extends RefCounted
## The game's languages (C16). Godot's [TranslationServer] does the work:
## the keys are the English text, so English needs no file and a string
## with no translation shows in English. Each shipped language is a
## [code]locale/<lang>.po[/code] listed in the project's translations
## ([code]internationalization/locale/translations[/code]); the template
## is [code]locale/messages.pot[/code], written by
## [code]tests/locale/write_pot.gd[/code].
##
## Text set once on a Label or Button stays English in code and is shown
## translated by Godot's auto-translate. Text that is formatted goes
## through [method Object.tr] / [method Object.tr_n] with named
## placeholders, on a control with auto-translate off, redrawn on
## [constant Node.NOTIFICATION_TRANSLATION_CHANGED]. Content (chat, session
## titles, paths, product names) is never translated: [method content].

## The language setting's default: the system's language if shipped,
## else English.
const AUTOMATIC := "auto"
const ENGLISH := "en"
## In each language's PO file, the language's own name ("Deutsch"), so
## the Language row can list it under it.
# TRANSLATORS: your language's own name, as the settings list it: "Deutsch", "日本語".
const OWN_NAME := "This language's name, in this language" # TRANSLATE: language
const OWN_NAME_CONTEXT := "language"
## The meta a content control carries, for [method is_content].
const CONTENT := &"content"


## The shipped languages: English, then each loaded translation's, in
## the order of their codes.
static func shipped() -> PackedStringArray:
	var out := PackedStringArray([ENGLISH])
	var others := Array(TranslationServer.get_loaded_locales())
	others.sort()
	for locale: String in others:
		if TranslationServer.compare_locales(locale, ENGLISH) < 5: # English is the keys
			out.append(locale)
	return out


## The language [param choice] (a setting's value: [constant AUTOMATIC]
## or a locale) stands for: a shipped one, else English.
static func resolve(choice: String, system := OS.get_locale_language()) -> String:
	var wanted := system if choice == AUTOMATIC else choice
	var best := ENGLISH
	var best_score := 0
	for locale in shipped():
		var score := TranslationServer.compare_locales(wanted, locale)
		if score > best_score:
			best = locale
			best_score = score
	return best


## Shows the game in [param choice]'s language (see [method resolve]).
## Every node hears [constant Node.NOTIFICATION_TRANSLATION_CHANGED].
static func apply(choice: String) -> void:
	var locale := resolve(choice)
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)


## A language's own name: its PO file's [constant OWN_NAME], else Godot's
## (English) name for it.
static func own_name(locale: String) -> String:
	if locale == ENGLISH:
		return "English"
	var t := TranslationServer.get_translation_object(locale)
	if t != null and t.get_locale() == locale:
		var name := String(t.get_message(OWN_NAME, OWN_NAME_CONTEXT))
		if not name.is_empty():
			return name
	return TranslationServer.get_locale_name(locale)


## Marks [param node] and everything under it as content: never
## auto-translated, so a session titled "Settings" still says so. A child
## that is the game's own text sets [code]AUTO_TRANSLATE_MODE_ALWAYS[/code]
## (a code block's Copy).
static func content(node: Node) -> Node:
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.set_meta(CONTENT, true)
	return node


## Whether [param node] shows content ([method content]): it or the
## nearest of its parents that says either way.
static func is_content(node: Node) -> bool:
	while node != null:
		if node.has_meta(CONTENT):
			return true
		if node.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_ALWAYS:
			return false
		node = node.get_parent()
	return false


## Text already translated in code ([method Object.tr]): auto-translate
## off, so it isn't looked up again; the node redraws it itself.
static func translated(control: Node) -> Node:
	control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return control


## [param text] (a translated string) with each [code]{name}[/code] replaced
## by [param values]' [code]name[/code], in one pass: unlike
## [method String.format], a value that itself holds "{name}" (a session
## title, a path) is left as it is. Unknown names stay.
static func fill(text: String, values: Dictionary) -> String:
	var out := ""
	var at := 0
	for m in _placeholder().search_all(text):
		var key := m.get_string(1)
		if values.has(key):
			out += text.substr(at, m.get_start() - at) + str(values[key])
			at = m.get_end()
	return out + text.substr(at)


## The [code]{name}[/code] placeholders in [param text], in order.
static func placeholders(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _placeholder().search_all(text):
		out.append(m.get_string(1))
	return out


static func _placeholder() -> RegEx:
	return RegEx.create_from_string("\\{([A-Za-z_][A-Za-z0-9_]*)\\}")


## [param text] (digits, a decimal point) in the language's own digits.
static func number(text: String) -> String:
	return TextServerManager.get_primary_interface().format_number(text, TranslationServer.get_locale())
