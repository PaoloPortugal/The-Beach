class_name SidecarText
extends RefCounted
## Godot's own words for what the sidecar says in English (C16 step 6).
## The sidecar stays English and sends no locale: an error reply, a
## notice and a program not found carry a [code]reason[/code] (and the
## [code]details[/code] its text needs), a permission's option a
## [code]kind[/code] (and its [code]parts[/code]). Reasons and kinds we
## know are worded here and translated; any other shows the sidecar's
## English [code]message[/code] (or the option's [code]label[/code]) as it
## is. So is one whose text needs a value that didn't come.
##
## The provider's own words fill the placeholders as they are: its name
## ([code]{provider}[/code], from hello), its program's
## ([code]{program}[/code]), and the details and parts (paths, versions,
## rule patterns, domains, a command such as [code]/login[/code]), in one
## pass ([method Languages.fill]). The reasons look like keys, so each
## text is a literal [method TranslationServer.translate] (a
## [code]# TRANSLATE[/code] line would skip a line holding an id).

const LIST := ", "


## The words for an [code]error[/code] reply: ours for its reason (else
## its code) when we have them, else its English message. [param provider]
## is the provider's entry from hello ([method SidecarClient.provider]),
## or empty.
static func error(reply: Dictionary, provider := {}) -> String:
	var message := str(reply.get("message", ""))
	var reason := str(reply.get("reason", ""))
	var details: Dictionary = reply.get("details", {}) if reply.get("details") is Dictionary else {}
	var text := _reason_text(reason, details, provider) if not reason.is_empty() else ""
	if text.is_empty() and reason.is_empty():
		text = _code_text(str(reply.get("code", "")))
	return text if not text.is_empty() else message


## Why a provider's program wasn't found ([code]{path: null, message,
## reason?, details?}[/code]): ours for its reason, else its message.
static func program(found: Dictionary, provider := {}) -> String:
	var details: Dictionary = found.get("details", {}) if found.get("details") is Dictionary else {}
	var text := _reason_text(str(found.get("reason", "")), details, provider)
	return text if not text.is_empty() else str(found.get("message", ""))


## A notice's words, for the codes whose wording needs the provider's
## parts: [code]sign_in_needed[/code] by its reason,
## [code]outside_sessions_off[/code]. Any other, its message. (The chat's
## and the launcher's own codes are worded where they're shown.)
static func notice(n: Dictionary, provider := {}) -> String:
	var details: Dictionary = n.get("details", {}) if n.get("details") is Dictionary else {}
	var template := ""
	match str(n.get("code", "")):
		"sign_in_needed":
			match str(n.get("reason", "")):
				"signed_out":
					template = TranslationServer.translate("{provider} needs you to sign in again: run {command} in its terminal.")
				"org_not_allowed":
					template = TranslationServer.translate("Your organization doesn't allow this account in {provider}: run {command} in its terminal to sign in with another.")
				"cloud_credentials":
					template = TranslationServer.translate("{provider} couldn't load your cloud provider's credentials: check its terminal.")
				"account_on_hold":
					# TRANSLATORS: {account}: the provider's name for the account, e.g. "Claude".
					template = TranslationServer.translate("Your {account} account is on hold: check {provider}'s terminal.")
				"billing":
					template = TranslationServer.translate("{provider} reports a billing problem with your account: check its terminal.")
		"outside_sessions_off":
			# TRANSLATORS: {setting}: the provider's own name for a setting of its, e.g. "agent view".
			template = TranslationServer.translate("Sessions started outside the game can't be shown: {setting} is off in {provider}.")
	var text := _filled(template, details, provider)
	return text if not text.is_empty() else str(n.get("message", ""))


## A permission option's words: ours for its kind, the provider's parts
## (rule patterns, folders, a domain) word for word in them; else its
## label as it is. [method is_ours] says which.
static func option(o: Dictionary) -> String:
	var text := _option_text(o)
	return text if not text.is_empty() else str(o.get("label", ""))


## Whether [method option] words it (so it isn't the provider's label alone).
static func is_ours(o: Dictionary) -> bool:
	return not _option_text(o).is_empty()


static func _option_text(o: Dictionary) -> String:
	var parts: Dictionary = o.get("parts", {}) if o.get("parts") is Dictionary else {}
	var values := {}
	for name: String in parts:
		var v: Variant = parts[name]
		if v is String:
			values[name] = v
		elif v is Array and not (v as Array).is_empty() and (v as Array).all(func(x: Variant) -> bool: return x is String):
			# Commands beside folders are quoted, as the terminal shows them.
			var items: Array = v if not (name == "commands" and o.get("kind") == "allow_folders_and_commands") \
				else (v as Array).map(func(x: String) -> String: return JSON.stringify(x))
			values[name] = LIST.join(PackedStringArray(items))
	var template := ""
	match str(o.get("kind", "")):
		"switch_mode":
			match str(values.get("mode", "")):
				"auto":
					template = TranslationServer.translate("Yes, and switch to auto mode")
				"acceptEdits":
					template = TranslationServer.translate("Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session")
				"":
					return ""
				var mode:
					# Our name for the mode ("Plan"), or the provider's id as it is.
					return Languages.fill(TranslationServer.translate("Yes, and switch to {mode} mode"), {"mode": PermissionModes.name_of(mode)})
		"allow_commands":
			template = TranslationServer.translate("Yes, and don't ask again for: {commands}")
		"allow_folders":
			template = TranslationServer.translate("Yes, and allow access to {folders} during this session")
		"read_folders":
			template = TranslationServer.translate("Yes, allow reading from {folders} during this session")
		"allow_folders_and_commands":
			template = TranslationServer.translate("Yes, and allow access to {folders} and {commands} commands")
		"allow_domain":
			template = TranslationServer.translate("Yes, and don't ask again for {domain}")
		"allow_web_search":
			template = TranslationServer.translate("Yes, and don't ask again for Web Search commands in {folder}")
	return _filled_from(template, values)


# Ours for a reason, or "" (unknown, or a value its text needs is missing).
static func _reason_text(reason: String, details: Dictionary, provider: Dictionary) -> String:
	var template := ""
	match reason:
		# Ours ([SidecarClient]'s code disconnected): no sidecar, or it went.
		"not_running":
			template = TranslationServer.translate("The sidecar isn't running.")
		"dropped":
			template = TranslationServer.translate("the connection to the sidecar dropped, so it may not have arrived.")
		# The session's own.
		"read_only":
			template = TranslationServer.translate("This session is read-only here; use its terminal.")
		"conversation_moved":
			template = TranslationServer.translate("This conversation moved to another {provider} session; continue it in the terminal.")
		"unreachable":
			template = TranslationServer.translate("The world can't reach this conversation right now (its channel to {provider} is closed); use the terminal.")
		"option_unavailable":
			template = TranslationServer.translate("This prompt can't be answered that way right now. Answer Yes or No, or answer in the terminal.")
		"question_not_waiting":
			template = TranslationServer.translate("The question is no longer waiting for an answer.")
		"plan_not_waiting":
			template = TranslationServer.translate("The plan is no longer waiting for an answer.")
		"end_in_terminal":
			template = TranslationServer.translate("End the session with /exit in its terminal.")
		# Starting or resuming one.
		"already_open":
			template = TranslationServer.translate("That session is already open.")
		"still_running":
			template = TranslationServer.translate("That session is still running in a terminal. Continue it there, or type /exit in it and resume it again.")
		"not_found":
			template = TranslationServer.translate("That session wasn't found. {provider} may have deleted it.")
		"project_gone":
			template = TranslationServer.translate("Its project folder no longer exists: {path}")
		"no_terminal":
			template = TranslationServer.translate("No terminal window could be opened to run {provider}.")
		"not_absolute":
			template = TranslationServer.translate("The project's path isn't a full path.")
		"no_such_folder":
			template = TranslationServer.translate("The project's folder doesn't exist.")
		"not_a_folder":
			template = TranslationServer.translate("The project's path isn't a folder.")
		# The program (S02): a check that failed, or none found.
		"not_full_path":
			template = TranslationServer.translate("That isn't a full path.")
		"network_path":
			template = TranslationServer.translate("Choose a file on a drive of this computer (like C:\\...), not a network path.")
		"no_file":
			template = TranslationServer.translate("There's no program at that path.")
		"wrapper":
			template = TranslationServer.translate("Pick {program}.exe itself: a .cmd or other wrapper can't be started without a shell.")
		"not_the_program":
			template = TranslationServer.translate("That program didn't answer as {provider} ({program} --version).")
		"too_old":
			template = TranslationServer.translate("{provider} {version} is too old; version {minimum} or newer is needed. Run `{program} update`.")
		"not_installed":
			if OS.get_name() == "Windows":
				template = TranslationServer.translate("{provider} for Windows wasn't found. Install it from {site} (the Windows version, not inside WSL) and sign in once in a terminal.")
			else:
				template = TranslationServer.translate("{provider} wasn't found. Install it from {site} and sign in once in a terminal.")
		"set_path_broken":
			var why := _reason_text(str(details.get("why", "")), details, provider) if details.get("why", "") != "set_path_broken" else ""
			if why.is_empty():
				return ""
			# TRANSLATORS: {why}: the reason it doesn't work, a whole sentence.
			return Languages.fill(TranslationServer.translate("The {provider} set in Settings doesn't work: {why} Choose it again, or reset it."),
				{"provider": str(provider.get("name", "")), "why": why}) if provider.has("name") else ""
	return _filled(template, details, provider)


# Ours for a code with one meaning, or "".
static func _code_text(code: String) -> String:
	match code:
		"unknown_session":
			return TranslationServer.translate("That session has ended.")
		"session_starting":
			return TranslationServer.translate("The session hasn't come up yet.")
	return ""


# [param template] filled with the details and the provider's names, or ""
# if it's empty or a placeholder it needs has no value.
static func _filled(template: String, details: Dictionary, provider: Dictionary) -> String:
	var values := {}
	for name: Variant in details:
		if name is String and details[name] is String:
			values[name] = details[name]
	if provider.has("name"):
		values["provider"] = str(provider["name"])
	var caps: Variant = provider.get("capabilities", {})
	if caps is Dictionary and (caps as Dictionary).get("program_path") is Dictionary:
		var program: Variant = caps["program_path"].get("program")
		if program is String:
			values["program"] = program
	return _filled_from(template, values)


static func _filled_from(template: String, values: Dictionary) -> String:
	if template.is_empty():
		return ""
	for name in Languages.placeholders(template):
		if not values.has(name):
			return ""
	return Languages.fill(template, values)
