# IIIF 3D Importer
# By Liam Green-Hughes, British Library, 2025
# Example imports:
# https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 3D: https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json
# 2D: https://iiif.io/api/cookbook/recipe/0001-mvm-image/ https://iiif.io/api/cookbook/recipe/0001-mvm-image/manifest.json

@tool

extends IIIF
class_name IIIFImporter

# Name of file as on disc (with .tscn)
var output_filename : String = ""

# Base node of a scene
var root_node : Node = null

# Reference to first model in scene, if no cameras then we can point a default camera at it
var first_model : Node3D = null

# Reference to the World Environment node (if there is one)
var world_env_node : WorldEnvironment = null

# List of assets requested from the downloader but not received yet
var awaiting_assets : Dictionary = {}

var asset_file_locations : Dictionary = {}

var camera_found : bool = false

# Variables changable in Inspector


@export var asset_downloader : IIIFAssetDownloader  = null
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
	# assets_to_download = 0	
	asset_downloader.clear_queue()
	# Recursive import
	import_assets_in_manifest(manifest_json["items"])
	change_status(StatusFlag.ALL_ASSETS_REQ)


#func create_iiif_manifest_root_node() -> void:
#	root_node = Node.new()
#	root_node.name = "IIIF Manifest"
#	add_meta_to_node(root_node, iiif_json)
#	print_debug("Created Root Node")
	

# Called when assets have been downloaded and tree can now be worked on
func resume_manifest_processing() -> void:
	print_debug("Resuming parsing items")
	
	# Create GODOT scene root		
	#create_iiif_manifest_root_node()
	parse_items(null,[iiif_json])
	
	# Add a default camera if there is not one in the scene
	if not camera_found:
		add_default_camera(first_model)
		
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

# Goes through manifest and looks for assets to be downloaded		
func import_assets_in_manifest(items : Array) -> void:
	for item in items:
		if item["type"] == "Annotation":
			if "source" in item["body"]:
				for source in item["body"]["source"]:
					asset_downloader.queue_asset_download(source["id"], source["type"])
					awaiting_assets[source["id"]] = source["type"]
			elif "format" in item["body"]:
				asset_downloader.queue_asset_download(item["body"]["id"], item["body"]["type"])
				awaiting_assets[item["body"]["id"]] = item["body"]["type"]
		if "items" in item:
			import_assets_in_manifest(item["items"])	

# Every node must have a unique name in Godot
func name_iiif_node(item : Dictionary) -> String:
	var name = 	"IIIF " + item["type"] + " (" + item["id"].get_slice("://", 1) + ")"
	return name.validate_node_name()
	
# Recursive parser for "items" in IIIF manifest JSON
# If parent_node is null then a root node will be created
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
		child_node.name = name_iiif_node(item)
		add_meta_to_node(child_node, item)
		
		# If parent node is null then we are creating the root node
		if parent_node == null:
			root_node = child_node	
		else:
			parent_node.add_child(child_node)
			child_node.set_owner(root_node)
			for subnode in child_node.get_children():
				subnode.set_owner(root_node)
			
		# Add position
		add_position_to_node(child_node, item)
		
		# Add rotation
		add_transform_to_node(child_node, item)
		
		# If lookAt set, find out target and rotate towards it
		add_look_at_to_node(child_node, item)
		
		# Process this instance of items recursively	
		if "items" in item:
			child_node = parse_items(child_node, item["items"])
		if "annotations" in item:
			print_debug("******************* FOUND ANNOTATIONS")
			child_node = parse_items(child_node, item["annotations"])	
		
		if 	"target" in item and item["target"] is Dictionary and item["target"]["type"] == "SpecificResource":
			# ignore for now
			pass
		elif "target" in item and item["target"] is Dictionary:
			var target_node : Node3D = Node3D.new()
			target_node.name = name_iiif_node(item["target"])
			add_meta_to_node(target_node, item["target"])
			child_node.add_child(target_node)
			target_node.set_owner(root_node)
			if "items" in item["target"]:
				parse_items(target_node, item["target"]["items"])
			if "annotations" in item["target"]:
				parse_items(target_node, item["target"]["annotations"])
			if "scope" in item["target"]:
				var scope_node : Node3D = Node3D.new()
				scope_node.name = name_iiif_node(item["target"]["scope"])
				add_meta_to_node(scope_node, item["target"]["scope"])
				target_node.add_child(scope_node)
				scope_node.set_owner(root_node)
				parse_items(scope_node, [item["target"]["scope"]["target"]])		
	return parent_node
		

func add_position_to_node(node : Node, meta : Dictionary) -> void:
	if "target" in meta and "selector" in meta["target"]:

		# TODO select position space based on object identified as source
		for selector in meta["target"]["selector"]:
			if selector["type"] == "PointSelector":
				print_debug("Positioning")
				if node is Node2D:
					node.position = Vector2(selector["x"], selector["y"])
				if node is Node3D:
					node.position = Vector3(selector["x"], selector["y"], selector["z"])

# Set rotation and scaling on a 3D model 
func add_transform_to_node(node : Node, meta : Dictionary) -> void:
	if "body" in meta and "transform" in meta["body"]:
		# TODO select position space based on object identified as source
		for transform in meta["body"]["transform"]:
			var xyz = Vector3(transform["x"], transform["y"], transform["z"])
			if transform["type"] == "RotateTransform":
				print_debug("Rotating")
				if node is Node3D:
					node.rotation_order = EULER_ORDER_XYZ
					node.rotation_degrees = xyz
					print_debug(xyz)
			elif transform["type"] == "ScaleTransform":
				print_debug("Scaling")
				if node is Node3D:
					node.scale = xyz
					print_debug(xyz)
			elif transform["type"] == "TranslateTransform":
				print_debug("Translate")
				if node is Node3D:
					node.translate(xyz) 
					print_debug(xyz)

func ensure_float(number : Variant) -> float:
	if number is float:
		return number
	if number is String:
		return number.to_float()
	else:
		return float(number)
	
# Works out coordinates for a lookAT direction	
func add_look_at_to_node(node, meta : Dictionary) -> void:
	var point = Vector3(0,0,0)
	if "body" in meta and "lookAt" in meta["body"]:
		var lookAt = meta["body"]["lookAt"]
		if lookAt["type"] == "PointSelector":
			point = Vector3(ensure_float(lookAt["x"]), ensure_float(lookAt["y"]), ensure_float(lookAt["z"]))
		elif lookAt["type"] == "Annotation":
			var target = find_node_by_id_and_type(lookAt["id"], lookAt["type"])
			if target is Node3D:
				point = target.position
			if target == null:
				print_debug("**** LOOKAT TARGET NOT FOUND *****")
		print_debug("*** Adding lookAt")
		print_debug(point)
		node.look_at_from_position(node.position, point)
	
# Converts IIIF metadata to Godot metatdata on a node
func add_meta_to_node(node : Node, meta : Dictionary) -> void:
	for key in meta:
		if key in meta and key != "items":			
			node.set_meta(key.replace("@","AT").validate_node_name(), meta[key])	


func find_node(node : Node):
	for child in node.get_children():
		print_debug(child.name)
		print_debug(child.get_meta("type"))
		var target : Node = null
		if child.get_meta("type") == "Model":
			print_debug("FOUND MODEL")
			target = child.get_parent()
			break
		else:
			for grandchild in child.get_children():
				target = find_node(grandchild)
				if target != null:
					break
		return target

# Adds a camera to the scene, which looks at the first model
func add_default_camera(target : Node3D) -> void:	
	if target == null:
		print("Could not create a default camera as could not find a model to point it at.")
		return

	for child in target.get_children():
		print_debug(child.name)
		if child is MeshInstance3D:
			var aabb : AABB = child.get_aabb()
			var model_size = aabb.size
			var model_centre : Vector3 = aabb.get_center()
			var camera_position = Vector3(model_centre.x, model_centre.y, aabb.size.y)
			var camera = Camera3D.new();
			root_node.add_child(camera)
			camera.set_owner(root_node)
			camera.name = "Default Camera"
			camera.position = camera_position
			camera.look_at_from_position(camera_position, model_centre)
			
# Converts an IIIF meta scene to a Godot scene	
func create_node3d(scene_meta : Dictionary) -> Node3D:
	var node = Node3D.new()
	add_meta_to_node(node, scene_meta)	
			
	#if "backgroundColor" in scene_meta:
	#	set_background_colour(scene_meta["backgroundColor"])
	return node

# Creates a child node with IIIF metadata for a model
func create_model_node(id : String, body : Dictionary) -> Node3D:
	var node = Node3D.new()
	var asset : Node3D = _get_imported_asset(id)	
	asset.name = name_iiif_node(body)
	add_meta_to_node(asset, body)	
	node.add_child(asset)
	if first_model == null:
		first_model = asset
	return node
	
func create_comment_node(body : Variant) -> Node3D:
	var node : Node3D = null
	if body is String:
		node = Label3D.new()
		node.text = body
	elif body is Dictionary:
		node = Node3D.new()
		var child_node = Label3D.new()
		child_node.name = name_iiif_node(body)
		add_meta_to_node(child_node, body)
		child_node.text = body["value"]		
		node.add_child(child_node)
	else:
		print("Annotation bodyValue is of unknown type")
	return node
	
# Creates an IIIF annotation node which will hold an asset
func create_annotation_node(item : Dictionary):
	var node : Node = null
	if "body" in item:
		if item["body"]["type"] == "Model":
			node = create_model_node(item["body"]["id"], item["body"])
		elif "source" in item["body"]:
			for source in item["body"]["source"]:
				if source["type"] == "Model":
					node = create_model_node(source["id"], item["body"])
		elif item["body"]["type"] == "Image":
			node = Node2D.new()
			var asset : Sprite2D = _get_imported_image(item["body"]["id"])
			add_meta_to_node(asset, item["body"])	
			node.add_child(asset)
		elif item["body"]["type"].containsn("Light"):
			node = Node3D.new()
			var light = make_light_node(item["body"]) 
			add_meta_to_node(light, item["body"])
			node.add_child(light)
		elif item["body"]["type"].containsn("Camera"):
			node = Node3D.new()
			camera_found = true
			var camera = make_camera_node(item["body"]) 
			add_meta_to_node(camera, item["body"])
			node.add_child(camera)
		else:
			node = Node.new()
	
	# var child_node : Node3D = Node3D.new()
	# Annotations with comments
	if "commenting" in item["motivation"]:
		if "bodyValue" in item:
			node = create_comment_node(item["bodyValue"])
		if "body" in item:
			node = create_comment_node(item["body"])
			
		
	return node
	
func prop_or_default(section : Dictionary, property_name : String, default_value : Variant) -> Variant:
	if property_name in section:
		return section[property_name]
	return default_value

func make_camera_node(cameraBodySection : Dictionary) -> Camera3D:
	print_debug("*** MAKING CAMERA NODE ***")
	var camera : Camera3D = Camera3D.new()
	# Properties for camera
	var fov : float = prop_or_default(cameraBodySection, "fov", 75.0) 
	var near : float = prop_or_default(cameraBodySection, "near", 0.05)
	var far : float = prop_or_default(cameraBodySection, "far", 4000)
	var size : float = prop_or_default(cameraBodySection, "size", 1)
	
	if cameraBodySection["type"] == "PerspectiveCamera":
		camera.set_perspective(fov, near, far)
		
	elif cameraBodySection["type"] == "OrthographicCamera":
		camera.set_orthogonal(size, near, far)
	
	else:
		print("Camera is of an unknown type")
	camera.name = name_iiif_node(cameraBodySection)
	return camera
	
# Set up lighting nodes
func make_light_node(lightBodySection : Dictionary) -> Node:
	var node : Node = null
	if lightBodySection["type"] == "AmbientLight":
		node = create_ambient_light_node(lightBodySection) 
	elif lightBodySection["type"] == "DirectionalLight":
		node = DirectionalLight3D.new()
	elif lightBodySection["type"] == "PointLight":
		node = OmniLight3D.new()
	elif lightBodySection["type"] == "SpotLight":
		node = SpotLight3D.new()
	else:
		print("Light is of an unknown type")
		node = Node.new()
	
	# Common
	
	# Jump out if we made a default node or AmbientLight
	if node is not Light3D:
		return node
		
	node.name = name_iiif_node(lightBodySection)
			
	if "color" in lightBodySection:
		node.light_color = Color(lightBodySection["color"])
		
	if "intensity" in lightBodySection:
		if lightBodySection["unit"] == "relative":
			node.light_energy = lightBodySection["unit"].to_float() * 256
		elif lightBodySection["unit"] == "lumens":
			node.light_intensity_lumens = lightBodySection["unit"].to_float()
		elif lightBodySection["unit"] == "lux":
			node.light_intensity_lux = lightBodySection["unit"].to_float()
		else:
			print("Unknown light intensity unit")
	
	# Set lights to be on bake mode by default as suitable for most use cases	
	node.light_bake_mode = default_lighting_bake_mode
		
	return node
	
func create_world_environment_node() -> void:
	# if no world environment yet, create one
	world_env_node = WorldEnvironment.new()
	var env = Environment.new()
	world_env_node.environment = env
	world_env_node.name = "WorldEnvironment"
	root_node.add_child(world_env_node)
	world_env_node.set_owner(root_node)
	
	
func create_ambient_light_node(lightBodySection : Dictionary) -> Node3D:
	if world_env_node == null:
		create_world_environment_node()
	print_debug("Adding Ambient Light: ")
	var env = world_env_node.environment
	env.background_mode = Environment.BG_COLOR
	if "color" in lightBodySection:
		env.ambient_light_color = Color(lightBodySection["color"])
	if "value" in lightBodySection and lightBodySection["unit"] == "relative":
		env.ambient_light_energy = lightBodySection["value"].to_float() * 256
	world_env_node.environment = env
	var node = Node3D.new()
	node.name = "AmbientLight (See WorldEnvironment) (" + lightBodySection["id"] + ")"
	return node
			
# Sets background colour
func set_background_colour(color : String) -> void:
	if world_env_node == null:
		create_world_environment_node()
	print_debug("Adding background colour: " + color)
	var env = world_env_node.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html(color)
	world_env_node.environment = env

# FInd a node in the scene tree by id and type
func find_node_by_id_and_type(id : String, type : String) -> Node:
	var node_name : String = name_iiif_node({"id": id, "type": "Model"})
	var target : Node = root_node.find_child(node_name, true, true)
	return target
	
# Generates a filename for the Godot Scene from the manifest URL	
func generate_output_filename(url : String) -> String:
	return "res://" + url.get_file().replace(url.get_extension(), "tscn").validate_filename()
	

# Gets a asset from the resources area		
func _get_imported_asset(url) -> Node3D:
	# Import asset as normal from resources
	var asset_scene : Resource = load(asset_file_locations[url])	
	if not asset_scene:
		print_debug("Failed to load the asset.", url)
	var asset : Node3D = asset_scene.instantiate()
	return asset

# Load in an image as a sprite, needs a node2d parent
func _get_imported_image(url) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.name = url.get_file().replace("." + url.get_extension(), "")
	sprite.texture = load(asset_file_locations[url])
	return sprite
	



# Quick check to see if a URL is valid at face value
func is_valid_url(raw_url) -> bool:
	var url = raw_url.strip_edges(true, true)
	if (url == "" || url.left(4) != "http"):
		print_debug("The URL %s is not valid." % url)
		return false
	else:
		return true

# Get the IIIF manifest from the web	
func import_manifest_from_url(url) -> void:
	asset_downloader.clear_queue()
	asset_downloader.queue_asset_download(url, "Manifest")
	output_filename = generate_output_filename(url);
	print_debug("Output filename (for scene): " + output_filename)
	change_status(StatusFlag.REQ_MANIFEST)

func _on_iiif_asset_downloader_manifest_received(json: Dictionary) -> void:
	change_status(StatusFlag.MANIFEST_DL_COMPLETE)
	process_iiif_json(json)


func _on_iiif_asset_downloader_download_complete(url: String, type: String, file_location: String) -> void:
	awaiting_assets.erase(url)
	asset_file_locations[url] = file_location
	if (awaiting_assets.is_empty()):
		change_status(StatusFlag.ASSETS_DL_COMPLETE)

func _on_iiif_asset_downloader_error_notification(error_message: String) -> void:
	change_status(StatusFlag.ERROR)
	print_debug(error_message)
