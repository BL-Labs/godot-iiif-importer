# IIIF 3D Importer
# By Liam Green-Hughes, British Library, 2025
# Example imports:
# https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 3D: https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 2D: https://iiif.io/api/cookbook/recipe/0001-mvm-image/ https://iiif.io/api/cookbook/recipe/0001-mvm-image/manifest.json

@tool

extends Node
class_name IIIFImporter

# Name of file as on disc (with .tscn)
var output_filename : String = ""

# Base node of a scene
var root_node : Node = null

# File currrently being downloaded
var current_download_url : String = ""
# Type of file being downloaded, e.g. model, image
var current_download_type : String = ""

var assets_to_download : int = 0

# Variables changable in Inspector
# In project folder name for imported resources
@export var import_dir : String = "IIIFAssetImport"
# Godot HTTPRequest object, must be assigned in editor
@export var http_request : HTTPRequest = null

# A reference to the EditorFileSYstem, used for scanning
var resource_fs : EditorFileSystem = null

# IIIF manifest
var iiif_json : Dictionary  = {}

enum StatusFlag {
	IDLE,
	REQ_ASSETS,
	ALL_ASSETS_REQ,
	ASSETS_DL_COMPLETE,
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
# Processing of the tree will be deferred while assets are downloaded
func process_iiif_json(manifest_json : Dictionary) -> void:
	# Copy Metadata
	iiif_json = manifest_json
	change_status(StatusFlag.REQ_ASSETS)
	assets_to_download = 0	
	# Recursive import
	import_assets_in_manifest(manifest_json["items"])
	change_status(StatusFlag.ALL_ASSETS_REQ)


func create_iiif_manifest_root_node() -> void:
	root_node = Node.new()
	root_node.name = "IIIF Manifest"
	add_meta_to_node(root_node, iiif_json)
	print_debug("Created Root Node")
	

# Called when assets have been downloaded and tree can now be worked on
func resume_manifest_processing() -> void:
	print_debug("Resuming parsing items")
	
	# Create GODOT scene root		
	create_iiif_manifest_root_node()
	parse_items(root_node,iiif_json["items"])
	# Save scene
	save_godot_scene()
	change_status(StatusFlag.IDLE)


# Saves the output godot scene to disc
func save_godot_scene() -> void:
	var scene = PackedScene.new()
	scene.pack(root_node)
	ResourceSaver.save(scene, output_filename)


# Godot function run on every frame
# This will monitor the resource scanner
func _process(delta : float) -> void:
	if status == StatusFlag.ASSETS_DL_COMPLETE:
		resource_fs.scan_sources()
		change_status(StatusFlag.SCANNING)
		return

	if status == StatusFlag.SCANNING && !resource_fs.is_scanning():			
		change_status(StatusFlag.BUILD_SCENE)
		scanning_complete.emit()
		return


# Goes through manifest and looks for assets to be downloaded		
func import_assets_in_manifest(items : Array) -> void:
	for item in items:
		if item["type"] == "Annotation":
			if "source" in item["body"]:
				for source in item["body"]["source"]:
					import_asset(source["id"], source["type"])
			else:
				import_asset(item["body"]["id"], item["body"]["type"])
		if "items" in item:
			import_assets_in_manifest(item["items"])
	
	
# Recursive parser for "items" in IIIF manifest JSON
func parse_items(parent_node : Node, items : Array) -> Node3D:	
	var child_node : Node = null
	# process manifest
	for item in items:
		# Act on specific kinds of nodes
		if item["type"] == "Scene":
			child_node = create_node3d(item)
		elif item["type"] == "Annotation":
			child_node = create_annotation_node(item)
		else:
			child_node = Node.new()
		
		# Common to all nodes
		child_node.name = "IIF " + item["type"].validate_node_name()
		add_meta_to_node(child_node, item)
		parent_node.add_child(child_node)
		child_node.owner = root_node
		for subnode in child_node.get_children():
			subnode.owner = root_node
			
		# Add position
		add_position_to_node(child_node, item)
		
		# Add rotation
		add_rotation_to_node(child_node, item)
		
		# Process this instance of items recursively	
		if "items" in item:
			child_node = parse_items(child_node, item["items"])
			
	return parent_node

func add_position_to_node(node : Node, meta : Dictionary) -> void:
	if "target" in meta and "selector" in meta["target"]:

		# TODO select position space based on object identified as source
		for selector in meta["target"]["selector"]:
			print_debug(selector)
			if selector["type"] == "PointSelector":
				print_debug("Positioning")
				if node is Node2D:
					print_debug(Vector2(selector["x"], selector["y"]))
					node.position = Vector2(selector["x"], selector["y"])
				if node is Node3D:
					print_debug(Vector3(selector["x"], selector["y"], selector["z"]))
					node.position = Vector3(selector["x"], selector["y"], selector["z"])

# Set rotation on a 3D model 
func add_rotation_to_node(node : Node, meta : Dictionary) -> void:
	if "body" in meta and "transform" in meta["body"]:
		# TODO select position space based on object identified as source
		for transform in meta["body"]["transform"]:
			if transform["type"] == "RotateTransform":
				print_debug("Rotating")
				var rotation = Vector3(transform["x"], transform["y"], transform["z"])
				if node is Node3D:
					node.rotation = rotation
					print_debug(rotation)

# Converts IIIF metadata to Godot metatdata on a node
func add_meta_to_node(node : Node, meta : Dictionary) -> void:
	for key in meta:
		if key in meta and key != "items":			
			node.set_meta(key.replace("@","AT").validate_node_name(), meta[key])	


# Converts an IIIF meta scene to a Godot scene	
func create_node3d(scene_meta : Dictionary) -> Node3D:
	var node = Node3D.new()
	add_meta_to_node(node, scene_meta)	
			
	if "backgroundColor" in scene_meta:
		create_world_environment_node(node, scene_meta["backgroundColor"])
	return node

# Creates an IIIF annotation node which will hold an asset
func create_annotation_node(item : Dictionary):
	var node : Node = null
	if item["body"]["type"] == "Model":
		node = Node3D.new()
		var asset : Node3D = _get_imported_asset(item["body"]["id"])		
		node.add_child(asset)
	elif "source" in item["body"]:
		for source in item["body"]["source"]:
			if source["type"] == "Model":
				node = Node3D.new()
				var asset : Node3D = _get_imported_asset(source["id"])	
				node.add_child(asset)
	elif item["body"]["type"] == "Image":
		node = Node2D.new()
		var asset : Sprite2D = _get_imported_image(item["body"]["id"])	
		node.add_child(asset)
	else:
		node = Node.new()
	return node


# Sets background colour
func create_world_environment_node(parent_node : Node3D, color : String) -> void:
	print_debug("Adding background colour: " + color)
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html(color)
	world_env.environment = env
	world_env.name = "Background"
	parent_node.add_child(world_env)
	print_debug("Adding owner to world background")


# Generates a filename for the Godot Scene from the manifest URL	
func generate_output_filename(url : String) -> String:
	return "res://" + url.get_file().replace(url.get_extension(), "tscn").validate_filename()
	

# Converts a download URL into an internal resource reference
func get_filename_from_url(url : String) -> String:
	return "res://%s/%s" % [import_dir, url.get_file()]
	
	
# Imports a 3d asset from the web
func import_asset(url : String, type : String) -> void:
	ensure_import_dir_exists()
	print_debug("Downloading " + get_filename_from_url(url))
	current_download_url = url
	current_download_type = type
	if type != "Model":
		http_request.set_download_file(get_filename_from_url(current_download_url))
	http_request.request_completed.connect(_on_asset_downloaded)
	http_request.request(url)
	assets_to_download = assets_to_download + 1


# Handles completed web request to download asset from web
func _on_asset_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	http_request.request_completed.disconnect(_on_asset_downloaded)
	http_request.set_download_file("")
	# If there was an HTTP then signal it and stop
	if (signal_if_alert_message(response_code)):
		print_debug(response_code)
		#return
		
	# Extra handling for models
	if current_download_type == "Model":
		var gstate = GLTFState.new()
		gstate.base_path = "res://IIIFAssetImport/"
		var gimporter = GLTFDocument.new()	
		var err = gimporter.append_from_buffer(body, "", gstate)
		if err != OK:
			print_debug("Error importing GLB: " + str(err))
			# return
		gimporter.write_to_filesystem(gstate, get_filename_from_url(current_download_url) )
	
	assets_to_download = assets_to_download - 1
	if status == StatusFlag.ALL_ASSETS_REQ && assets_to_download == 0:
		change_status(StatusFlag.ASSETS_DL_COMPLETE)


# Gets a asset from the resources area		
func _get_imported_asset(url) -> Node3D:
	# Import asset as normal from resources
	var asset_scene = load(get_filename_from_url(url))	
	if not asset_scene:
		print_debug("Failed to load the asset.", url)
	var asset : Node3D = asset_scene.instantiate()
	return asset

# Load in an image as a sprite, needs a node2d parent
func _get_imported_image(url) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = url.get_file().replace("." + url.get_extension(), "")
	sprite.texture = load(get_filename_from_url(url))
	return sprite
	
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
	# Set up export filename
	output_filename = generate_output_filename(url);
	print_debug("Output filename: " + output_filename)


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
