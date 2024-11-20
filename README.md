# BattSelector V2
On-widget battery selection and percent remaining calculator for FrSky Ethos.<br>
Tested on Ethos Version 1.5.18 only.<br>

## Features

## Settings/Configuration

## Prerequisites
1. You should have a mAh sensor from somewhere. Rotorflight, ESC with S.Port telemetry, or a calculated mAh sensor from a Current source. 
      This script works by scanning the first 25 telemetry sensors and picks the first one that has the unit mAh.  If you have more than  one sensor with the unit mAh, it will only use the first one, so make sure the first one is the one you want being used for calculations.
2. You do not need to have a Remaining (Percent) sensor from somewhere else.  This widget creates and updates its own Remaining (Percent) sensor, which you can then use for Alerts, Value display widgets, etc.
      The Remaining (Percent) sensor that it creates has a PhysID of 0x11.  0x11 was chosen because 0x10 is often used by other devices (e.g. Rotorflight), so by having the PhysID be 0x11, this allows both to coexist.

## Installation
Method 1. Download BattSelector.zip from the latest [Release](https://github.com/BladeScraper-Designs/Ethos_BattSelector/releases) and use Ethos Suite LUA Development tools to install it.<br>
Method 2. Download [main.lua](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/V2/scripts/BattSelector/main.lua) directly and place it in a folder called BattSelector in your scripts directory. 

### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
  - Version 1.1 - Small Update.  Fixed/improved mAh sensor detection.
  - Version 1.2 - Removed % Display from Widget due to complications with Lua Forms.  Improved compatibility with Ethos 1.5.18
  - Version 2.0 (WIP) - Massive refactor of the entire script.  Adds Battery naming, Model ID from Rotorflight, Favorites, Voltage Detection
