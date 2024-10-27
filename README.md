# BattSelector
Battery selection widget for FrSky Ethos.  Requires Ethos Version 1.5.10 or higher.<br>
Perfect for flying multiple size batteries on a single model, or multiple aircraft on a single model file. Or Both.
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Demo.gif?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Select.png?raw=true)

## Installation
Easiest method for install is to download the .zip from the latest Release and use Ethos Suite's Lua Development Tools menu to install it.<br>
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Installer.png?raw=true)

## Features
  - On-Screen Widget-Based Battery Selection - No need to navigate menus to set flight battery<br>
  - Automatically detects mAh (Consumption) sensor from any source (including calculated sensors from Current) and uses it for calculations
  - Calculates Remaining Percentage automatically based on battery size<br>
  - Creates and updates "Remaining" Percentage Telemetry Sensor for use in Logic Switches and Alarms<br>
  - Set up to 5 Battery Sizes, from 0 to 10,000mAh<br>
  - Set Default Battery to either one of your configured sizes or "Last Used"<br>
  - Set "Use Capacity" Percentage for LiPo Protection


## Settings/Configuration
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure.png?raw=true)
![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/Configure%20Batteries.png?raw=true)
  - Number Of Batteries: 1 to 5 Different Battery Sizes<br>
  - Battery N: Set LiPo _Rated_ Capacity Here<br>
  - Default: Set to a specific battery if you want it to always default to that, or set to Last Used to default to whatever you used last time<br>
  - Use Capacity: Use this to set your Use(able) capacity.  Most people fly 80% of a battery and consider that "dead" (to preserve LiPo health).  The Percent Remaining telemetry sensor and display reflects the remaining _usable_ capacity, e.g. 4000mAh when the battery is 5000mAh and Use Capacity set to 80%.

## Notes
  - This widget uses the mAh sensor and creates the Percent Remaining sensor, so you don't need one from any other source. If you're using Rotorflight, disable the "Battery Charge Level" sensor.<br>
  ![](https://github.com/BladeScraper-Designs/Ethos_BattSelector/blob/main/img/RotorflightFuel.png?raw=true)<br>
  You should also ensure that you only have one mAh sensor.  I do not know what will happen if you have multiple and at this point I'm scared to try.
  

### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
  - Version 1.1 - Small Update.  Fixed/improved mAh sensor detection.
  - Version 1.2 - Removed % Display from Widget due to complications with Lua Forms.  Improved compatibility with Ethos 1.5.18
