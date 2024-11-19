# BattSelector (V2 Branch)
Battery selection widget for FrSky Ethos.  Tested on Ethos Version 1.5.18 only.<br>
Utilizes Rotorflight ModelID telemetry sensor to list only batteries tied to current ID.

## Installation

## Features

## Settings/Configuration

## Notes
  - This widget uses the mAh sensor and creates the Percent Remaining sensor, so you don't need one from any other source. If you're using Rotorflight, disable the "Battery Charge Level" sensor.<br>
  ![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/RotorflightFuel.png?raw=true)<br>
  You should also ensure that you only have one mAh sensor.  I do not know what will happen if you have multiple and at this point I'm scared to try.
  

### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
  - Version 1.1 - Small Update.  Fixed/improved mAh sensor detection.
  - Version 1.2 - Removed % Display from Widget due to complications with Lua Forms.  Improved compatibility with Ethos 1.5.18
  - Version 2.0 (WIP) - Massive refactor of the entire script.  Adds Battery naming, Model ID from Rotorflight, Favorites
