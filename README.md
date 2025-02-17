# godot-iiif-importer
 Experimental Godot Addon to import IIIF 3D manifests

Extremely experimental IIIF importer for Godot 4.4 and above. It has only been tried with this manifest so far:
https://github.com/IIIF/3d/blob/main/manifests/1_basic_model_in_scene/model_origin.json

## Installation

Follow the instllation instructions at:
https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html

So for this repository:

![Image showing tick box for Ignore Asset Root](ignoreassetroot.png)

* Click the green "<> Code" button to access a drop down menu
* Click on Download ZIP and remember where you put it
* In Godot, open a project and go the "AssetLib"
* Click on "Import" and select your zip
* IMPORTANT: Make sure "Ignore Asset Root" is ticked
* After the plugin has been imported to you project click "Plugins" on the AssetLib window
* Click "On" next to the IIIF entry

## Usage
* A new panel should open on the left hand side of Godot, paste into the panel a URL of a IIIF 3D manifets file, e.g. https://raw.githubusercontent.com/IIIF/3d/refs/heads/main/manifests/1_basic_model_in_scene/model_origin.json.
* If you are copying a URL from GitHub, be sure to click the "Raw" button first to get the JSON file

## Screenshot
![Godot runnning the plugin after an export with an astronaut model in the 3D workspace](screenshot.png)

Have fun!