@tool
extends IIIF

class_name IIIFAssetDownloader

# TODO Authentication layer?
signal download_complete(url, type, file_location)

signal manifest_received(json : Variant)

signal error_notification(error_message)


# File currrently being downloaded
var current_download_url : String = ""
# Type of file being downloaded, e.g. model, image
var current_download_type : String = ""

# var assets_to_download : int = 0

var asset_download_queue : Dictionary = {}

# In project folder name for imported resources
@export var import_dir : String = "IIIFAssetImport"


# Godot HTTPRequest object, must be assigned in editor
@export var http_request : HTTPRequest = null

func clear_queue():
	asset_download_queue = {}
	


func queue_asset_download(url : String, type : String) -> void:
	print_debug("Adding " + url + " to queue")
	asset_download_queue[url] = type
	if current_download_url.is_empty():
		download_next_asset_in_queue()
		
	
func download_next_asset_in_queue() -> void:
	if not asset_download_queue.is_empty():
		var url = asset_download_queue.keys()[0]
		var type = asset_download_queue[url]
		import_asset(url, type)

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
		error_notification.emit("Failed to create import directory: %s" % result)
		return false
	# Directory now exists	
	return true

# Converts a download URL into an internal resource reference
func get_filename_from_url(url : String) -> String:
	return "res://%s/%s" % [import_dir, url.get_file()]
	

# Imports a 3d asset from the web
func import_asset(url : String, type : String) -> void:
	ensure_import_dir_exists()
	print_debug("Downloading " + get_filename_from_url(url))
	current_download_url = url
	current_download_type = type
	if type != "Model" and type != "Manifest":
		http_request.set_download_file(get_filename_from_url(current_download_url))
	http_request.request(url)
	#assets_to_download = assets_to_download + 1
	
# Emits a message corresponding with an HTTP error code
func signal_if_alert_message(response_code, current_download_url) -> bool:
	var err_msg : String = ""
	if response_code == 401:
		err_msg = "401 Not authorised."
	elif response_code == 404:
		err_msg = "404 Not Found."
	elif response_code >= 400:
		err_msg = "HTTP Error %s." % response_code
	
	err_msg = err_msg + "  URL: %s" % current_download_url
	
	if err_msg != "":
		error_notification.emit("Could not import asset at " + current_download_url + " " + err_msg)
		return true
		
	return false

# Handles completed web request to download asset from web
func on_asset_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print_debug("Got " + current_download_type + " " + current_download_url)
	http_request.set_download_file("")
	# If there was an HTTP then signal it and stop
	if (signal_if_alert_message(response_code, current_download_url)):
		return
		
	# Extra handling for models
	if current_download_type == "Model":
		var gstate = GLTFState.new()
		gstate.base_path = "res://IIIFAssetImport/"
		var gimporter = GLTFDocument.new()	
		var err = gimporter.append_from_buffer(body, "", gstate)
		if err != OK:
			error_notification.emit("Error importing GLB: " + str(err))
			# return
		gimporter.write_to_filesystem(gstate, get_filename_from_url(current_download_url) )
	
	# assets_to_download = assets_to_download - 1
	asset_download_queue.erase(current_download_url)
	# Send notification that the download is complete
	if current_download_type == "Manifest":
		print_debug("Sending manifest")
		send_json_manifest(body.get_string_from_utf8())
	else:
		print_debug("Sending file")
		download_complete.emit(current_download_url, current_download_type, get_filename_from_url(current_download_url))
	
	current_download_url = ""
	current_download_type = ""
	# Download next item in queue
	download_next_asset_in_queue()
	

# Parses string and turns it into JSON before sending it on via signal
func send_json_manifest(rawData : String) -> void:
	print_debug(rawData)
	var json = JSON.new()
	var parse_result = json.parse(rawData)
	
	if parse_result != OK:
		error_notification.emit("Could not parse manifest.")
		return
		
	manifest_received.emit(json.data)
	
