extends SceneTree

## Headless check that a wall freed with its ivy still growing exits cleanly:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wall_free.gd


func _init() -> void:
	var masonry := Masonry.new(Wall.kinds())
	root.add_child(masonry)
	var wall := Wall.new(1, masonry)
	wall.layout.points = [Vector3.ZERO, Vector3(12, 0, 0)]
	wall.layout.height = 2.4
	wall.finished = true
	wall.rebuild()
	wall.lay_now()
	wall.free()
	print("tests: ok")
	Main.quit(self, 0)
