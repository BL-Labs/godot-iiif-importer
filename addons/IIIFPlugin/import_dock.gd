@tool
extends Control

@onready var url_entry : TextEdit = $URLEntry
@onready var errorAlert : AcceptDialog = $"Error Alert"
@onready var importer : IIIFImporter = $IIIFImporter

# Run when component starts
func _ready():
	importer.alert_message.connect(_alert)


# Alert dialogue, used to show HTTP errors
func _alert(message : String) -> void:
	errorAlert.dialog_text = message
	errorAlert.popup_centered()	

# Run when the import button is pressed. This should read in the URL from the text box and start work
func _on_import_button_pressed() -> void:
	var url = url_entry.text
	# For convenience, convert github urls to raw github urls (if applicable)
	if (url.findn("https://github.com/") == 0):
		url = url.replacen("https://github.com/", "https://raw.githubusercontent.com/").replacen("blob/", "refs/heads/")
		print_debug("[Info] Converted GitHub URL to raw version")
		
	if importer.is_valid_url(url):
		importer.default_lighting_bake_mode = $OptionButton.get_selected_id()
		importer.import_manifest_from_url(url)
	else:
		_alert("The URL entered is not a valid IIF manifest.")
