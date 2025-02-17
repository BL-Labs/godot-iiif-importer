@tool
extends EditorPlugin

var import_dock : Control

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	add_custom_type("IIIFImporter", "Node", preload("res://addons/IIIFPlugin/IIIFImporter.gd"), preload("res://addons/IIIFPlugin/IIIFMetaNodeIcon.png"))
	import_dock = preload("res://addons/IIIFPlugin/import_dock.tscn").instantiate()
	
	add_control_to_dock(DOCK_SLOT_LEFT_BL, import_dock)


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.

	remove_custom_type("IIIFImporter")
	remove_control_from_docks(import_dock)

func _on_test_clicked() -> void:
	EditorInterface.get_resource_filesystem().scan()
