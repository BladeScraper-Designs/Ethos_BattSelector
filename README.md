# BattSelector
Battery selection and alerts widget for FrSky Ethos.  Requires Ethos Version 1.5.10 or higher.<br>
Perfect for flying multiple size batteries on a single model, or multiple aircraft on a single model file. Or Both.

## Features
  - On-Screen Widget-Based Battery Selection - No need to navigate menus to set flight battery<br>
  - Calculates Remaining Percentage automatically based on battery size<br>
  - Creates and updates "Remaining" Percentage Telemetry Sensor for use in Logic Switches and Alarms<br>
  - Set up to 5 Battery Sizes, from 0 to 10,000mAh<br>
  - Set Default Battery to either one of your configured sizes or "Last Used"<br>
  - Set "Use Capacity" Percentage for LiPo Protection

## Settings/Configuration
  - Number Of Batteries: 1 to 5 Different Battery Sizes<br>
  - Battery N: Set LiPo _Rated_ Capacity Here<br>
  - Default: Set to a specific battery if you want it to always default to that, or set to Last Used to default to whatever you used last time<br>
  - mAh Source Sensor: Currently DISABLED and HIDDEN.  You must have a mAh sensor called "Consumption" for this Lua to work currently.<br>
  - Use Capacity: Use this to set your Use(able) capacity.  Most people fly 80% of a battery and consider that "dead" (to preserve LiPo health).  The Percent Remaining reflects the remaining _usable_ capacity, e.g. 4000mAh when the battery is 5000mAh and Use Capacity set to 80%.

## Notes
  - Currently only works on widgets of size 256x100px.  More sizes will be added eventually.
  - Probably Really Buggy, Enjoy

### Version History
  - Version 1.0 - Initial Release.  Basic Functionality is there.  Only compatible with 256x100px widget size.  No mAh Sensor Selection Available.
