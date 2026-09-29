I found the problem. The player falls through the floor because `move_and_slide()` runs **before** the collision shape is enabled, so the first physics frame has nothing to collide with.

## What's happening

1. `_ready()` disables the shape while the level loads.
2. `_physics_process()` starts immediately and applies gravity.
3. The shape is re-enabled one frame later, after the body has already moved *below* the floor.

Here's the relevant part of `player.gd`:

```gdscript
func _ready() -> void:
	$CollisionShape3D.disabled = true
	await get_tree().process_frame
	$CollisionShape3D.disabled = false  # too late: gravity already ran


func _physics_process(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	move_and_slide()
```

## The fix

Skip physics until the shape is live:

```gdscript
var _ready_for_physics := false

func _physics_process(delta: float) -> void:
	if not _ready_for_physics:
		return
	velocity.y -= GRAVITY * delta
	move_and_slide()
```

Then run the tests:

```bash
godot --headless --path . --script res://tests/run_all.gd
```

### Options compared

| Approach | Pros | Cons |
|---|---|---|
| Guard flag | Simple, explicit | One more variable |
| `set_physics_process(false)` | No flag needed | Easy to forget to re-enable |
| Enable shape in the scene | Nothing to fix | Breaks the loading screen |

A few things worth knowing:

- The guard also covers **scene reloads**, not just the first load.
  It costs one branch per frame, which is nothing.
- If you'd rather not add a flag:
  - call `set_physics_process(false)` in `_ready()`
  - and `set_physics_process(true)` after the `await`
- [ ] Add a regression test for the first frame
- [x] Confirm the floor's collision layer is `1`

> **Note:** Godot's docs cover this in [Physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html). The same pattern applies to `RigidBody3D`.

---

Want me to apply the guard-flag version and add the test?
