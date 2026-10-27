class_name SessionIslands
extends Node3D
## One island per live session, each with its orchestrator bound to the
## session and its subagents (IslandAgents). Islands are placed by
## cluster (W05, [SessionClusters]). Each island's ground is made on a
## worker thread, out of sight, then it rises out of the sea (W04); since
## C14 one already running when the world connects rises too, behind the
## main menu. Until the player has been on a new session's island, a beacon
## stands over it (and [NewIslandPointers] points to it); not over one
## taken back or started outside the game (S08). When a session
## ends its orchestrator and agents go at once; the empty island stays
## while the player is on it (or on one of its bridges), then sinks and is
## freed; while the player is away ([member player_away]) it sinks at
## once. Bridges (W06, [BridgeNetwork]) join a cluster's islands and the
## spawn platform once an island is up, and go when it starts sinking.
## Each island is of a [Biome] (W10), chosen in the sessions menu or
## rolled at random.
## A session taken back after a restart (S07) gets its island back as it
## was (W12, [IslandMemory]): its biome, seed and cluster, placed in the
## saved order once the sync is done, gaps closed up. One started outside
## the game (S08) is remembered after it goes, until a start that shows
## them finds it gone; when it rises again mid-game it gets its biome and
## seed back.
## An island whose session the world only watches ([code]read_only[/code]:
## S07, S08) has the read-only mark, a grey flag ([ReadOnlyFlag]).
## Everything under it, agents and bridges that come later included, is
## hidden past [member draw_distance] ([DrawDistance]).

signal island_added(session_id: String, island: Island, orchestrator: Orchestrator)
## A new session's island is up (at once for one already running).
signal island_risen(session_id: String)

const ORCHESTRATOR := preload("res://agents/orchestrator/orchestrator.tscn")
## Where a beach island starts rising from and sinks to: low enough that
## all of it (its dunes reach about 3.2 m) is under the deepest sea floor
## (W08), so it rises out of the seabed and sinks back into it. Higher
## islands (W10) go deeper: see [method sunk_y].
const SUNK_Y := Seabed.DEEPEST - 4.0
## Where an island waits, out of sight, while its ground is made
## (Island.build_in_background): its orchestrator is already on it.
const BUILDING_Y := Seabed.DEEPEST - 100.0
## The new-island beacon's colour: not A05's orange, which means waiting.
const NEW_COLOUR := Color(0.35, 1.0, 0.55)
## Props are cleared this far either side of a bridge's landing, and this
## far inward from it, metres (W10).
const LANDING_CLEAR := 3.0
const LANDING_RUN := 8.0

var store: SessionStore
## Which cluster each session is in, and where its island goes.
var clusters := SessionClusters.new()
## The bridges between islands, and to the platform (a hub added by the
## world).
var bridges := BridgeNetwork.new()
## Whoever has to leave an ended session's island before it sinks.
var player: Node3D
## The player is away (the main menu's up, C14): an ended session's
## island sinks even with them on it, and [method take_stranded] says so.
var player_away := false
## Each live session's island, kept for the next start (W12).
var memory := IslandMemory.new()
## The biome of an island nobody chose one for (a session already running,
## or one started outside the menu): [constant Biome.RANDOM] or a kind.
var default_biome := Biome.RANDOM
## Seconds to rise and to sink.
var rise_time := 3.0
var sink_time := 4.0
## Islands, agents and bridges further than this from the camera, plus
## their own size, aren't drawn: the fog hides them fully (world.gd sets
## it from the fog). 0 is no limit. Setting it applies it to everything.
var draw_distance := 0.0:
	set(value):
		draw_distance = value
		if is_inside_tree():
			for node in get_tree().get_nodes_in_group(DrawDistance.GROUP):
				if is_ancestor_of(node):
					DrawDistance.limit(node, draw_distance)

var _islands := {} # session id → Island
var _rising := {} # session id → its Tween
var _left := {} # Island of an ended session → its cluster hold
var _sinking := {} # Island → true, of those in _left
var _unvisited := {} # session id → its new-island AttentionBeacon
var _cluster := {} # Island → its cluster id, while it's in the world
var _biome_choice := {} # session id → the biome chosen for its island
var _keys := {} # session id → its IslandMemory key
var _aliases := {} # session id → its IslandMemory alias, or ""
var _outside := {} # session id → true, for one started outside the game (S08)
var _gone_outside: Array[Array] = [] # [key, alias] of outside ones kept after they went, till the next sync
var _waiting: Array[String] = [] # sessions taken back, placed once synced
var _stranded := false # an island sank from under the player while away


func _ready() -> void:
	bridges.name = "Bridges"
	bridges.build_in_background = true # like the islands' ground (W01)
	add_child(bridges)
	get_tree().node_added.connect(_on_node_added)


# The memory's file is written on a worker thread: in before we go.
func _exit_tree() -> void:
	IslandMemory.flush()


## Call once, before anything else that listens for new sessions (see
## SessionsMenu.setup).
func setup(p_store: SessionStore) -> void:
	store = p_store
	memory.load_file()
	store.session_added.connect(_on_added)
	store.session_removed.connect(_on_removed)
	store.session_changed.connect(func(id: String, fields: Array) -> void:
		if "read_only" in fields and _islands.has(id):
			(_islands[id] as Island).set_read_only(store.session(id).get("read_only", false) == true))
	store.synced.connect(_on_synced)


func island(session_id: String) -> Island:
	return _islands.get(session_id)


func orchestrator(session_id: String) -> Orchestrator:
	var i := island(session_id)
	return i.get_node("Orchestrator") if i else null


## The agents on a session's island (subagents, state markers), or null.
func agents(session_id: String) -> IslandAgents:
	var i := island(session_id)
	return i.get_node("Agents") if i else null


## Whether a session's island is still rising.
func is_rising(session_id: String) -> bool:
	return _rising.has(session_id)


## Whether every island is built and up (none rising).
func all_up() -> bool:
	return _rising.is_empty()


## New sessions whose islands the player hasn't been on yet.
func unvisited() -> Array[String]:
	var out: Array[String] = []
	out.assign(_unvisited.keys())
	return out


## The islands of a cluster in the world: live, empty or sinking.
func cluster_islands(cluster_id: String) -> Array[Island]:
	var out: Array[Island] = []
	for i: Island in _cluster:
		if _cluster[i] == cluster_id and is_instance_valid(i):
			out.append(i)
	return out


## Every island in the world: live, empty or sinking (W06's big map).
func all_islands() -> Array[Island]:
	var out: Array[Island] = []
	for i: Island in _cluster:
		if is_instance_valid(i):
			out.append(i)
	return out


## The cluster an island in the world belongs to, or "".
func cluster_of(i: Island) -> String:
	return _cluster.get(i, "")


## Records the biome chosen for a session being started (a [enum
## Biome.Kind] or [constant Biome.RANDOM]), before it comes up (W10).
func choose_biome(session_id: String, choice: int) -> void:
	_biome_choice[session_id] = choice


## How deep [param i] starts rising from and sinks to: all of it under the
## deepest sea floor.
static func sunk_y(i: Island) -> float:
	return minf(SUNK_Y, Seabed.DEEPEST - 0.8 - i.top())


## The live sessions with an island.
func session_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_islands.keys())
	return out


## The cluster of the island nearest [param point], or "".
func nearest_cluster(point: Vector3) -> String:
	var found := ""
	var best := INF
	for i: Island in _cluster:
		if is_instance_valid(i) and _distance(i, point) < best:
			found = _cluster[i]
			best = _distance(i, point)
	return found


## Whether an island is in a far cluster (W05: a 9th or later), bridged
## to its cluster's other islands but not to the platform.
func is_far(i: Island) -> bool:
	return clusters.is_far(_cluster.get(i, ""))


## The key of an island's region in [member bridges].
static func region(i: Island) -> String:
	return "island:%d" % i.get_instance_id()


## Whether an ended session's island sank from under the player while
## they were away ([member player_away]); asking clears it.
func take_stranded() -> bool:
	var was := _stranded
	_stranded = false
	return was


## Ended sessions' islands still in the world: waiting for the player to
## leave, or sinking.
func left_islands() -> Array[Island]:
	var out: Array[Island] = []
	out.assign(_left.keys())
	return out


## Where the player lands on a session's island: 6 m in front of the
## orchestrator, on the flat middle.
func arrival_point(session_id: String) -> Vector3:
	var i := island(session_id)
	return i.global_position + Vector3(0.0, i.height_at(0.0, 6.0) + 0.1, 6.0)


## The session whose island is under [param point] (the nearest, as a
## cluster's islands are close together), or "".
func session_at(point: Vector3) -> String:
	var found := ""
	var best := INF
	for id in _islands:
		var i: Island = _islands[id]
		var d := _distance(i, point)
		if _is_over(i, point) and d < best:
			found = id
			best = d
	return found


func _process(_delta: float) -> void:
	for id: String in _unvisited.keys():
		if player and _is_over(_islands[id], player.global_position):
			_unvisited[id].set_on(false)
			_unvisited.erase(id)
	for i: Island in _left:
		if _sinking.has(i):
			continue
		var on := player != null and (_is_over(i, player.global_position) or bridges.on_bridge_of(region(i), player.global_position))
		if on and player_away:
			_stranded = true
		if not on or player_away:
			_sink(i)


func _on_added(id: String, created: bool) -> void:
	var session := store.session(id)
	_keys[id] = IslandMemory.key(session)
	_aliases[id] = IslandMemory.alias(session)
	if session.get("origin") == "external":
		_outside[id] = true
	# One already running (taken back) waits for the sync's others, to
	# come back in their order. One outside a sync (taken back late, or
	# one started outside the game that rises: turned back on, new, or its
	# app relaunched it, S08) is placed at once, with its remembered biome
	# and seed if any; it joins its cluster as a new one would.
	if not created and store.syncing:
		_waiting.append(id)
		return
	_place(id, created, memory.entry(memory.find([_keys[id], _aliases[id]])), false)


# Places those taken back: the remembered ones in their saved order, then
# the others as they came. Then forgets the islands of sessions that
# didn't come back.
func _on_synced() -> void:
	var by_key := {}
	var waiting := _waiting.duplicate()
	_waiting.clear()
	for id in waiting:
		var k := memory.find([_keys[id], _aliases[id]])
		if not k.is_empty():
			by_key[k] = id
	for k: String in memory.ordered(by_key.keys()):
		_place(by_key[k], false, memory.entry(k))
		waiting.erase(by_key[k])
	for id: String in waiting:
		_place(id, false)
	var live := {}
	for id: String in _keys:
		live[_keys[id]] = true
		live[_aliases[id]] = true
	memory.keep_only(live)
	_gone_outside.clear()


## Forgets the islands of sessions started outside the game that went
## during this game and were kept for their app relaunching them (S08):
## the setting was turned off (those still shown end, reason user).
func forget_outside() -> void:
	for keys: Array in _gone_outside:
		memory.erase(keys)
	_gone_outside.clear()


# [param saved]: its remembered island, all of it, or with
# [param whole] false only its biome and seed.
func _place(id: String, created: bool, saved := {}, whole := true) -> void:
	var t0 := Time.get_ticks_usec() # TIMING
	var tl := func(what: String) -> void: # TIMING
		print("TIMING place %s %.2f ms" % [what, (Time.get_ticks_usec() - t0) / 1000.0]) # TIMING
		t0 = Time.get_ticks_usec() # TIMING
	var i := Island.new()
	i.name = "Island"
	if saved.is_empty() or not whole:
		clusters.add(id, store.session(id))
		i.biome = Biome.resolve(_biome_choice.get(id, default_biome)) if saved.is_empty() else int(saved["biome"])
		if not saved.is_empty():
			i.island_seed = int(saved["seed"])
	else:
		clusters.restore(id, saved)
		clusters.add(id, store.session(id))
		i.biome = int(saved["biome"])
		i.island_seed = int(saved["seed"])
	_biome_choice.erase(id)
	i.position = clusters.island_position(id)
	i.zipline_waits = true # placed once its bridges land (W10)
	i.build_in_background = true
	# Out of sight till its ground is made (it then rises from sunk_y).
	i.position.y = BUILDING_Y
	tl.call("clusters") # TIMING
	add_child(i, true)
	tl.call("island add") # TIMING
	var o: Orchestrator = ORCHESTRATOR.instantiate()
	tl.call("orch instantiate") # TIMING
	o.name = "Orchestrator"
	o.session_id = id
	o.position = Vector3(0.0, i.height_at(0.0, 0.0), 0.0)
	tl.call("orch height") # TIMING
	i.add_child(o)
	tl.call("orch add") # TIMING
	var agents := IslandAgents.new()
	agents.name = "Agents"
	i.add_child(agents)
	agents.setup(store, id, i, o)
	tl.call("agents") # TIMING
	i.set_read_only(store.session(id).get("read_only", false) == true)
	_islands[id] = i
	var cluster := clusters.cluster_of(id)
	_cluster[i] = cluster
	memory.put([_keys[id], _aliases[id]], {
		"biome": i.biome, "seed": i.island_seed, "cluster": cluster, "name": clusters.cluster_name(cluster),
		"repo_key": clusters.cluster_key(cluster), "slot": clusters.slot_of(cluster), "index": clusters.index_of(id),
	})
	tl.call("read-only, memory") # TIMING
	island_added.emit(id, i, o)
	tl.call("island_added") # TIMING
	# Rises with the island, from its middle. Not for one already running
	# (taken back) or started outside the game (S08): the player didn't
	# just ask for it, so it isn't news.
	if created and not _outside.has(id):
		var beacon := AttentionBeacon.new()
		beacon.name = "NewBeacon"
		beacon.colour = NEW_COLOUR
		beacon.position = o.position
		i.add_child(beacon)
		beacon.set_on(true)
		_unvisited[id] = beacon
		tl.call("beacon") # TIMING
	# Every island rises once its ground is made (C14: taken-back ones too,
	# behind the main menu); it counts as rising till then.
	_rising[id] = null
	i.built.connect(_rise.bind(id, i), CONNECT_ONE_SHOT)


func _rise(id: String, i: Island) -> void:
	if _islands.get(id) != i:
		return
	i.position.y = sunk_y(i)
	# Bound to the island, so it stops if the island goes.
	var tween := i.create_tween()
	tween.tween_property(i, "position:y", 0.0, rise_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		_rising.erase(id)
		_bridge(id)
		island_risen.emit(id))
	_rising[id] = tween


func _on_removed(id: String, reason: String) -> void:
	_waiting.erase(id)
	# One started outside the game that stops being listed is remembered
	# until the next start (S08), so its app relaunching it finds it again;
	# that start's sync forgets it if it's gone. Turning them off forgets it.
	if not _outside.has(id) or reason == "user":
		memory.erase([_keys.get(id, ""), _aliases.get(id, "")])
	else:
		_gone_outside.append([_keys.get(id, ""), _aliases.get(id, "")])
	_keys.erase(id)
	_aliases.erase(id)
	_outside.erase(id)
	var i: Island = _islands.get(id)
	if i == null:
		return
	_islands.erase(id)
	if _rising.has(id):
		if _rising[id]:
			_rising[id].kill()
		_rising.erase(id)
	if _unvisited.has(id):
		_unvisited[id].set_on(false)
		_unvisited.erase(id)
	i.get_node("Orchestrator").queue_free()
	i.get_node("Agents").queue_free()
	_left[i] = clusters.hold(id)


func _sink(i: Island) -> void:
	_sinking[i] = true
	bridges.remove(region(i))
	_tell_landings()
	# One ended before it rose is out of sight: gone at once.
	var time := sink_time if i.is_built() and i.position.y >= sunk_y(i) else 0.0
	var tween := i.create_tween()
	tween.tween_property(i, "position:y", sunk_y(i), time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		clusters.remove(_left[i])
		_left.erase(i)
		_sinking.erase(i)
		_cluster.erase(i)
		i.queue_free())


# Geometry coming under us gets the draw distance, once it's set up (its
# mesh may come after it enters the tree).
func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D and is_ancestor_of(node):
		_limit.call_deferred(node)


func _limit(node: Variant) -> void:
	if is_instance_valid(node) and (node as Node).is_inside_tree():
		var t0 := Time.get_ticks_usec() # TIMING
		DrawDistance.limit(node, draw_distance)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 # TIMING
		if ms > 0.3: # TIMING
			print("TIMING limit %s %.2f ms" % [(node as Node).name, ms]) # TIMING


# A risen island joins its cluster's bridges; a far cluster's leave the
# platform out.
func _bridge(id: String) -> void:
	var t0 := Time.get_ticks_usec() # TIMING
	var i: Island = _islands[id]
	var reach := i.generator.radius * 1.45
	var cluster := clusters.cluster_of(id)
	bridges.add(region(i), cluster, i.global_position, reach, func(toward: Vector3) -> Vector3:
		var p := _shore_point(i, toward)
		# The way in from the bridge is kept clear of props.
		var local := p - i.global_position
		var inward := Vector3(-local.x, 0.0, -local.z).normalized() * LANDING_RUN
		i.props.clear_near(local, local + inward, LANDING_CLEAR)
		return p, not clusters.is_far(cluster))
	print("TIMING _bridge add %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)) # TIMING
	t0 = Time.get_ticks_usec() # TIMING
	_tell_landings()
	print("TIMING _bridge landings %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)) # TIMING


# Tells every island where its bridges land now, after bridges came or
# went, so its zipline (W10) and its read-only flag (S08) keep off them.
func _tell_landings() -> void:
	for i in all_islands():
		var key := region(i)
		var landings: Array[Vector3] = []
		for l in bridges.links():
			if key in l:
				var b := bridges.bridge(l[0], l[1])
				var near := b.from if b.from.distance_to(i.global_position) < b.to.distance_to(i.global_position) else b.to
				landings.append(near - i.global_position)
		i.set_landings(landings)


# Where a bridge heading for [param toward] meets the island: the
# outermost point at its edge height (a beach's half metre, W10's
# shoulders), on the line from its middle.
static func _shore_point(i: Island, toward: Vector3) -> Vector3:
	var c := i.global_position
	var dir := Vector2(toward.x - c.x, toward.z - c.z).normalized()
	var r := i.generator.shore_radius(dir.x, dir.y) * 1.2
	var edge := i.edge_height()
	while r > 0.0 and i.height_at(dir.x * r, dir.y * r) < edge:
		r -= 0.25
	return c + Vector3(dir.x * r, i.height_at(dir.x * r, dir.y * r), dir.y * r)


# Whether [param point] is on or around the island: its land and shallows.
func _is_over(i: Island, point: Vector3) -> bool:
	return _distance(i, point) < i.generator.radius * 2.0


func _distance(i: Island, point: Vector3) -> float:
	return Vector2(point.x - i.global_position.x, point.z - i.global_position.z).length()
