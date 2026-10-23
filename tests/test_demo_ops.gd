extends "res://../tests/support/suite.gd"

## Every step in every demo script names an op Driver plays, so a rename shows here rather than on a device.


func _initialize() -> void:
	var ops := (load("res://src/driver.gd") as Script).get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	var demo := ProjectSettings.globalize_path("res://../demo").simplify_path()
	var files := DirAccess.get_files_at(demo)
	check(files.size() > 100, "the demo scripts are found")
	for file in files:
		if file.get_extension() == "json":
			for step: Dictionary in Driver.read(demo.path_join(file)):
				check(ops.has("_" + step.op), "%s: Driver plays %s" % [file, step.op])
	finish()
