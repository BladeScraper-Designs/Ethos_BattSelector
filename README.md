# BattSelector
On-widget battery selection and percent remaining calculator for FrSky Ethos.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Main.png?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Select.png?raw=true)<br>
Read this ENTIRE Readme - it will answer most of your questions.

# Features
## On-Screen Battery Selection
This widget creates an on-widget form for selecting the battery you'll be flying with.  Put this widget right on your home screen and quickly and easily choose your battery and let the widget do the rest.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Select.png?raw=true)

## Optional Voltage Check On Connect
This widget features an optional (through Widget Configuration page) Voltage Check.  Upon first receiving telemetry, it estimates the cellcount based on the received voltage and if it is determined to be not fully charged, it pops up an alert telling you that you may have plugged in a not-fully-charged battery. The check is disabled after 30s to prevent the alert after takeoff, and is reset when telemetry stops to be ready for the next battery.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Voltage_Warning.png?raw=true)

## Rotorflight Model ID Telemetry Integration
If you're using this widget with Rotorflight 2.1, you can set the ModelID of each battery.  By doing this, when a valid Model ID telemetry sensor is present and active, the list of batteries in the widget will only show batteries that are tied to the current Model ID.  When a Model ID sensor is not present or present but not working (i.e. value is nil), the widget will list all batteries.<br>

As part of the Rotorflight Model ID Telemetry Integration, you can set up a "Favorite Battery" for each Model ID.  When a heli with the model ID is connected, it will default to your chosen Favorite battery for that ID.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Favorites.png?raw=true)

## Autmatic Model Bitmap
Also as part of Model ID Integration, you can set a default bitmap as well as a bitmap for each Model ID and it will automatically change the model bitmap to the one you select.  When there is no telemetry nor no valid ModelID, it will use your selected Default image.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/ID_Images.png?raw=true)

## Virtually Unlimited Batteries to Choose From
Unlike the previous version of the widget, which was limited to 5 batteries, this widget's only limitation in how many batteries you can have is the space available on the EEPROM used to store battery data.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Unlimited.png?raw=true)

# Configuration
## Batteries
Drop down the "Batteries" expansion panel and add/remove batteries as needed.  Give them a nice name, enter their capacity, and (optionally) tell the widget which Rotorflight ModelID it is for.  You can delete or clone any battery.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Batteries.png?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Batteries_Options.png?raw=true)

## Favorites
See [Rotorflight Model ID Telemetry Integration](#rotorflight-model-id-telemetry-integration) for more info.<br>

# Preferences
## Use Capacity
You can configure a Use Capacity or "fly-to" percentage, which is the percentage of the battery's nominal capacity you want to consume before landing.  When you hit 0% remaining, you've used that much.  Most people fly to 80-85%, and the default is 80%.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Preferences.png?raw=true)

## Enable Battery Voltage Check
Enable/Disable this setting to enable/disable the Battery Voltage Check on Connect feature.  When enabled, another option will be added so you can set the "Min Charged Coltage per Cell", which is the threshold below which the Low Voltage dialog will pop up.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure_Preferences_VoltageCheck.png?raw=true)


## Prerequisites
1. You should have a mAh sensor from somewhere. Rotorflight, ESC with S.Port telemetry, or a calculated mAh sensor from a Current source. 
      This script works by scanning the telemetry sensors and picks the first one that has the unit mAh.  If you have more than one sensor with the unit mAh, it will only use the first one, so make sure the first one is the one you want being used for calculations.
2. You do not need to have a Remaining (Percent) sensor from somewhere else.  This widget creates and updates its own Remaining (Percent) sensor, which you can then use for Alerts, Value display widgets, etc.
      The Remaining (Percent) sensor that it creates has a PhysID of 0x11.  0x11 was chosen because 0x10 is often used by other devices (e.g. Rotorflight), so by having the PhysID be 0x11, this allows both to coexist.
3. If you want to use the optional Voltage Check On Connect feature, you need to have a Voltage sensor called "Voltage".
4. If you want to use the optional Rotorflight Model ID Integration feature, you need to configure Rotorflight to send that telemetry sensor, and set each heli to its own unique ID (or the same ID if they share batteries).


## Installation
Method 1. Download BattSelector.zip from the latest [Release](https://github.com/BladeScraper-Designs/Ethos_BattSelector/releases) and use Ethos Suite LUA Development tools to install it.<br>
Method 2. Download [main.lua](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/scripts/BattSelector/main.lua) directly and place it in a folder called BattSelector in your scripts directory. 


### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
  - Version 1.1 - Small Update.  Fixed/improved mAh sensor detection.
  - Version 1.2 - Removed % Display from Widget due to complications with Lua Forms.  Improved compatibility with Ethos 1.5.18
  - Version 2.0 - Massive refactor of the entire script.  Adds Battery naming, Model ID from Rotorflight, Favorites, Voltage Detection
  - Version 2.2 - Adds Image selection for model ID
