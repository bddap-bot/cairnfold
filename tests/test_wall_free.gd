extends SceneTree

## A wall freed while its ivy still grows; the check is a clean exit.


func _init() -> void:
	var masonry := Masonry.new(Wall.kinds())
	root.add_child(masonry)
	var wall := Wall.new(1, masonry, Terrain.new())
	wall.layout.points = [Vector3.ZERO, Vector3(12, 0, 0)]
	wall.layout.height = 2.4
	wall.finished = true
	wall.rebuild()
	wall.lay_now()
	wall.free()
	print("tests: ok")
	Main.quit(self, 0)
