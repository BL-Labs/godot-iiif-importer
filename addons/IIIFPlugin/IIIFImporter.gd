# IIIF 3D Importer
# By Liam Green-Hughes, British Library, 2025
# Example imports:
# https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 3D: https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 2D: https://iiif.io/api/cookbook/recipe/0001-mvm-image/ https://iiif.io/api/cookbook/recipe/0001-mvm-image/manifest.json

@tool
class_name IIIFImporter extends IIIFPluginInternal

# Name of file as on disc (with .tscn)
var output_filename : String = ""

# Base node of a scene
var root_node : Node = null


# Reference to the World Environment node (if there is one)
var world_env_node : WorldEnvironment = null

# List of assets requested from the downloader but not received yet
var awaiting_assets : Dictionary = {}
# Variables changable in Inspector


@export var asset_downloader : IIIFAssetDownloader  = null
@export var node_maker : IIIFNodeMaker = null
@export var default_lighting_bake_mode : Light3D.BakeMode = Light3D.BakeMode.BAKE_STATIC

# A reference to the EditorFileSYstem, used for scanning
var resource_fs : EditorFileSystem = null

# IIIF manifest
var iiif_json : Dictionary  = {}

enum StatusFlag {
	IDLE,
	REQ_MANIFEST,
	MANIFEST_DL_COMPLETE,
	REQ_ASSETS,
	ALL_ASSETS_REQ,
	ASSETS_DL_COMPLETE,
	SCANNING,
	BUILD_SCENE,
	ERROR
}

# Current operation of import plugin
var status : StatusFlag = StatusFlag.IDLE

# Signals
# Fired when there is an http error status on a request
signal alert_message(err_msg : String)

signal scanning_complete

# Godot function run whan plugin starts
func _ready():
	if (!resource_fs):
		resource_fs = EditorInterface.get_resource_filesystem()
	scanning_complete.connect(resume_manifest_processing)
	change_status(StatusFlag.IDLE)
	

# Godot function run on every frame
# This will monitor the resource scanner
func _process(delta : float) -> void:
	# When all downloads are complete the get Godot to scan the assets file
	if status == StatusFlag.ASSETS_DL_COMPLETE:
		resource_fs.scan_sources()
		change_status(StatusFlag.SCANNING)
		return

	# Start building the scene once all of the assets have downloaded
	if status == StatusFlag.SCANNING && !resource_fs.is_scanning():			
		change_status(StatusFlag.BUILD_SCENE)
		scanning_complete.emit()
		return

#
# ENTRY POINT FROM import_dock.gd
#

# Get the IIIF manifest from the web	
func import_manifest_from_url(url) -> void:
	asset_downloader.clear_queue()
	asset_downloader.queue_asset_download(url, "Manifest")
	output_filename = generate_output_filename(url);
	print_debug("[info] Output filename (for scene): " + output_filename)
	change_status(StatusFlag.REQ_MANIFEST)

#
# UTILITY/HELPER CODE
#
# Change current status of import plugin
func change_status(new_status : StatusFlag):
	status = new_status
	print_debug("[Info] New status is now: ", StatusFlag.find_key(status))
	# If status is idle, reset the node maker
	if (new_status == StatusFlag.IDLE):
		node_maker.reset()

## Every node must have a unique name in Godot
#func name_iiif_node(item : Dictionary) -> String:
	#var name = 	"IIIF " + item["type"]
	#if "id" in item:
		#name = name + " (" + item["id"].get_slice("://", 1) + ")"
	#return name.validate_node_name()
	


# Quick check to see if a URL is valid at face value
# used in import_dock.gd
func is_valid_url(raw_url) -> bool:
	var url = raw_url.strip_edges(true, true)
	if (url == "" || url.left(4) != "http"):
		print_debug("[Error] The URL %s is not valid." % url)
		return false
	else:
		return true
		
#
# SCENE HELPER FUNCTIONS
#			


# Converts IIIF metadata to Godot metatdata on a node
#func add_meta_to_node(node : Node, meta : Dictionary) -> void:
#	for key in meta:
#		if key in meta and key != "items":			
#			node.set_meta(key.replace("@","AT").validate_node_name(), meta[key])	

# Generates a filename for the Godot Scene from the manifest URL	
func generate_output_filename(url : String) -> String:
	return "res://" + url.get_file().replace(url.get_extension(), "tscn").validate_filename()

# Saves the output godot scene to disc
func save_godot_scene() -> void:
	var scene = PackedScene.new()
	scene.pack(root_node)
	ResourceSaver.save(scene, output_filename)

#
# PRELOAD ASSETS
#
	
# Parses an IIIF manifest file and tries to convert it to a Godot scene
# Processing of the tree will be deferred while assets are downloaded
func process_iiif_json(manifest_json : Dictionary) -> void:
	# Copy Metadata
	iiif_json = manifest_json
	change_status(StatusFlag.REQ_ASSETS)
	# assets_to_download = 0	
	asset_downloader.clear_queue()
	# Recursive import
	import_assets_in_manifest(manifest_json["items"])
	change_status(StatusFlag.ALL_ASSETS_REQ)

# Goes through manifest and looks for assets to be downloaded		
func import_assets_in_manifest(items : Array) -> void:
	for item in items:
		if item["type"] == "Annotation":
			if "source" in item["body"]:
				for source in item["body"]["source"]:
					add_asset(source["id"], source["type"])
			elif "format" in item["body"]:
				add_asset(item["body"]["id"], item["body"]["type"])
		if "items" in item:
			import_assets_in_manifest(item["items"])	

func add_asset(id : String, type : String):
	if type not in ["Model", "Image", "Manifest"]:
		return
	asset_downloader.queue_asset_download(id, type)
	awaiting_assets[id] = type
					
func _on_iiif_asset_downloader_download_complete(url: String, type: String, file_location: String) -> void:
	awaiting_assets.erase(url)
	node_maker.set_asset_file_location(url, file_location)
	if (awaiting_assets.is_empty()):
		change_status(StatusFlag.ASSETS_DL_COMPLETE)

func _on_iiif_asset_downloader_manifest_received(json: Dictionary) -> void:
	change_status(StatusFlag.MANIFEST_DL_COMPLETE)
	process_iiif_json(json)

func _on_iiif_asset_downloader_error_notification(error_message: String) -> void:
	change_status(StatusFlag.ERROR)
	print_debug(error_message)
				
#
# PARSE IIIF MANIFEST
#

# Called when assets have been downloaded and tree can now be worked on
func resume_manifest_processing() -> void:
	print_debug("[Info] Resuming parsing items")
	
	# Create GODOT scene root/manifest root
	root_node = node_maker.create_manifest(iiif_json)
	node_maker.default_lighting_bake_mode = default_lighting_bake_mode
	node_maker.world_env_node = world_env_node
	
	if "items" in iiif_json:
		parse_items(root_node,iiif_json["items"])
	if "annotations" in iiif_json:
		parse_items(root_node,iiif_json["annotations"])
	
	# Add a default camera if there is not one in the scene
	if not node_maker.is_camera_created:
		print_debug("[Info] Creating default camera")
		node_maker.create_default_camera(root_node)
		
	# Save scene
	save_godot_scene()
	change_status(StatusFlag.IDLE)
	
# Recursive parser for "items" in IIIF manifest JSON
# If parent_node is null then a root node will be created
func parse_items(parent_node : Node, items : Array) -> Node3D:	
	var child_node : Node = null
	# process manifest
	for item in items:
		# Act on specific kinds of nodes
		if item["type"] == "Scene":
			child_node = node_maker.create_scene(item)
		elif item["type"] == "AnnotationPage":
			child_node = node_maker.create_annotation_page(item)
		elif item["type"] == "Annotation":
			child_node = node_maker.create_annotation_node(item)
		elif item["type"] == "Choice":
			child_node = node_maker.create_choice(item)
		else:
			print_debug("[Error] Unknown node type: " + item["type"])
			child_node = node_maker.create_iiif_node(Node.new(), item)
		
		# otherwise add to parent
		parent_node.add_child(child_node)
		child_node.set_owner(root_node)
		for subnode in child_node.get_children():
			subnode.set_owner(root_node)
			
		# Add position
		node_maker.add_position_to_node(child_node, item)
		
		# Add rotation
		node_maker.add_transform_to_node(child_node, item)
		
		# If lookAt set, find out target and rotate towards it
		node_maker.add_look_at_to_node(child_node, item)
		
		# Process this instance of items recursively	
		if "items" in item:
			child_node = parse_items(child_node, item["items"])
		if "annotations" in item:
			child_node = parse_items(child_node, item["annotations"])	
		if "target" in item:
			if "scope" in item["target"]:
				child_node = parse_items(child_node, [item["target"]["scope"]])
			if "items" in item["target"]:
				child_node = parse_items(child_node, item["target"]["items"])				
			
		# Do this another way?!	
		#if "target" in item:
		#	child_node = parse_items(child_node, [item["target"]])	
		# Not sure if this should be here
		#if "scope" in item:
		#	child_node = parse_items(child_node, [item["scope"]])	
		
		# if 	"target" in item and item["target"] is Dictionary and item["target"]["type"] == "SpecificResource":
		#	# ignore for now see line 375
		#	print_debug("**** FOUND A SPECIFIC RESORURCE")
			
		#elif "target" in item and item["target"] is Dictionary:
			#var target_node : Node3D = Node3D.new()
			#target_node.name = name_iiif_node(item["target"])
			#add_meta_to_node(target_node, item["target"])
			#child_node.add_child(target_node)
			#target_node.set_owner(root_node)
			#if "items" in item["target"]:
				#parse_items(target_node, item["target"]["items"])
			#if "annotations" in item["target"]:
				#parse_items(target_node, item["target"]["annotations"])
			#if "scope" in item["target"]:
				#var scope_node : Node3D = Node3D.new()
				#scope_node.name = name_iiif_node(item["target"]["scope"])
				#add_meta_to_node(scope_node, item["target"]["scope"])
				#target_node.add_child(scope_node)
				#scope_node.set_owner(root_node)
				#parse_items(scope_node, [item["target"]["scope"]["target"]])		
	return parent_node
