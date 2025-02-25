# IIIF 3D Importer
# By Liam Green-Hughes, British Library, 2025
# Example imports:
# https://github.com/IIIF/3d/blob/main/manifests/1_basic_model_in_scene/model_origin.json
# https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json

@tool

extends Node
class_name IIIFImporter

# Scene object being built
var scene : PackedScene = null
# Name of file as on disc (with .tscn)
var scene_filename : String = ""

# IIIF Manifest converted to dictionary
var manifest : Dictionary = {}
# Base node of a scene
var root_node : Node = null

# File currrently being downloaded
var current_download_url : String = ""

# var await_scanning : bool = false
var models_to_download : int = 0

# Variables changable in Inspector
# In project folder name for imported resources
@export var import_dir : String = "IIIFModelImport"
# Godot HTTPRequest object, must be assigned in editor
@export var http_request : HTTPRequest = null

# A reference to the EditorFileSYstem, used for scanning
var resource_fs : EditorFileSystem = null

# IIIF manifest
var iiif_json : Dictionary  = {}

enum StatusFlag {
	IDLE,
	REQ_MODELS,
	ALL_MODELS_REQ,
	MODEL_DL_COMPLETE,
	SCANNING,
	BUILD_SCENE
}

# Current operation of import plugin
var status : StatusFlag = StatusFlag.IDLE

# Signals
# Fired when there is an http error status on a request
signal alert_message(err_msg : String)

signal scanning_complete

# Change current status of import plugin
func change_status(new_status : StatusFlag):
	status = new_status
	print_debug("New status is now: ", StatusFlag.find_key(status))


# Godot function run whan plugin starts
func _ready():
	if (!resource_fs):
		resource_fs = EditorInterface.get_resource_filesystem()
	scanning_complete.connect(resume_manifest_processing)
	change_status(StatusFlag.IDLE)

	
# Parses an IIIF manifest file and tries to convert it to a Godot scene
# Processing of the tree will be deferred while models are downloaded
func process_iiif_json(manifest_json : Dictionary) -> void:
	# Copy Metadata
	iiif_json = manifest_json
	for key in manifest_json:
		if(key != "items"):
			manifest["iiif_manifest_%s" % key.validate_node_name()] = manifest_json[key]
	change_status(StatusFlag.REQ_MODELS)
	models_to_download = 0	
	# Recursive import
	import_assets_in_manifest(manifest_json["items"])
	change_status(StatusFlag.ALL_MODELS_REQ)


# Called when models have been downloaded and tree can now be worked on
func resume_manifest_processing() -> void:
	print_debug("Resuming parsing items")
	parse_items(null,iiif_json["items"])
	change_status(StatusFlag.IDLE)


# Godot function run on every frame
# This will monitor the resource scanner
func _process(delta : float) -> void:
	if status == StatusFlag.MODEL_DL_COMPLETE:
		resource_fs.scan_sources()
		change_status(StatusFlag.SCANNING)
		return

	if status == StatusFlag.SCANNING && !resource_fs.is_scanning():	
		scanning_complete.emit()
		change_status(StatusFlag.BUILD_SCENE)
		return


# Goes through manifest and looks for models to be downloaded		
func import_assets_in_manifest(items : Array) -> void:
	for item in items:
		if item["type"] == "Annotation":
			import_model(item["body"]["id"])
		if "items" in item:
			import_assets_in_manifest(item["items"])
	
	
# Recursive parser for "items" in IIIF manifest JSON
func parse_items(parent_node : Node, items : Array) -> Node:	
	var child_node = null
	# process manifest
	for item in items:
		# Act on specific kinds of nodes
		if item["type"] == "Scene":
			# TODO what happens with 2D?
			child_node = create_node_3d_root_from_scene(item)
		elif item["type"] == "Annotation":
			child_node = create_metadata_node(item)
			parent_node.add_child(child_node)
			child_node.owner = root_node
			var model : Node = _get_imported_model(item["body"]["id"])		
			child_node.add_child(model)
			model.owner = root_node
		else:
			# Just create an annotion node for now
			child_node = create_metadata_node(item)
		
		# Add this new node to the parent			
		if parent_node != null and item["type"] != "Annotation":
			parent_node.add_child(child_node)
			child_node.owner = root_node
		
		# Process this instance of items recursively	
		if "items" in item:
			child_node = parse_items(child_node, item["items"])
		
		# If we created a scene then we now need to save it	
		if item["type"] == "Scene":
			scene.pack(child_node)
			ResourceSaver.save(scene, scene_filename)
			
	return parent_node


# Create an IIIF metadata section to a Godot node and copy all metadata
func create_metadata_node(item_meta : Dictionary) -> Node:
	var meta_node = Node.new()
	meta_node.name = "IIIF %s" % item_meta["type"]
	add_meta_to_node(meta_node, item_meta)	
	return meta_node


# Converts IIIF metadata to Godot metatdata on a node
func add_meta_to_node(node : Node, meta : Dictionary) -> void:
	for key in meta:
		if key in meta and key != "items":
			node.set_meta("iiif_%s" % key, meta[key])	


# Converts an IIIF meta scene to a Godot scene	
func create_node_3d_root_from_scene(scene_meta : Dictionary) -> Node3D:
	scene = PackedScene.new()
	root_node = Node3D.new()
	add_meta_to_node(root_node, scene_meta)
	# Add in manifest data
	for key in manifest:
		root_node.set_meta(key, manifest[key])
	# TODO multilingual support
	root_node.name = scene_meta["label"]["en"][0].validate_node_name()
	# Generate safe filename
	scene_filename = "res://%s.tscn" % scene_meta["label"]["en"][0].validate_filename()
	
			
	if "backgroundColor" in scene_meta:
		create_world_environment_node(scene_meta["backgroundColor"])
	return root_node


# Sets background colour
func create_world_environment_node(color : String) -> void:
	print_debug("Adding background colour: " + color)
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html(color)
	world_env.environment = env
	world_env.name = "Background"
	root_node.add_child(world_env)
	world_env.owner = root_node


# Converts a download URL into an internal resource reference
func get_filename_from_url(url : String) -> String:
	return "res://%s/%s" % [import_dir, url.get_file()]
	
	
# Imports a 3d model from the web
func import_model(url : String) -> void:
	ensure_import_dir_exists()
	print_debug("Downloading " + get_filename_from_url(url))
	current_download_url = url
	http_request.request_completed.connect(_on_model_downloaded)
	http_request.request(url)
	models_to_download = models_to_download + 1


# Handles completed web request to download model from web
func _on_model_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# If there was an HTTP then signal it and stop
	if (signal_if_alert_message(response_code)):
		return
	var gstate = GLTFState.new()
	gstate.base_path = "res://IIIFModelImport/"
	var gimporter = GLTFDocument.new()	
	
	var err = gimporter.append_from_buffer(body, "", gstate)

	if err != OK:
		print_debug("Error importing GLB: " + str(err))
		return
	gimporter.write_to_filesystem(gstate, get_filename_from_url(current_download_url) )
	models_to_download = models_to_download - 1
	if status == StatusFlag.ALL_MODELS_REQ && models_to_download == 0:
		change_status(StatusFlag.MODEL_DL_COMPLETE)


# Gets a model from the resources area		
func _get_imported_model(url) -> Node:
	# Import model as normal from resources
	var model_scene = load(get_filename_from_url(url))	
	if not model_scene:
		print_debug("Failed to load the model.", url)
	var model : Node3D = model_scene.instantiate()
	return model

	
# Makes sure the object import folder exists, if not, it creates it
func ensure_import_dir_exists() -> bool:
	var dir = DirAccess.open("res://")
	
	if not dir:
		print_debug("Failed to access directory.")
		return false
		
	if dir.dir_exists(import_dir):
		return true
		
	# Try to create import dir
	var result = dir.make_dir(import_dir)
	if result != OK:
		print_debug("Failed to create import directory: %s" % result)
		return false
	# Directory now exists	
	return true


# Quick check to see if a URL is valid at face value
func is_valid_url(raw_url) -> bool:
	var url = raw_url.strip_edges(true, true)
	if (url == "" || url.left(4) != "http"):
		print_debug("The URL %s is not valid." % url)
		return false
	else:
		return true


# Emits a message corresponding with an HTTP error code
func signal_if_alert_message(response_code) -> bool:
	var err_msg : String = ""
	if response_code == 401:
		err_msg = "401 Not authorised."
	elif response_code == 404:
		err_msg = "404 Not Found."
	elif response_code >= 400:
		err_msg = "HTTP Error %s." % response_code
	
	if err_msg != "":
		alert_message.emit("Could not import manifest. %s" % err_msg)
		return true
		
	return false
	

# Get tje IIIF manifest from the web	
func import_manifest_from_url(url) -> void:
	http_request.request_completed.connect(_on_manifest_request_received)
	http_request.request(url)


# Called when manifest we request returns. This will process the results.
func _on_manifest_request_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	http_request.request_completed.disconnect(_on_manifest_request_received)

	# If there was an HTTP then signal it and stop
	if (signal_if_alert_message(response_code)):
		return
		# IF JSON THEN PARSE AS IMPORT, IF NOT THEN A MODEL
	# Now see if it can be parsed
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		alert_message.emit("Could not parse manifest.")
		return

	process_iiif_json(json.data)
