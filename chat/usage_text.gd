class_name UsageText
extends RefCounted
## How token usage reads on screen (C08), shared by the chat panel and the
## limits corner. Numbers are compact like the terminal's: 950, 1.2k, 34k,
## 1.1M, 12M.


## A token count, compact: as is under 1,000, then one decimal under 10k
## (1.2k), whole thousands under a million (34k), one decimal under 10M
## (1.1M), then whole millions (12M). A trailing ".0" is dropped (1k).
static func tokens(n: int) -> String:
	if n < 1000:
		return str(maxi(n, 0))
	if n < 9950:
		return _decimal(n / 1000.0) + "k"
	if n < 999500:
		return "%dk" % roundi(n / 1000.0)
	if n < 9950000:
		return _decimal(n / 1000000.0) + "M"
	return "%dM" % roundi(n / 1000000.0)


## A count with thousands separators, for the exact figures (12,345).
static func exact(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## The chat header's line: "Context 34% · ↑ 2.1M in · ↓ 48k out". Context
## is a % when the provider says (the status line), else a token count,
## and left out until known. In counts input, cache reads and cache
## writes; out, output. "" without usage.
static func header(usage) -> String:
	if not usage is Dictionary:
		return ""
	var parts: PackedStringArray = []
	var context = usage.get("context")
	if context is Dictionary:
		if context.get("percent") != null:
			parts.append("Context %d%%" % roundi(context["percent"]))
		else:
			parts.append("Context %s" % tokens(int(context["tokens"])))
	var t: Dictionary = usage["tokens"]
	parts.append("↑ %s in" % tokens(int(t["input"]) + int(t["cache_read"]) + int(t["cache_write"])))
	parts.append("↓ %s out" % tokens(int(t["output"])))
	return " · ".join(parts)


## The header's tooltip: the exact figures.
static func header_details(usage) -> String:
	if not usage is Dictionary:
		return ""
	var lines: PackedStringArray = []
	var context = usage.get("context")
	if context is Dictionary:
		var line := "Context: %s tokens" % exact(int(context["tokens"]))
		if context.get("window") != null:
			line += " of %s" % exact(int(context["window"]))
		lines.append(line)
	var t: Dictionary = usage["tokens"]
	lines.append("Input: %s" % exact(int(t["input"])))
	lines.append("Cache reads: %s" % exact(int(t["cache_read"])))
	lines.append("Cache writes: %s" % exact(int(t["cache_write"])))
	lines.append("Output: %s" % exact(int(t["output"])))
	return "\n".join(lines)


## A turn's hint: "↓ 1.2k tokens" (its output tokens).
static func turn(output_tokens: int) -> String:
	return "↓ %s tokens" % tokens(output_tokens)


## One plan limit: "5-hour 74% · resets 3:40 PM" ([method when]).
static func limit(name: String, used_percent: float, resets_at: float, now: float) -> String:
	return "%s %d%% · resets %s" % [name, roundi(used_percent), when(resets_at, now)]


## A coming time (Unix seconds) in local time: "3:40 PM" today, "Fri 3:40
## PM" within a week, else "Oct 15".
static func when(at: float, now: float) -> String:
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	var local := Time.get_datetime_dict_from_unix_time(int(at + bias))
	var today := Time.get_datetime_dict_from_unix_time(int(now + bias))
	var hour: int = local["hour"] % 12
	var clock := "%d:%02d %s" % [12 if hour == 0 else hour, local["minute"], "AM" if local["hour"] < 12 else "PM"]
	if local["year"] == today["year"] and local["month"] == today["month"] and local["day"] == today["day"]:
		return clock
	if at - now < 7 * 86400:
		return "%s %s" % [["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][local["weekday"]], clock]
	return "%s %d" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][local["month"] - 1], local["day"]]


static func _decimal(x: float) -> String:
	return ("%.1f" % x).trim_suffix(".0")
