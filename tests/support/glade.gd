extends RefCounted

## A garden without main.tscn for the wildlife tests: the wildlife and its tools are ticked by hand, never processed,
## and the hands are held far away. Without walls the glade has no wall tool, ground grab or kept
## meadow, as the butterflies'.
const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)

var tree: SceneTree
var rig: Rig
var world: World
var paths: Paths
var flora: Flora
var walls: WallTool
var grab: GroundGrab
var water: Water
var palette := Palette.new()
var wildlife: Wildlife
## Extra tools a test adds; teardown frees them first.
var tools: Array[Node] = []


func build(suite: SceneTree, seed: int, with_walls := true) -> void:
	tree = suite
	world = World.new()
	rig = _add(Rig.new(world.terrain))
	_add(world)
	var p := Paths.new()
	p.terrain = world.terrain
	p.marks = world.marks
	paths = _add(p)
	flora = _add(Flora.new(world.terrain, world.marks))
	water = Water.new(world.terrain, [])
	if with_walls:
		flora.keep()
		walls = _add(WallTool.new(rig, world, flora, paths))
		walls.set_process(false)
		grab = _add(GroundGrab.new(rig, world))
		grab.process_mode = Node.PROCESS_MODE_DISABLED
		grab.reshaped.connect(walls.reground)
	_add(water)
	world.attach(walls, flora, paths, grab, water)
	var hands: Array[Node3D] = []
	hands.assign(rig.hands)
	await tree.process_frame
	wildlife = _add(Wildlife.new(world.terrain, world.marks, water, flora, walls, palette, rig.head, hands, seed))
	wildlife.set_process(false)
	for h in rig.hands:
		h.global_position = AWAY


func add_tool(tool: Node) -> Node:
	tools.append(_add(tool))
	return tool


func teardown() -> void:
	wildlife.free()
	if walls:
		for w in walls.walls:
			w.free()
	for n: Node in tools + [grab, water, walls, flora, paths, world, rig]:
		if n:
			n.queue_free()
	await tree.process_frame


## Ticks the wildlife without frames, the walls' stones and perches first laid as they stand, so what the animals see
## does not hang on how far a worker thread got.
func run(seconds: float, each := Callable()) -> void:
	lay()
	for i in int(seconds / STEP):
		wildlife.tick(STEP)
		if each.is_valid():
			each.call()


func lay() -> void:
	if walls:
		for w in walls.walls:
			w.perches(true)


## As `run`, a frame at a time, so walls lay their stones again as they would in play.
func play(seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		await tree.process_frame
		lay()
		wildlife.tick(STEP)
		if each.is_valid():
			each.call()


## A check, run after each tick, that none of `animals()` left while `wildlife` could see it.
static func watch_vanishing(suite: SceneTree, wildlife: Wildlife, animals: Callable, what: String) -> Callable:
	var seen := {}
	return func() -> void:
		var now := {}
		for a: Node3D in animals.call():
			now[a] = wildlife._in_sight(a.position)
		for a in seen:
			if not now.has(a) and seen[a]:
				suite.check(false, "a %s vanished in sight" % what)
		seen.clear()
		seen.merge(now)


## Presses a hollow at x, z as a grip held `frames` does, then fills it to its brim with the pond tool, at once.
static func dig(tool: WaterTool, x: float, z: float, frames := 90) -> void:
	var depth := GroundGrab.dig_depth(frames / 60.0)
	var grab := tool.world.ground_grab
	var hand := grab.rig.right
	grab.begin(hand, tool.world.terrain.ground(x, z), 2.8)
	grab.pull(hand, -depth)
	grab.end_stroke(hand)
	tool.fill(hand, Vector3(x, Water.brim(tool.world.terrain, x, z, GroundGrab.reach(2.8, depth)), z))
	tool.settle()
	await tool.get_tree().process_frame
	await tool.get_tree().process_frame


func _add(n: Node) -> Node:
	tree.root.add_child(n)
	return n
