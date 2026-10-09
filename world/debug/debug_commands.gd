class_name DebugCommands
extends RefCounted
## The debug commands (C09), in the style of Minecraft's: typed in the
## [DebugConsole], they change the world's state on the spot. [method run]
## takes a line and returns what to tell you. For the developer while
## debugging; only in debug builds.
##
##   /time set <day|noon|sunset|night|midnight|sunrise|<n>m<n>s>
##   /time add <n>m<n>s      /time query      /time speed <multiplier>
##   /weather <clear|cloudy|rain|windy|storm|query>
##   /lightning              /help
##
## Times count from midnight over W09's day: 0s is midnight, 7m sunrise,
## 14m noon, 21m sunset, 28m midnight again (user's, 2026-10-08).

## Named points of the day, seconds from midnight. "day" is the launch's
## mid-morning (W09's START); "night" halfway from sunset to midnight.
const NAMED := {
	"midnight": 0.0,
	"sunrise": 420.0,
	"day": 622.0,
	"noon": 840.0,
	"sunset": 1260.0,
	"night": 1470.0,
}
## The day's length the times above are counted in, seconds (W09's).
const DAY := DayNight.CYCLE
const HELP := "Commands: /time set|add|query|speed, /weather <kind>|query, /lightning, /help"

var day_night: DayNight
var weather: Weather


func _init(p_day_night: DayNight, p_weather: Weather) -> void:
	day_night = p_day_night
	weather = p_weather


## Runs [param line] ("/time set noon"); returns the reply to show.
func run(line: String) -> String:
	var words := line.strip_edges().trim_prefix("/").to_lower().split(" ", false)
	if words.is_empty():
		return HELP
	match words[0]:
		"help", "?":
			return HELP
		"time":
			return _time(words.slice(1))
		"weather":
			return _weather(words.slice(1))
		"lightning":
			weather.strike()
			return "Lightning."
	return "Unknown command /%s. %s" % [words[0], HELP]


## Seconds from midnight now, on W09's 28-minute day.
func now() -> float:
	return fposmod(day_night.time - 0.75, 1.0) * DAY


## Jumps to [param seconds] from midnight.
func set_time(seconds: float) -> void:
	day_night.time = fposmod(seconds / DAY + 0.75, 1.0)
	day_night.apply()


## "10m 22s" for [param seconds].
static func clock(seconds: float) -> String:
	var s := int(round(seconds)) % int(DAY)
	return "%dm %02ds" % [s / 60, s % 60]


## Seconds for "7m", "30s", "10m22s" or a name in [constant NAMED];
## -1 if it isn't one.
static func parse_time(text: String) -> float:
	if NAMED.has(text):
		return NAMED[text]
	var re := RegEx.create_from_string("^(?:(\\d+(?:\\.\\d+)?)m)?(?:(\\d+(?:\\.\\d+)?)s)?$")
	var m := re.search(text)
	if m == null or text.is_empty():
		return -1.0
	return m.get_string(1).to_float() * 60.0 + m.get_string(2).to_float()


func _time(args: PackedStringArray) -> String:
	var usage := "Usage: /time set <day|noon|sunset|night|midnight|sunrise|7m|10m22s>, /time add <time>, /time query, /time speed <multiplier, 1 normal>"
	if args.is_empty():
		return usage
	match args[0]:
		"query":
			return "It's %s (%s); a day takes %s (speed %s)." % [clock(now()), _part(), _length(day_night.cycle), _speed()]
		"set", "add":
			if args.size() < 2:
				return usage
			var t := parse_time("".join(args.slice(1)))
			if t < 0.0:
				return "Not a time: %s. %s" % [" ".join(args.slice(1)), usage]
			set_time(t if args[0] == "set" else now() + t)
			return "Time set to %s (%s)." % [clock(now()), _part()]
		"speed":
			if args.size() < 2:
				return usage
			# A multiplier (user's, 2026-10-09): 2 makes days go twice as
			# fast (14m), 1 is normal (28m).
			var x := args[1].trim_suffix("x")
			if not x.is_valid_float() or x.to_float() <= 0.0:
				return "Not a speed: %s. %s" % [args[1], usage]
			day_night.cycle = DayNight.CYCLE / x.to_float()
			return "Speed %s: a day now takes %s." % [_speed(), _length(day_night.cycle)]
	return usage


# "28m" or "1m 30s" for a day [param seconds] long (clock() wraps at 28m).
static func _length(seconds: float) -> String:
	var s := int(round(seconds))
	return "%dm" % (s / 60) if s % 60 == 0 else "%dm %02ds" % [s / 60, s % 60]


# The day's speed as a multiplier: "2" for a 14-minute day.
func _speed() -> String:
	return ("%.2f" % (DayNight.CYCLE / day_night.cycle)).rstrip("0").rstrip(".")


# What part of the day it is now.
func _part() -> String:
	var t := now()
	if t < NAMED["sunrise"] or t >= NAMED["sunset"]:
		return "night"
	return "day"


func _weather(args: PackedStringArray) -> String:
	var usage := "Usage: /weather <%s>, /weather query" % "|".join(Weather.NAMES)
	if args.is_empty():
		return usage
	if args[0] == "query":
		return "The weather is %s%s." % [Weather.NAMES[weather.kind], "" if weather.changes else ", held"]
	var kind := Weather.kind_named(args[0])
	if kind < 0:
		return "Unknown weather %s. %s" % [args[0], usage]
	# Like Minecraft's (user's, 2026-10-09): it's that weather now, and
	# changes by itself again after a spell, as ever.
	weather.set_kind(kind as Weather.Kind, true)
	return "Weather set to %s." % args[0]
