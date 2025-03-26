-- Lua Battery Selector and Alarm widget
-- Version: 3.0.0
local battsel = {}

-- Set to true to enable debug output for each function as required
battsel.useDebug = {
    fillFavoritesPanel = false,
    fillImagePanel = false,
    fillBatteryPanel = false,
    fillPrefsPanel = false,
    doBatteryVoltageCheck = false,
    updateRemainingSensor = false,
    getmAh = false,
    create = false,
    build = false,
    read = false,
    write = false,
    paint = false,
    wakeup = false,
    configure = false
}

-- Required libraries
local json = require("lib.dkjson") -- JSON library
local layouts = require("lib.layout") -- Layout library
local utils = require("lib.utils") -- Utility library

local read, write

-- Get radio information
local radio = system.getVersion()
local LCD_W, LCD_H = radio.lcdWidth, radio.lcdHeight
print("DEBUG(battsel): Radio: " .. radio.board)
print("DEBUG(battsel): LCD Width: " .. LCD_W .. " Height: " .. LCD_H)

local configLoaded = false  -- Flag to indicate if the configuration has been loaded yet

local formLines = {}
local formFields = {}

local favoritesPanel
local imagePanel
local batteryPanel
local prefsPanel

local rebuildWidget = false

-- Putting these here to remind myself to implement them later
battsel.source = {
    telem = nil,
    voltage = nil,
    consumption = nil,
    cells = nil,
    modelID = nil,
    percent = nil
}

local currentModelID = nil

--- Dynamically enables or disables specific form fields based on the current configuration.
--- This function evaluates the values in the `battsel.Config` table and adjusts the form fields
--- accordingly to ensure that only valid options are available to the user.
local function updateFieldStates()
    local updates = {
        {"VoltageCheckMinCellV", battsel.Config.checkBatteryVoltageOnConnect},
        {"EnableVoltageCheckHaptic", battsel.Config.checkBatteryVoltageOnConnect},
        {"VoltageCheckHapticPattern", battsel.Config.checkBatteryVoltageOnConnect and battsel.Config.doHaptic},
        {"ImagePickerDefault", battsel.Config.modelImageSwitching},
        {"ImagePickerId", battsel.Config.modelImageSwitching}
    }

    -- Iterates over the `updates` table, where each element is expected to be a pair
    -- containing a field name and a condition. For each pair:
    -- 1. Retrieves the field name (`fieldName`) and condition (`condition`) from the current update.
    -- 2. Checks if the `formFields` table contains an entry for the given `fieldName`.
    -- 3. If the field exists, calls the `enable` method on the corresponding form field,
    --    passing the `condition` as an argument to enable or disable the field dynamically.
    for _, update in ipairs(updates) do
        local fieldName, condition = update[1], update[2]
        if formFields[fieldName] then
            formFields[fieldName]:enable(condition)
        end
    end
end


local uniqueIDs = {}

-- Favorites Panel in Configure
local function fillFavoritesPanel(favoritesPanel)
    local debug = battsel.useDebug.fillFavoritesPanel
    
    -- Create list of Unique IDs from on all Batteries' IDs
    uniqueIDs = {}
    local seen = {}
    for i = 1, #battsel.Data.Batteries do
        local id = battsel.Data.Batteries[i].modelID
        if not seen[id] then
            seen[id] = true
            table.insert(uniqueIDs, id)
        end
    end

    -- List out available unique Model IDs in the Favorites panel
    for i, id in ipairs(uniqueIDs) do
        local line = favoritesPanel:addLine("ID " .. id .. " Favorite")

        -- Create Favorite picker field
        local matchingNames = {}
        for j = 1, #battsel.Data.Batteries do
            if battsel.Data.Batteries[j].modelID == id then
                matchingNames[#matchingNames + 1] = {battsel.Data.Batteries[j].name, j}
            end
        end
        formFields["FavoriteSelectionField"] = form.addChoiceField(line, nil, matchingNames, function()
            for j = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[j].modelID == id and battsel.Data.Batteries[j].favorite then
                    return j
                end
            end
            return nil
        end, function(value)
            for j = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[j].modelID == id then
                    battsel.Data.Batteries[j].favorite = (j == value)
                end
            end
        end)
    end
end


local function fillImagePanel(imagePanel)
    local debug = battsel.useDebug.fillImagePanel

    local line = imagePanel:addLine("Enable Model Image Switching")
    formFields["EnableImageSwitching"] = form.addBooleanField(line, nil, function() return battsel.Config.modelImageSwitching end, function(newValue) 
        if debug then print("Model Image Switching: " .. tostring(newValue)) end
        battsel.Config.modelImageSwitching = newValue
        updateFieldStates()
    end)
    
    local line = imagePanel:addLine("Default Image")
    formFields["ImagePickerDefault"] = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function() return battsel.Config.Images.Default or "" end, function(newValue) battsel.Config.Images.Default = newValue end)
    if debug then print("DEBUG(fillImagePanel):" .. "Default Image: " .. battsel.Config.Images.Default) end

    -- List out available Model IDs in the Favorites panel
    for i, id in ipairs(uniqueIDs) do
        local line = imagePanel:addLine("ID " .. id .. " Image")
        local key = tostring(id)  -- Convert to string
    
        formFields["ImagePickerId"] = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function()
            return battsel.Config.Images[key] or ""
        end, function(newValue)
            battsel.Config.Images[key] = newValue
        end)
        if debug then print("DEBUG(fillImagePanel): Image for ID " .. id .. ": " .. (battsel.Config.Images[key] or "")) end
    end
end


local reorderMode = false

local function fillBatteryPanel(batteryPanel)
    local debug = battsel.useDebug.fillBatteryPanel

    -- Get the layout
    local layout = layouts.getLayout("batteryPanel", reorderMode)
    if debug then 
        -- print("Current Layout:")
        -- utils.printTable(layout) 
    end

    -- Create header for the battery panel
    local line = batteryPanel:addLine("")
    form.addStaticText(line, layout.header.batName, "Name")
    if not reorderMode then
        form.addStaticText(line, layout.header.batType, "Type")
        form.addStaticText(line, layout.header.batCels, "Cells")
        form.addStaticText(line, layout.header.batCap, "Capacity")
        form.addStaticText(line, layout.header.batID, "ID")
    else
        form.addStaticText(line, layout.header.batMove, "Move")
    end

    for i = 1, #battsel.Data.Batteries do
        local line = batteryPanel:addLine("")
        formFields["BatteryNameField"] = form.addTextField(line, layout.field.batName, function() return battsel.Data.Batteries[i].name end, function(newName)
            battsel.Data.Batteries[i].name = newName
            rebuildWidget = true
        end)

        if not reorderMode then
            formFields["BatteryTypeField"] = form.addChoiceField(line, layout.field.batType, {{"LiPo", 1},{ "LiHV", 2}}, function() return battsel.Data.Batteries[i].type end, function(value) 
                battsel.Data.Batteries[i].type = value
            end)

            formFields["BatteryCellsField"] = form.addNumberField(line, layout.field.batCels, 1, 16, function() return battsel.Data.Batteries[i].cells end, function(value)
                battsel.Data.Batteries[i].cells = value
                rebuildWidget = true
            end)
            formFields["BatteryCellsField"]:help("Number of cells in the battery.  Used for battery voltage check.")

            formFields["BatteryCapacityField"] = form.addNumberField(line, layout.field.batCap, 0, 20000, function() return battsel.Data.Batteries[i].capacity end, function(value)
                battsel.Data.Batteries[i].capacity = value
                rebuildWidget = true
            end)
            formFields["BatteryCapacityField"]:suffix("mAh")
            formFields["BatteryCapacityField"]:step(100)
            formFields["BatteryCapacityField"]:default(0)
            formFields["BatteryCapacityField"]:enableInstantChange(false)
            formFields["BatteryCapacityField"]:help("Battery rated capacity in mAh.  Used for remaining percent calculations.")
            
            formFields["BatteryIDField"] = form.addNumberField(line, layout.field.batID , 0, 99, function() return battsel.Data.Batteries[i].modelID end, function(value)
                battsel.Data.Batteries[i].modelID = value
                favoritesPanel:clear()
                fillFavoritesPanel(favoritesPanel, battsel)
                imagePanel:clear()
                fillImagePanel(imagePanel, battsel)
                rebuildWidget = true
            end)
            formFields["BatteryIDField"]:default(0)
            formFields["BatteryIDField"]:enableInstantChange(false)
            formFields["BatteryIDField"]:help("Rotorflight Model ID to associate with this battery. Used for model image switching and favorites.")

        else
            formFields["DeleteButton"] = form.addTextButton(line, layout.field.batDel, "Delete", function()
                table.remove(battsel.Data.Batteries, i)
                batteryPanel:clear()
                fillBatteryPanel(batteryPanel)
                return true
            end)
            formFields["CloneButton"] = form.addTextButton(line, layout.field.batClone, "Clone", function()
                local clone = {
                    name = battsel.Data.Batteries[i].name .. " (Copy)",
                    type = battsel.Data.Batteries[i].type,
                    cells = battsel.Data.Batteries[i].cells,
                    capacity = battsel.Data.Batteries[i].capacity,
                    modelID = battsel.Data.Batteries[i].modelID,
                }
                table.insert(battsel.Data.Batteries, clone)
                batteryPanel:clear()
                fillBatteryPanel(batteryPanel)
                return true
            end)
            -- Add Up/Down buttons in reorder mode
            if i > 1 then
                formFields["UpButton"] = form.addTextButton(line, layout.field.batUp, "↑", function()
                    battsel.Data.Batteries[i], battsel.Data.Batteries[i-1] = battsel.Data.Batteries[i-1], battsel.Data.Batteries[i]
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel)
                    return true
                end)
            end
            if i < #battsel.Data.Batteries then
                formFields["DownButton"] = form.addTextButton(line, layout.field.batDown, "↓", function()
                    battsel.Data.Batteries[i], battsel.Data.Batteries[i+1] = battsel.Data.Batteries[i+1], battsel.Data.Batteries[i]
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel)
                    return true
                end)
            end
        end
    end

    local line = batteryPanel:addLine("")
    formFields["ReorderButton"] = form.addTextButton(line, layout.button.batReorder, reorderMode and "Done" or "Reorder/Edit", function()
        reorderMode = not reorderMode
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, battsel)
    end)
    formFields["AddButton"] = form.addTextButton(line, layout.button.batAdd, "Add New", function()
        table.insert(battsel.Data.Batteries, {
            name = "Battery " .. (#battsel.Data.Batteries + 1),
            type = 1,
            cells = 6,
            capacity = 0,
            modelID = 0
        })
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, battsel)
        favoritesPanel:clear()
        fillFavoritesPanel(favoritesPanel, battsel)
        imagePanel:clear()
        fillImagePanel(imagePanel, battsel)
        rebuildWidget = true
    end)
end

local hapticPatterns = {{". . . . . .", 1}, {". - . - . - .", 2}, {". - - . - - . - - . - - .", 3}}
local hapticPattern

-- Settings Panel
local function fillPrefsPanel(prefsPanel)
    local debug = battsel.useDebug.fillPrefsPanel
    if debug then print("DEBUG(fillPrefsPanel): Filling Preferences Panel") end

    local line = prefsPanel:addLine("Use Capacity")
    formFields["UseCapacityField"] = form.addNumberField(line, nil, 50, 100, function() return battsel.Config.useCapacity or 80 end, function(value) battsel.Config.useCapacity = value end)
    formFields["UseCapacityField"]:suffix("%")
    formFields["UseCapacityField"]:default(80)
    formFields["UseCapacityField"]:help("Percentage of battery capacity to use for remaining percent calculations.  e.g. 80% means 4000mAh on a 5000mAh battery is 0% Remaining.")

    local line = prefsPanel:addLine("Enable Voltage Check")
    formFields["EnableVoltageCheck"] = form.addBooleanField(line, nil, function() return battsel.Config.checkBatteryVoltageOnConnect end, function(newValue) battsel.Config.checkBatteryVoltageOnConnect = newValue updateFieldStates() end)
    
    local line = prefsPanel:addLine("Min Charged Volt/Cell")
    formFields["VoltageCheckMinCellV"] = form.addNumberField(line, nil, 400, 435, function() return battsel.Config.minChargedCellVoltage or 415 end, function(value) battsel.Config.minChargedCellVoltage = value end)
    formFields["VoltageCheckMinCellV"]:decimals(2)
    formFields["VoltageCheckMinCellV"]:suffix("V")
    formFields["VoltageCheckMinCellV"]:enableInstantChange(false)
    formFields["VoltageCheckMinCellV"]:help("Minimum voltage per cell to consider battery charged.  Default is 4.15V")

    local line = prefsPanel:addLine("Haptic Warning")
    formFields["EnableVoltageCheckHaptic"] = form.addBooleanField(line, nil, function() return battsel.Config.doHaptic end, function(newValue) battsel.Config.doHaptic = newValue updateFieldStates() end)
    local line = prefsPanel:addLine("Haptic Pattern")
    formFields["VoltageCheckHapticPattern"] = form.addChoiceField(line, nil, hapticPatterns, function() return hapticPattern or 1 end, function(newValue) hapticPattern = newValue end)
end

-- Alerts Panel, commented out for now as not in use
-- local function fillAlertsPanel(alertsPanel, battsel)
--     local line = alertsPanel:addLine("Eventually")
-- end

local voltageDialogDismissed = false
local doneVoltageCheck = false
local batteryConnectTime

-- Estimate cellcount and check if battery is charged.  If not, popup dialog to alert user
local function doBatteryVoltageCheck()
    local debug = battsel.useDebug.doBatteryVoltageCheck

    -- Divide by 100 because the value is stored as a whole number (415 = 4.15V)
    local minChargedCellVoltage = battsel.Config.minChargedCellVoltage / 100 or 4.15

    local cellCount
    local currentVoltage
    local isCharged

    if not batteryConnectTime then
        batteryConnectTime = os.clock()
    end

    if batteryConnectTime and (os.clock() - batteryConnectTime) <= 60 then
        -- Check if cell count sensor exists in battsel.sensors, if not, get it
        if not battsel.source.cells then
            battsel.source.cells = system.getSource({category = CATEGORY_TELEMETRY, name = "Cell Count"})
            if battsel.source.cells then
                if debug then print("DEBUG(doBatteryVoltageCheck): RF Cell Count sensor found. Continuing") end
            else
                if debug then print("DEBUG(doBatteryVoltageCheck): RF Cell Count sensor not found. Proceeding with estimation from Voltage") end
            end
        end

        -- Check if voltage sensor exists in battsel.sensors, if not, get it
        if not battsel.source.voltage then
            -- Try to obtain the voltage sensor from RFSUITE first
            if rfsuite and rfsuite.tasks.active() then
                battsel.source.voltage = rfsuite.tasks.telemetry.getSensorSource("voltage")
            end
            if battsel.source.voltage then
                if debug then print("DEBUG(doBatteryVoltageCheck): Voltage Sensor found from RFSUITE: " .. battsel.source.voltage:name()) end
            else
                if debug then print("DEBUG(doBatteryVoltageCheck): Voltage Sensor not found from RFSUITE, proceeding with legacy search.") end
                -- Fallback to legacy method: search by name in the telemetry category
                battsel.source.voltage = system.getSource({category = CATEGORY_TELEMETRY, name = "Voltage"})
                if battsel.source.voltage then
                    if debug then print("DEBUG(doBatteryVoltageCheck): Voltage Sensor Found: " .. battsel.source.voltage:name()) end
                else
                    if debug then print("DEBUG(doBatteryVoltageCheck): Could not get Voltage sensor!") end
                    return
                end
            end
        end

        if battsel.source.cells and battsel.source.voltage then
            if battsel.source.cells:value() == nil or battsel.source.voltage:value() == nil then
                if debug then print("DEBUG(doBatteryVoltageCheck): Cell Count or Voltage sensor reading is nil. Exiting") end
                return
            end
            currentVoltage = battsel.source.voltage:value()
            cellCount = math.floor(battsel.source.cells:value())
            isCharged = currentVoltage >= cellCount * minChargedCellVoltage
            doneVoltageCheck = true
        elseif battsel.source.voltage then
            if battsel.source.voltage:value() == nil then
                if debug then print("DEBUG(doBatteryVoltageCheck): Voltage sensor reading is nil. Exiting") end
                return
            end
            currentVoltage = battsel.source.voltage:value()
            -- Estimate cell count based on voltage
            cellCount = math.floor(currentVoltage / minChargedCellVoltage + 0.5)
            -- To prevent accidentally reading a very low battery as a lower cell count than actual, add 1 to cellCount if the voltage is higher than cellCount * 4.35 (HV battery max cell voltage)
            if currentVoltage >= cellCount * 4.35 then
                cellCount = cellCount + 1
            end
        end

        if cellCount == 0 then
            cellCount = 1
        end

        if cellCount and currentVoltage then
            isCharged = currentVoltage >= cellCount * minChargedCellVoltage
            if debug then
                print("DEBUG(doBatteryVoltageCheck): Voltage Sensor Found. Reading: " .. currentVoltage .. "V")
                print("DEBUG(doBatteryVoltageCheck): Cell Count: " .. cellCount)
                print("DEBUG(doBatteryVoltageCheck): Battery Charged: " .. tostring(isCharged))
            end

            if isCharged == false and voltageDialogDismissed == false then
                if debug then print("Debug(doBatteryVoltageCheck): Battery not charged! Popup dialog") end
                local buttons = {
                    {label = "OK", action = function()
                        voltageDialogDismissed = true
                        if debug then print("DEBUG(doBatteryVoltageCheck): Voltage Dialog Dismissed") end
                        return true
                    end}
                }
                if battsel.Config.doHaptic then
                    if debug then print("DEBUG(doBatteryVoltageCheck): Playing Haptic") end
                    -- system.playHaptic(hapticPatterns[hapticPattern][1])
                end
                form.openDialog({
                    title = "Low Battery Voltage",
                    message = "Battery may not be charged!",
                    width = 350,
                    buttons = buttons,
                    options = TEXT_LEFT,
                })
            end
            doneVoltageCheck = true
        end
    end
end


local newPercent = 100

local function updateRemainingSensor()
    local debug = battsel.useDebug.updateRemainingSensor
    if not battsel.source.percent then
        if debug then print("Searching for Remaining Sensor") end
        battsel.source.percent = system.getSource({category = CATEGORY_TELEMETRY, appId = 0x4402, physId = 0x11, name = "Remaining"})
        if not battsel.source.percent then
            print("Remaining Sensor Not Found. Creating...")
            battsel.source.percent = model.createSensor()
            battsel.source.percent:name("Remaining")
            battsel.source.percent:unit(UNIT_PERCENT)
            battsel.source.percent:decimals(0)
            battsel.source.percent:appId(0x4402)
            battsel.source.percent:physId(0x11)
            if debug then print(string.format("Remaining Sensor Created: 0x%04X 0x%02X", battsel.source.percent:appId(), battsel.source.percent:physId())) end
        else
            if debug then print(string.format("Remaining Sensor Found: 0x%04X 0x%02X", battsel.source.percent:appId(), battsel.source.percent:physId())) end
        end
    end

    if battsel.source.percent then
        if debug then print("Updating Remaining Sensor: " .. newPercent .. "%") end
        battsel.source.percent:value(newPercent)
    else
        if debug then print("Unable to Find/Create Remaining Sensor") end
        return
    end
end


--- Retrieves the current milliampere-hour (mAh) reading from a telemetry sensor.
--- 
--- This function attempts to locate a telemetry sensor that provides mAh readings.
--- It first tries to find the sensor using the `rfsuite.tasks.telemetry.getSensorSource` method.
--- If unsuccessful, it falls back to a legacy search method that iterates through available telemetry sensors.
--- 
--- If a valid sensor is found, the function retrieves its current value, rounds it down to the nearest integer,
--- and returns it. If no sensor is found or the value cannot be retrieved, the function returns 0.
---
--- Debugging messages can be enabled by setting `battsel.useDebug.getmAh` to `true`.
---
--- @return number The current mAh reading, rounded down to the nearest integer, or 0 if no sensor is found.
local function getmAh()
    local debug = battsel.useDebug.getmAh

    if not battsel.source.consumption then
        if rfsuite and rfsuite.tasks.active() then
            battsel.source.consumption = rfsuite.tasks.telemetry.getSensorSource("consumption")
        end
        if battsel.source.consumption then
            if debug then print("DEBUG(getmAh): mAh Sensor found from RFSUITE: " .. battsel.source.consumption:name()) end
        else
            if debug then print("DEBUG(getmAh): mAh Sensor not found from RFSUITE, proceeding with legacy search.") end
            for member = 0, 50 do
                local candidate = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, member = member})
                if candidate and candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                    battsel.source.consumption = candidate
                    if debug then print("DEBUG(getmAh): mAh Sensor Found: " .. battsel.source.consumption:name()) end
                    break
                end
            end
        end

        if not battsel.source.consumption then
            if debug then print("DEBUG(getmAh): Could not get mAh sensor!") end
            return 0
        end
    end

    local value = battsel.source.consumption:value()
    if value then
        if debug then print("DEBUG(getmAh): mAh Reading: " .. math.floor(value) .. "mAh") end
        return math.floor(value)
    end

    return 0
end

-- This function is called when the widget is first created
local function create()

end

local lastmAh = 0
local widgetInit = true
local selectedBattery
local matchingBatteries
local fieldHeight
local fieldWidth

local function build()
    local debug = battsel.useDebug.build

    local w, h = lcd.getWindowSize()

    -- Refresh the matchingBatteries list based on currentModelID
    matchingBatteries = {}
    if #battsel.Data.Batteries > 0 then
        if currentModelID then
            if debug then print("DEBUG(build): Current Model ID: " .. currentModelID) end
            -- First, try to add batteries matching currentModelID.
            for i = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[i].modelID == currentModelID then
                    matchingBatteries[#matchingBatteries + 1] = {battsel.Data.Batteries[i].name, i}
                end
            end
            -- If no batteries matched, fall back to adding all batteries.
            if #matchingBatteries == 0 then
                if debug then print("DEBUG(build): No batteries match currentModelID, falling back to all batteries.") end
                for i = 1, #battsel.Data.Batteries do
                    matchingBatteries[#matchingBatteries + 1] = {battsel.Data.Batteries[i].name, i}
                end
            end
    
            -- Select a battery if a favorite is marked for the currentModelID.
            for i = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[i].modelID == currentModelID and battsel.Data.Batteries[i].favorite then
                    selectedBattery = i
                    break
                end
            end
        else
            -- No currentModelID provided; simply add all batteries.
            for i = 1, #battsel.Data.Batteries do
                matchingBatteries[#matchingBatteries + 1] = {battsel.Data.Batteries[i].name, i}
            end
            if #matchingBatteries > 0 then
                selectedBattery = matchingBatteries[1][2]
            end
        end
    end
    
    if selectedBattery == nil then
        selectedBattery = 1
    end

    if debug then
        local batteryNames = {}
        for i, battery in ipairs(matchingBatteries) do
            table.insert(batteryNames, battery[1])
        end
        if batteryNames then print("DEBUG(build): Matching Batteries: " .. table.concat(batteryNames, ", ")) end
        if battsel.Data.Batteries[selectedBattery] then 
            local batteryInfo = "Debug(build): Selected Battery: " .. battsel.Data.Batteries[selectedBattery].name
            if battsel.Data.Batteries[selectedBattery].favorite then
            batteryInfo = batteryInfo .. " (Favorite)"
            end
            print(batteryInfo)
        end
    end

    -- Initialize widget based on radio type
    if widgetInit then
        if debug then print("DEBUG(build): Widget Init") end
        
        if radio.board == "X18" or radio.board == "X18S" then
            fieldHeight = 30
        else
            fieldHeight = 40
        end

        local padding = 10
        fieldWidth, _ = lcd.getWindowSize()
        fieldWidth = fieldWidth - padding * 2
        if fieldWidth > 200 then
            fieldWidth = 200
        end

        if debug then print("DEBUG(build): Creating form") end
        form.create()
        widgetInit = false
    end
    
    if fieldHeight and fieldWidth and matchingBatteries then
        form.clear()
        if debug then print("DEBUG(build): Updating Choice Field") end
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)

        -- Create form and add choice field for selecting battery
        formFields["batteryChoiceField"] = form.addChoiceField(nil, {x = pos_x, y = pos_y, w = fieldWidth, h = fieldHeight}, matchingBatteries, function() return selectedBattery end, function(value) 
            selectedBattery = value 
        end)
    end 
end

local lastModelID = nil
local lastTime = os.clock()
local lastBattCheckTime = os.clock()
local resetDone = false
local batteryCapacity

local function wakeup()
    local debug = battsel.useDebug.wakeup

    -- Assign telemetry active event to battsel.source.telem if not already
    if battsel.source.telem == nil then
        battsel.source.telem = system.getSource({category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE, options = nil})
    end
    local tlmActive = battsel.source.telem:state() -- Get the telemetry state

    -- Get the current uptime
    local currentTime = os.clock()

    if battsel.Config.checkBatteryVoltageOnConnect and tlmActive then
        -- Only run the battery voltage check 15 seconds after telemetry becomes active to prevent reading voltage before Voltage telemetry is established and valid (nonzero)
        -- Initially this was 3 seconds, but some ESCs take longer to initialize and provide valid voltage telemetry (Scorpion takes over 10 seconds to start sending telemetry)
        if currentTime - lastBattCheckTime >= 15 then
            lastBattCheckTime = currentTime
            -- If telemetry is active and voltage check is enabled, run check if it hasn't been done and dismissed yet
            if not doneVoltageCheck and not voltageDialogDismissed then
                if debug then print ("Debug(wakeup): Running Battery Voltage Check") end
                doBatteryVoltageCheck(battsel)
            end
        end
    else
        voltageDialogDismissed = false -- Reset the dialog dismissed flag when telemetry becomes inactive
        lastBattCheckTime = currentTime -- Reset the timer when telemetry becomes inactive
    end

    if currentTime - lastTime >= 1 then
        -- Reset all doBatteryVoltageCheck parameters when telemetry becomes inactive so that it can run again on next battery connect
        if not tlmActive and not resetDone then
            voltageDialogDismissed = false
            doneVoltageCheck = false
            batteryConnectTime = nil
            resetDone = true
        elseif tlmActive then
            resetDone = false
        end

        -- if Batteries exist, telemetry is active, a battery is selected, and the mAh reading is not nil, do the maths
        local newmAh = getmAh()
        if #battsel.Data.Batteries > 0 and tlmActive and selectedBattery and newmAh and battsel.Config.useCapacity  then
            if newmAh ~= lastmAh then
                local usablemAh = battsel.Data.Batteries[selectedBattery].capacity * (battsel.Config.useCapacity / 100)
                newPercent = 100 - (newmAh / usablemAh) * 100
                if newPercent < 0 then newPercent = 0 end
                lastmAh = newmAh
            end
        end

        if debug then print ("Debug(wakeup): Updating Remaining Sensor") end
        updateRemainingSensor() -- Update the remaining sensor
        
        -- Check for modelID sensor presence and its value
        if not battsel.source.modelID then 
            battsel.source.modelID = system.getSource({category = CATEGORY_TELEMETRY, name = "Model ID"})
        end
        if battsel.source.modelID and battsel.source.modelID:value() ~= nil then
            currentModelID = math.floor(battsel.source.modelID:value())
        end
        
        local currentBitmapName = model.bitmap():match("([^/]+)$")

        -- Set the model image based on the currentModelID.  If not present or invalid, set it to the default image
        if battsel.Config.modelImageSwitching then
            if tlmActive and currentModelID and battsel.Config.Images[tostring(currentModelID)] then
                if currentBitmapName ~= battsel.Config.Images[tostring(currentModelID)] then
                    model.bitmap(battsel.Config.Images[tostring(currentModelID)])
                    if debug then print("DEBUG(wakeup): Setting model image to " .. battsel.Config.Images[tostring(currentModelID)]) end
                end
            elseif battsel.Config.Images and battsel.Config.Images.Default and battsel.Config.Images.Default ~= "" then
                if currentBitmapName ~= battsel.Config.Images.Default then
                    model.bitmap(battsel.Config.Images.Default)
                    if debug then print("DEBUG(wakeup): Setting model image to Default: " .. battsel.Config.Images.Default) end
                end
            end
        end
        lastTime = currentTime
    end

    -- Check if the modelID has changed since last wakeup, and if so, set the rebuildWidgetflag to true
    if currentModelID ~= lastModelID then
        if debug then print("DEBUG(wakeup): Model ID has changed") end
        lastModelID = currentModelID 
        rebuildWidget = true
    end

    if rebuildWidget then
        if debug then print ("Debug(wakeup): Rebuilding widget") end
        build()
        rebuildWidget = false
    end
end


-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure()
    local debug = battsel.useDebug.configure

    if not configLoaded then
        read()
    end

    -- Fill Batteries panel
    if debug then print("DEBUG(configure): Filling Battery Panel") end
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, battsel)

    -- Fill Favorites panel
    if debug then print("DEBUG(configure): Filling Favorites Panel") end
    favoritesPanel = form.addExpansionPanel("Favorites")
    favoritesPanel:open(false)
    fillFavoritesPanel(favoritesPanel, battsel)

    -- Fill Images panel
    if debug then print("DEBUG(configure): Filling Images Panel") end
    imagePanel = form.addExpansionPanel("Images")
    imagePanel:open(false)
    fillImagePanel(imagePanel, battsel)

    -- Preferences Panel
    if debug then print("DEBUG(configure): Filling Preferences Panel") end
    prefsPanel = form.addExpansionPanel("Preferences")
    prefsPanel:open(false)
    fillPrefsPanel(prefsPanel, battsel)

    updateFieldStates()
end


--- Reads configuration or battery data from files and merges it with default values.
--- 
--- This function handles reading and processing configuration and battery data
--- from JSON files. It merges the read configuration with default values to ensure
--- all required fields are present. The processed data is stored in the `battsel.Config`
--- and `battsel.Data` tables.
---
--- @param what string|nil Specifies what data to read:
---                        - "config": Reads configuration data from `config.json`.
---                        - "data": Reads battery data from `batteries.json`.
---                        - nil: Reads both configuration and battery data.
function read(what)
    local debug = battsel.useDebug.read

    local defaultConfig = {
        useCapacity = 80,
        checkBatteryVoltageOnConnect = false,
        minChargedCellVoltage = 415,
        doHaptic = false,
        modelImageSwitching = true,
        Images = {
            Default = "",
        }
    }

    -- Local helper function to merge defaults into the config
    local function mergeDefaults(defaults, config)
        for key, defaultValue in pairs(defaults) do
            if type(defaultValue) == "table" then
                if type(config[key]) ~= "table" then
                    config[key] = {}
                end
                mergeDefaults(defaultValue, config[key])
            elseif config[key] == nil then
                config[key] = defaultValue
            end
        end
    end

    local function readFileContent(filename)
        local file = io.open(filename, "r")
        if not file then return nil end
        local content = {}
        while true do
            local line = file:read("*l")
            if not line then break end
            table.insert(content, line)
        end
        file:close()
        return table.concat(content, "\n")
    end

    print("Reading BattSelector data from file...")
    
    if what == nil or what == "config" then
        local configFileName = "config.json"
        local content = readFileContent(configFileName)
        local configData = {}
        if content and content ~= "" then
            configData = json.decode(content) or {}
        end
        -- Merge default config values into the read config
        mergeDefaults(defaultConfig, configData)
        battsel.Config = configData
    end

    if what == nil or what == "data" then
        local batteriesFileName = "batteries.json"
        local content2 = readFileContent(batteriesFileName)
        local batteryData = {}
        if content2 and content2 ~= "" then
            local decoded = json.decode(content2)
            if decoded then
                if decoded.version and decoded.batteries then
                    batteryData = decoded.batteries
                elseif type(decoded) == "table" and #decoded > 0 and decoded[1].name then
                    batteryData = decoded
                else
                    batteryData = {}
                end
            else
                batteryData = {}
            end
        else
            batteryData = {}
        end
        battsel.Data = { Batteries = batteryData }
    end
    if battsel.Config and battsel.Data then
        configLoaded = true
    end

    if debug then 
        if battsel.Config then utils.printTable(battsel.Config, "raw") end
        if battsel.Data then utils.printTable(battsel.Data, "raw") end
    end
end

--- Writes configuration or battery data to JSON files.
--- 
--- This function saves the current state of configuration and/or battery data
--- to their respective JSON files. It supports writing either "config" data,
--- "data" (battery data), or both if no specific type is specified.
---
--- @param what string|nil Optional. Specifies what data to write:
---                        - "config": Writes configuration data to `config.json`.
---                        - "data": Writes battery data to `batteries.json`.
---                        - nil: Writes both configuration and battery data.
function write(what)
    local debug = battsel.useDebug.write

    print("Writing BattSelector data to file...")
    local configData = {}
    local batteryData = {}

    if what == nil or what == "config" then
        local configFileName = "config.json"
        -- Here we assume your global state holds the config in battsel.Config.
        configData = battsel.Config or {}
        local jsonConfig = json.encode(configData, { indent = "  " })
        local file = io.open(configFileName, "w")
        if file then
            file:write(jsonConfig)
            file:close()
        end
    end
    if what == nil or what == "data" then
        local batteriesFileName = "batteries.json"
        -- Similarly, we assume battsel.Data.Batteries holds your battery list.
        batteryData = { version = 1, batteries = (battsel.Data and battsel.Data.Batteries) or {} }
        local jsonBatteries = json.encode(batteryData, { indent = "  " })
        local file2 = io.open(batteriesFileName, "w")
        if file2 then
            file2:write(jsonBatteries)
            file2:close()
        end
        
    end

    if debug then 
        if configData then utils.printTable(configData, "pretty") end
        if batteryData then utils.printTable(batteryData, "pretty") end
    end
end

local function paint(battsel) end

local function event(widget, category, value, x, y) end

local function close()
    battsel = nil
    system.exit()
    return true
end

local function init()
    system.registerWidget({
        key = "battsel",
        name = "Battery Select",
        create = create,
        build = build,
        paint = paint,
        event = event,
        wakeup = wakeup,
        configure = configure,
        read = read,
        write = write,
        close = close
    })
end


return {init = init}
