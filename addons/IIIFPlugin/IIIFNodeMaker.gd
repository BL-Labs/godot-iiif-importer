@tool
## DO NOT ADD THIS NODE DIRECTLY
class_name IIIFNodeMaker extends IIIFPluginInternal

var root_node : Node = null
var world_env_node : WorldEnvironment = null
var default_lighting_bake_mode : Light3D.BakeMode

var asset_file_locations : Dictionary = {}

# Reference to first model in scene, if no cameras then we can point a default camera at it
var first_model : Node3D = null

# Will be set to true if a camera is found in the manifest (so no default camera needed)
var is_camera_created : bool = false

func reset() -> void:
	root_node = null
	world_env_node = null 
	first_model = null
	is_camera_created = false
	

func create_iiif_node(node : Node, meta : Dictionary) -> Node:
	node.name = name_iiif_node(meta)
	add_meta(node, meta)
	return node

# Every node must have a unique name in Godot
func name_iiif_node(item : Dictionary) -> String:
	var name = 	"IIIF " + item["type"]
	if "id" in item:
		name = name + " (" + item["id"].get_slice("://", 1) + ")"
	return name.validate_node_name()
	
# Converts IIIF metadata to Godot metatdata on a node
func add_meta(node : Node, meta : Dictionary) -> void:
	for key in meta:
		if key in meta and key != "items":			
			node.set_meta(key.replace("@","AT").validate_node_name(), meta[key])	

# Returns a default value for a dictionary property if it is missing	
func prop_or_default(section : Dictionary, property_name : String, default_value : Variant) -> Variant:
	if property_name in section:
		return section[property_name]
	return default_value

func set_asset_file_location(url, file_location):
	asset_file_locations[url] = file_location
	
# Make sure number provided is a float
func ensure_float(number : Variant) -> float:
	if number is float:
		return number
	if number is String:
		return number.to_float()
	else:
		return float(number)


# Find a node in the scene tree by id and type
func find_node_by_id_and_type(id : String, type : String) -> Node:
	var node_name : String = name_iiif_node({"id": id, "type": "Model"})
	var target : Node = root_node.find_child(node_name, true, true)
	return target
	
	
		
#func find_node(node : Node):
	#for child in node.get_children():
		#print_debug(child.name)
		#print_debug(child.get_meta("type"))
		#var target : Node = null
		#if child.get_meta("type") == "Model":
			#print_debug("FOUND MODEL")
			#target = child.get_parent()
			#break
		#else:
			#for grandchild in child.get_children():
				#target = find_node(grandchild)
				#if target != null:
					#break
		#return target
#
# Specific Node Types
#

#
# MANIFESTS
#

# Creates a root IIIF manifest node
func create_manifest(meta : Dictionary) -> Node:
	root_node = create_iiif_node(Node3D.new(), meta)
	return root_node

#
# CONTAINERS
#
func create_scene(meta : Dictionary) -> Node3D:
	var node = create_iiif_node(Node3D.new(), meta)
			
	if "backgroundColor" in meta:
		set_background_colour(meta["backgroundColor"])
	return node

#
# ANNOTATIONS
#
func create_annotation_page(meta : Dictionary) -> Node:
	return create_iiif_node(Node3D.new(), meta)
	
# Creates an IIIF annotation node which will hold an asset
func create_annotation_node(item : Dictionary):
	# TODO make sure sub node creation all works in the same way
	
	var node : Node3D = create_iiif_node(Node3D.new(), item)
	if "body" in item:
		if item["body"]["type"] == "Model":
			node.add_child(create_model_node(item["body"]["id"], item["body"]))
		elif "source" in item["body"]:
			for source in item["body"]["source"]:
				if source["type"] == "Model":
					node.add_child(create_model_node(source["id"], source))
		#elif item["body"]["type"] == "Image":
		#	var asset : Sprite2D = _get_imported_image(item["body"]["id"])
		#	add_meta_to_node(asset, item["body"])	
		#	node.add_child(asset)
		elif item["body"]["type"].containsn("Light"):
			node.add_child(create_light_node(item["body"]))
		elif item["body"]["type"].containsn("Camera"):
			node.add_child(create_camera_node(item["body"])) 
	
	# Annotations with comments
	if "commenting" in item["motivation"]:
		if "bodyValue" in item:
			node = create_comment_node(item["bodyValue"])
		if "body" in item:
			node = create_comment_node(item["body"])
			
		
	return node

#
# SUPPORTING RESOURCES
#

# Creates a child node with IIIF metadata for a model
func create_model_node(id : String, body : Dictionary) -> Node3D:
	var asset : Node3D = create_iiif_node( _get_imported_asset(id), body )	
	if first_model == null:
		first_model = asset
	return asset
	
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
	
func create_default_camera(root : Node):
	create_camera_looking_at(root, first_model)

# Adds a camera to the scene, which looks at the first model
func create_camera_looking_at(root : Node, target : Node3D) -> void:	
	if target == null || len(target.get_children()) == 0:
		print("Could not create a default camera as could not find a model to point it at.")
		return
		
	# Default look at position is to look at the top left of the object
	# If we find a mesh instance we can be more precise and look at the middle of the object
	var camera_position : Vector3 = Vector3(target.position.x, target.position.y, target.position.z + 10) ;
	var model_centre : Vector3 = target.position;

	for child in target.get_children():
		if child is MeshInstance3D:
			var aabb : AABB = child.get_aabb()
			var model_size = aabb.size
			model_centre = aabb.get_center()
			camera_position = Vector3(model_centre.x, model_centre.y, aabb.size.y)
			
	var camera = Camera3D.new();
	camera.name = "Default Camera"
	camera.position = camera_position
	camera.look_at_from_position(camera_position, model_centre)		
	root.add_child(camera)
	camera.set_owner(root)
	is_camera_created = true


func create_camera_node(cameraBodySection : Dictionary) -> Camera3D:
	print_debug("*** MAKING CAMERA NODE ***")
	var camera : Camera3D = create_iiif_node(Camera3D.new(), cameraBodySection)
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
	
	is_camera_created = true
	return camera


# Set up lighting nodes
func create_light_node(lightBodySection : Dictionary) -> Node:
	var node : Node = null
	if lightBodySection["type"] == "AmbientLight":
		node = create_ambient_light_node(lightBodySection) 
	elif lightBodySection["type"] == "DirectionalLight":
		node = create_iiif_node(DirectionalLight3D.new(), lightBodySection)
	elif lightBodySection["type"] == "PointLight":
		node = create_iiif_node(OmniLight3D.new(), lightBodySection)
	elif lightBodySection["type"] == "SpotLight":
		node = create_iiif_node(SpotLight3D.new(), lightBodySection)
	else:
		print("Light is of an unknown type")
		node = create_iiif_node(Node.new(), lightBodySection)
	
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
	


func create_world_environment_node() -> WorldEnvironment:
	# if no world environment yet, create one
	world_env_node = WorldEnvironment.new()
	var env = Environment.new()
	world_env_node.environment = env
	world_env_node.name = "WorldEnvironment"
	root_node.add_child(world_env_node)
	world_env_node.set_owner(root_node)
	return world_env_node
		
func create_ambient_light_node(meta : Dictionary) -> Node3D:
	if world_env_node == null:
		create_world_environment_node()
	print_debug("Adding Ambient Light: ")
	var env = world_env_node.environment
	env.background_mode = Environment.BG_COLOR
	if "color" in meta:
		env.ambient_light_color = Color(meta["color"])
	if "value" in meta and meta["unit"] == "relative":
		env.ambient_light_energy = meta["value"].to_float() * 256
	world_env_node.environment = env
	var node = Node3D.new()
	node.name = "AmbientLight (See WorldEnvironment) (" + meta["id"] + ")"
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

func create_comment_node(body : Variant) -> Node3D:
	var node : Node3D = null
	if body is String:
		node = create_iiif_node(Label3D.new(), body)
		node.text = body
	elif body is Dictionary:
		node = create_iiif_node(Node3D.new(), body)
		var child_node = create_iiif_node(Label3D.new(), body)
		child_node.text = body["value"]		
		node.add_child(child_node)
	else:
		print("Annotation bodyValue is of unknown type")
	return node

#
# TRANSFORM, ROTATION, ETC
#
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
