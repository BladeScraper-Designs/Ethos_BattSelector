# BattSelector
On-widget battery selection, percent remaining calculator and Alerts system for FrSky Ethos.<br>
Designed primarily for use with Rotorflight 2 and RFSUITE.  Read this ENTIRE Readme - it will answer most of your questions.

# Features
## On-Screen Battery Selection
This widget creates an on-widget form for selecting the battery you'll be flying with.  Put this widget right on your home screen and quickly and easily choose your battery and let the widget do the rest.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Selector.png?raw=true)

## Optional Voltage Check On Connect
This widget features an optional (through Widget Configuration page) Voltage Check.  Upon first receiving telemetry, it utilizes an array of sensors and sources to determine the charge level of your battery.  If the per-cell voltage is below a certain threshold, it will pop up a dialog warning that your battery may not be charged.  This check is delayed by 15 seconds after first connection to ensure proper 
nonzero telemetry voltage is coming through and is disabled after 60 seconds to prevent false alerts while flying.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Prefs.png?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/VoltageWarning.png?raw=true)

## Rotorflight Model ID Telemetry Integration
If you're using this widget with Rotorflight 2.1+, you can set the ModelID for each battery.  By doing this, when a valid Model ID telemetry sensor is present and active, the list of batteries in the widget will only show batteries that are tied to the current Model ID.  When a Model ID sensor is not present or present but not working (i.e. value is nil), the widget will list all batteries.<br>

As part of the Rotorflight Model ID Telemetry Integration, you can set up a "Favorite Battery" for each Model ID.  When a heli with the model ID is connected, it will default to your chosen Favorite battery for that ID.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Favorites.png?raw=true)

## Autmatic Model Bitmap
Also as part of Rotorflight Model ID Integration, you can set a default bitmap as well as a bitmap for each Model ID and it will automatically change the model bitmap to the one you select.  When there is no telemetry or no valid ModelID, it will use your selected Default image.  This overrides the "model bitmap" in Model Settings using the model.bitmap() function.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Images.png?raw=true)

# Configuration
## Batteries
Drop down the "Batteries" expansion panel and add/remove batteries as needed.  Use the Reorder/Edit mode to clone, delete, or move any battery in the list.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Batteries.png?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Batteries_Reorder.png?raw=true)

## Favorites
See [Rotorflight Model ID Telemetry Integration](#rotorflight-model-id-telemetry-integration) for more info.<br>

# Preferences
## Use Capacity
You can configure a Use Capacity or "fly-to" percentage, which is the percentage of the battery's nominal capacity you want to consume before landing.  When you hit 0% remaining, you've used that much.  Most people fly to 80-85%, and the default is 80%.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Preferences.png?raw=true)

### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
  - Version 1.1 - Small Update.  Fixed/improved mAh sensor detection.
  - Version 1.2 - Removed % Display from Widget due to complications with Lua Forms.  Improved compatibility with Ethos 1.5.18
  - Version 2.0 - Massive refactor of the entire script.  Adds Battery naming, Model ID from Rotorflight, Favorites, Voltage Detection
  - Version 2.2 - Adds Image selection for model ID
  - Version 3.0 - Massive Refactor of the entire script.  Adds battery cellcount and type, better voltage alert logic, Alerts feature, dynamic UI scaling for configuration page, and more.
