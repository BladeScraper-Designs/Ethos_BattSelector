-- Lua Battery Selector and Alarm widget
-- Version: 3.2.0
local battsel = {}

-- Set to true to enable debug output for each function as required
battsel.useDebug = {
    -- UI Panel Fillers
    fillBatteryPanel = false,
    fillFavoritesPanel = false,
    fillImagePanel = false,
    fillVoltAlertsPanel = false,
    fillCapAlertsPanel = false,
    fillPrefsPanel = false,
    fillAlertsPanel = false,

    -- UI/Field State
    updateFieldStates = false,

    -- Data IO
    read = false,
    write = false,

    -- Battery/Telemetry Logic
    doBatteryVoltageCheck = true,
    getmAh = false,
    updateRemainingSensor = false,
    doCapAlert = false,

    -- Widget Lifecycle
    create = false,
    build = false,
    configure = false,
    paint = false,
    wakeup = true,
    close = false,
    init = false,

    -- Utility/Scheduling
    shouldRun = false,
    shouldRunBatteryCheck = false
}

-- Required libraries
local json = require("lib.lunajson") -- JSON library 
if json then print("DEBUG(battsel): JSON Library Loaded") else print("DEBUG(battsel): JSON Library Load Failed!") end

local layouts = require("lib.layout") -- Layout library
if layouts then print("DEBUG(battsel): Layouts Library Loaded") else print("DEBUG(battsel): Layouts Library Load Failed!") end

local utils = require("lib.utils") -- Utility library
if utils then print("DEBUG(battsel): Utils Library Loaded") else print("DEBUG(battsel): Utils Library Load Failed!") end

local read, write

-- Get radio information
local radio = system.getVersion()
local LCD_W, LCD_H = radio.lcdWidth, radio.lcdHeight
print("DEBUG(battsel): Radio: " .. radio.board)
print("DEBUG(battsel): LCD Width: " .. LCD_W .. " Height: " .. LCD_H)
print("DEBUG(battsel): Radio Version: " .. radio.version)

-- Ethos compatibility check
if not utils.checkCompat("ethos") then
    print("DEBUG(battsel): Ethos Compatibility Check Failed!  Aborting...")
    return
else 
    print("DEBUG(battsel): Ethos Compatibility Check Passed!")
end

local configLoaded = false

local formLines, formFields = {}, {}

local favoritesPanel
local imagePanel
local batteryPanel
local capAlertsPanel
local voltAlertsPanel
local prefsPanel

local rebuildWidget = false

-- Telemetry sources
battsel.source = {
    telem = nil,
    voltage = nil,
    consumption = nil,
    cells = nil,
    modelID = nil,
    percent = nil,
    mute = nil
}

local currentModelID = nil
local tlmActive = false
local voicePath = system.getAudioVoice() or "AUDIO:/en/us"

-- Dynamically enables or disables specific form fields based on the current configuration.
-- This function evaluates the values in the `battsel.Config` table and adjusts the related
-- form fields accordingly to ensure that only valid options are available to the user.
local function updateFieldStates()
    local updates = {
        {"ImagePickerDefault", battsel.Config.modelImageSwitching},
        {"ImagePickerId", battsel.Config.modelImageSwitching},
        {"AlertFrequency", battsel.Config.enableAlerts},
        {"AlertMute", battsel.Config.enableAlerts},
        {"AlertCustomThresholds", battsel.Config.enableAlerts and battsel.Config.AlertsID == 3},
        {"AlertLowCellVoltage", battsel.Config.enableVoltageAlerts},
        {"AlertCriticalCellVoltage", battsel.Config.enableVoltageAlerts},
        {"AlertFalsePositiveDelay", battsel.Config.enableVoltageAlerts},
        {"VoltageCheckMinCellV_LiPo", battsel.Config.checkBatteryVoltageOnConnect},
        {"VoltageCheckMinCellV_LiHV", battsel.Config.checkBatteryVoltageOnConnect},
        {"EnableVoltageCheckHaptic", battsel.Config.checkBatteryVoltageOnConnect},
        {"VoltageCheckHapticPattern", battsel.Config.checkBatteryVoltageOnConnect and battsel.Config.doHaptic},
        {"VoltageCheckAudioFile", battsel.Config.checkBatteryVoltageOnConnect},
        {"AlertLowVoltAudio", battsel.Config.enableVoltageAlerts},
        {"AlertCriticalVoltAudio", battsel.Config.enableVoltageAlerts}
    }

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
    formFields["EnableImageSwitching"] = form.addBooleanField(line, nil, function() return battsel.Config.modelImageSwitching end, 
        function(newValue) battsel.Config.modelImageSwitching = newValue updateFieldStates() end)
    if debug then print("Model Image Switching: " .. tostring(newValue)) end 
    
    local line = imagePanel:addLine("Default Image")
    formFields["ImagePickerDefault"] = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function() return battsel.Config.Images.Default or "" end, 
        function(newValue) battsel.Config.Images.Default = newValue end)
    if debug then print("DEBUG(fillImagePanel):" .. "Default Image: " .. battsel.Config.Images.Default) end

    -- List out available Model IDs in the Favorites panel
    for i, id in ipairs(uniqueIDs) do
        local line = imagePanel:addLine("ID " .. id .. " Image")
        local key = tostring(id)  -- Convert to string
    
        formFields["ImagePickerId"] = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function() return battsel.Config.Images[key] or "" end, 
            function(newValue) battsel.Config.Images[key] = newValue end)
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


local hapticPatterns = {
  {"-", 1},
  {"- -", 2},
  {"- - -", 3},
  {"- - - -", 4},
  {".", 5},
  {". .", 6},
  {". . .", 7},
  {". . . . .", 8},
  {". -", 9},
  {". . -", 10},
  {". . . . . . .", 11},
  {". - . - . - .", 12},
  {". - - . - - .", 13}
}
  
-- Settings Panel
local function fillPrefsPanel(prefsPanel)
    local debug = battsel.useDebug.fillPrefsPanel
    if debug then print("DEBUG(fillPrefsPanel): Filling Preferences Panel") end

    local line = prefsPanel:addLine("Use Capacity")
    formFields["UseCapacityField"] = form.addNumberField(line, nil, 50, 100, function() return battsel.Config.useCapacity or 80 end, function(value) battsel.Config.useCapacity = value end)
    formFields["UseCapacityField"]:suffix("%")
    formFields["UseCapacityField"]:default(80)
    formFields["UseCapacityField"]:help("Percentage of battery capacity to use for remaining percent calculations.  e.g. 80% means 4000mAh on a 5000mAh battery is 0% Remaining.")

    local line = prefsPanel:addLine("Alert Mute")
    formFields["AlertMute"] = form.addSwitchField(line, nil,
        function()
            return battsel.Config.AlertMute 
                and battsel.Config.AlertMute.member 
                and system.getSource({ 
                    category = battsel.Config.AlertMute.category, 
                    member = battsel.Config.AlertMute.member 
                })
                or nil end,
        function(newValue)
            battsel.Config.AlertMute = { 
                category = newValue:category(), 
                member = newValue:member() 
            }
        end)
end


local function fillVoltAlertsPanel(voltAlertsPanel)
    local debug = battsel.useDebug.fillVoltAlertsPanel or true
    if debug then print("DEBUG(fillVoltAlertsPanel): Filling Voltage Alerts Panel") end

    local line = voltAlertsPanel:addLine("Enable Low Voltage Alerts")
    formFields["EnableVoltageAlerts"] = form.addBooleanField(line, nil, function() return battsel.Config.enableVoltageAlerts end, function(newValue) battsel.Config.enableVoltageAlerts = newValue updateFieldStates() end)

    local line = voltAlertsPanel:addLine("Low Cell Voltage")
    formFields["AlertLowCellVoltage"] = form.addNumberField(line, nil, 0, 390, function() return battsel.Config.alertLowCellVoltage or 350 end, function(value) battsel.Config.alertLowCellVoltage = value end)
    formFields["AlertLowCellVoltage"]:decimals(2)
    formFields["AlertLowCellVoltage"]:suffix("V")
    formFields["AlertLowCellVoltage"]:enableInstantChange(false)
    formFields["AlertLowCellVoltage"]:help("Cell voltage at which the low alert is triggered.")

    local line = voltAlertsPanel:addLine("Critical Cell Voltage")
    formFields["AlertCriticalCellVoltage"] = form.addNumberField(line, nil, 0, 390, function() return battsel.Config.alertCriticalCellVoltage or 330 end, function(value) battsel.Config.alertCriticalCellVoltage = value end)
    formFields["AlertCriticalCellVoltage"]:decimals(2)
    formFields["AlertCriticalCellVoltage"]:suffix("V")
    formFields["AlertCriticalCellVoltage"]:enableInstantChange(false)
    formFields["AlertCriticalCellVoltage"]:help("Cell voltage at which the critical alert is triggered.")

    local line = voltAlertsPanel:addLine("False Positive Delay")
    formFields["AlertFalsePositiveDelay"] = form.addNumberField(line, nil, 0, 10, function() return battsel.Config.alertFalsePositiveDelay or 5 end, function(value) battsel.Config.alertFalsePositiveDelay = value end)
    formFields["AlertFalsePositiveDelay"]:suffix("s")
    formFields["AlertFalsePositiveDelay"]:enableInstantChange(false)
    formFields["AlertFalsePositiveDelay"]:help("Time in seconds to wait before triggering the alert after the voltage drops below the threshold.  This helps prevent false positives from momentary voltage drops.")

    local line = voltAlertsPanel:addLine("Low Voltage Alert Audio")
    formFields["AlertLowVoltAudio"] = form.addFileField(line, nil, voicePath .. "/", "audio", function() return battsel.Config.alertLowVoltAudio end, function(newValue) battsel.Config.alertLowVoltAudio = newValue end)

    local line = voltAlertsPanel:addLine("Critical Voltage Alert Audio")
    formFields["AlertCriticalVoltAudio"] = form.addFileField(line, nil, voicePath .. "/", "audio", function() return battsel.Config.alertCriticalVoltAudio end, function(newValue) battsel.Config.alertCriticalVoltAudio = newValue end)

    -- Blank Line to separate voltage alert and voltage check settings
    local line = voltAlertsPanel:addLine("")
    --

    local line = voltAlertsPanel:addLine("Enable Charged Battery Check")
    formFields["EnableVoltageCheck"] = form.addBooleanField(line, nil, function() return battsel.Config.checkBatteryVoltageOnConnect end, function(newValue) battsel.Config.checkBatteryVoltageOnConnect = newValue updateFieldStates() end)
    
    local line = voltAlertsPanel:addLine("Min Charged V/Cell (LiPo)")
    formFields["VoltageCheckMinCellV_LiPo"] = form.addNumberField(line, nil, 350, 420, function() return battsel.Config.minChargedCellVoltage.lv or 415 end, function(value) battsel.Config.minChargedCellVoltage.lv = value end)
    formFields["VoltageCheckMinCellV_LiPo"]:decimals(2)
    formFields["VoltageCheckMinCellV_LiPo"]:suffix("V")
    formFields["VoltageCheckMinCellV_LiPo"]:enableInstantChange(false)
    formFields["VoltageCheckMinCellV_LiPo"]:help("Minimum voltage per cell to consider LiPo battery charged.")

    local line = voltAlertsPanel:addLine("Min Charged V/Cell (LiHV)")
    formFields["VoltageCheckMinCellV_LiHV"] = form.addNumberField(line, nil, 350, 435, function() return battsel.Config.minChargedCellVoltage.hv or 430 end, function(value) battsel.Config.minChargedCellVoltage.hv = value end)
    formFields["VoltageCheckMinCellV_LiHV"]:decimals(2)
    formFields["VoltageCheckMinCellV_LiHV"]:suffix("V")
    formFields["VoltageCheckMinCellV_LiHV"]:enableInstantChange(false)
    formFields["VoltageCheckMinCellV_LiHV"]:help("Minimum voltage per cell to consider LiHV battery charged.")

    local line = voltAlertsPanel:addLine("Haptic Warning")
    formFields["EnableVoltageCheckHaptic"] = form.addBooleanField(line, nil, function() return battsel.Config.doHaptic end, function(newValue) battsel.Config.doHaptic = newValue updateFieldStates() end)
    local line = voltAlertsPanel:addLine("Haptic Pattern")
    formFields["VoltageCheckHapticPattern"] = form.addChoiceField(line, nil, hapticPatterns, function() return hapticPattern or 1 end, function(newValue) hapticPattern = newValue end)

    local line = voltAlertsPanel:addLine("Uncharged Battery Alert Audio")
    formFields["VoltageCheckAudioFile"] = form.addFileField(line, nil, voicePath .. "/", "audio", function() return battsel.Config.batteryCheckAudioFile end, function(newValue) battsel.Config.batteryCheckAudioFile = newValue end)
end



local alertFrequencies = {{"Every 10%", 1}, {"50%, 5%, 0%", 2}, {"Custom", 3}}
local freqMappingById = {
    [1] = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90},
    [2] = {50, 5, 0},
    [3] = {}
}

-- Alerts Panel
local function fillCapAlertsPanel(capAlertsPanel)
    local line = capAlertsPanel:addLine("Enable Capacity Alerts")
    formFields["EnableAlerts"] = form.addBooleanField(line, nil, 
        function() return battsel.Config.enableAlerts end, 
        function(newValue) battsel.Config.enableAlerts = newValue updateFieldStates() end)

    local line = capAlertsPanel:addLine("Alert Frequency")
    formFields["AlertFrequency"] = form.addChoiceField(line, nil, alertFrequencies,
        function() return battsel.Config.AlertsID or 1 end,
        function(newValue) battsel.Config.AlertsID = newValue battsel.Config.Alerts = freqMappingById[newValue] updateFieldStates() end)

    local function parseThresholds(str)
        local thresholds = {}
        for token in string.gmatch(str, "([^%s%-]+)") do
            local num = tonumber(token)
            if num then
                table.insert(thresholds, num)
            end
        end
        return thresholds
    end        
    
    local line = capAlertsPanel:addLine("Alert Thresholds (Custom)")
    formFields["AlertCustomThresholds"] = form.addTextField(line, nil,
        function()
            if battsel.Config.AlertsID == 3 and battsel.Config.Alerts and #battsel.Config.Alerts > 0 then
                return table.concat(battsel.Config.Alerts, " ")
            else
                return ""
            end
        end,
        function(newText)
            if battsel.Config.AlertsID == 3 then
                battsel.Config.Alerts = parseThresholds(newText)
                print("Custom alerts updated to:", newText)
            end
        end)
end

local voltageDialogDismissed = false
local doneVoltageCheck = false
local batteryConnectTime
local selectedBattery
local cellCount

-- Estimate cellcount and check if battery is charged.  If not, popup dialog to alert user
local function doBatteryVoltageCheck()
    local debug = battsel.useDebug.doBatteryVoltageCheck
    if debug then print("DEBUG(doBatteryVoltageCheck): Starting battery voltage check.") end

    -- Retrieve battery data for the selected battery.
    local batteryData = (battsel.Data and battsel.Data.Batteries and selectedBattery)
        and battsel.Data.Batteries[selectedBattery] or nil
    if debug then
        if batteryData then 
            print("DEBUG(doBatteryVoltageCheck): Battery Data: " .. json.encode(batteryData))
        else 
            print("DEBUG(doBatteryVoltageCheck): No battery data available.")
        end
    end

    local currentVoltage, isCharged

    -- Determine the minimum per-cell voltage based on battery type.
    local minPerCell = 4.15  -- default fallback
    if batteryData then
        if batteryData.type == 2 then
            minPerCell = (battsel.Config.minChargedCellVoltage.hv or 430) / 100
            if debug then print("DEBUG(doBatteryVoltageCheck): Battery type is LiHV. Using minPerCell = " .. minPerCell .. "V") end
        else
            minPerCell = (battsel.Config.minChargedCellVoltage.lipo or 415) / 100
            if debug then print("DEBUG(doBatteryVoltageCheck): Battery type is LiPo. Using minPerCell = " .. minPerCell .. "V") end
        end
    else
        minPerCell = (battsel.Config.minChargedCellVoltage.lipo or 415) / 100
        if debug then print("DEBUG(doBatteryVoltageCheck): No battery data available. Using default LiPo minPerCell = " .. minPerCell .. "V") end
    end

    -- Get cell count sensor (if not already cached)
    battsel.source.cells = battsel.source.cells or utils.getSensor("Cell Count", nil)
    print("DEBUG(doBatteryVoltageCheck): Cell Count Sensor: " .. (battsel.source.cells and battsel.source.cells:name() or "Not Found"))

    -- Get voltage sensor (if not already cached)
    battsel.source.voltage = battsel.source.voltage or utils.getSensor("Voltage", nil)

    -- Process sensor values if both sensors are available.
    if battsel.source.cells and battsel.source.voltage then
        if battsel.source.cells:value() == nil or battsel.source.voltage:value() == nil then
            if debug then
                print("DEBUG(doBatteryVoltageCheck): One sensor reading is nil. Cell Count: " 
                      .. tostring(battsel.source.cells:value()) .. ", Voltage: "    
                      .. tostring(battsel.source.voltage:value()))
            end
            return
        end
        currentVoltage = battsel.source.voltage:value()
        cellCount = math.floor(battsel.source.cells:value())
        if debug then
            print("DEBUG(doBatteryVoltageCheck): Sensor readings: Voltage = " .. currentVoltage ..
                  "V, Raw Cell Count = " .. battsel.source.cells:value() ..
                  " (floored to " .. cellCount .. ")")
        end

        -- Override cell count if batteryData provides a valid value.
        if batteryData and batteryData.cells and batteryData.cells > 0 then
            if debug then print("DEBUG(doBatteryVoltageCheck): Overriding sensor cell count with batteryData.cells = " .. batteryData.cells) end
            cellCount = batteryData.cells
        end

        isCharged = currentVoltage >= cellCount * minPerCell
        doneVoltageCheck = true
    elseif battsel.source.voltage then
        if battsel.source.voltage:value() == nil then
            if debug then print("DEBUG(doBatteryVoltageCheck): Voltage sensor reading is nil. Exiting.") end
            return
        end
        currentVoltage = battsel.source.voltage:value()
        cellCount = math.floor(currentVoltage / minPerCell + 0.5)
        if debug then
            print("DEBUG(doBatteryVoltageCheck): Estimated cell count from voltage = " .. cellCount ..
                  " using minPerCell = " .. minPerCell)
        end
        if currentVoltage >= cellCount * ((battsel.Config.minChargedCellVoltage.hv or 430) / 100) then
            if debug then
                print("DEBUG(doBatteryVoltageCheck): Voltage (" .. currentVoltage .. "V) exceeds cellCount * HV threshold (" ..
                      cellCount .. " * " .. ((battsel.Config.minChargedCellVoltage.hv or 430) / 100) .. "V). Incrementing cell count.")
            end
            cellCount = cellCount + 1
        end
        if batteryData and batteryData.cells and batteryData.cells > 0 then
            if debug then
                print("DEBUG(doBatteryVoltageCheck): Overriding estimated cell count with batteryData.cells = " .. batteryData.cells)
            end
            cellCount = batteryData.cells
        end
    end

    if cellCount == 0 then
        cellCount = 1
    end

    -- Check if the voltage is below 3V. If so, exit the function.
    -- Some units will return some voltage on the Voltage sensor when connected over USB.
    -- In other cases, the battery voltage sensor may be from an ESC, and the voltage may be low until the ESC initilizes.
    -- In either of these cases, the alert should be skipped.

    -- With this added I have reduced the delay in running the voltage check from 15s to 5s, since this should skip the 
    -- alert if the voltage sensor is low due to ESC not being initialized yet.
    if currentVoltage and currentVoltage < 3 then
        if debug then print("DEBUG(doBatteryVoltageCheck): Voltage is less than 3V. Exiting.") end
        return
    end

    if cellCount and currentVoltage then
        isCharged = currentVoltage >= cellCount * minPerCell
        if debug then
            print("DEBUG(doBatteryVoltageCheck): Voltage Sensor Found. Reading: " .. currentVoltage .. "V")
            print("DEBUG(doBatteryVoltageCheck): Cell Count: " .. cellCount)
            print("DEBUG(doBatteryVoltageCheck): Battery Charged: " .. tostring(isCharged))
        end

        if not isCharged and not voltageDialogDismissed then
            if debug then print("DEBUG(doBatteryVoltageCheck): Battery not charged.") end

            if debug then print("DEBUG(doBatteryVoltageCheck): Playing audio..."  ) end
            system.playFile(voicePath .. "/" .. battsel.Config.batteryCheckAudioFile .. ".wav" or voicePath .. "/battery.wav")

            if debug then print("DEBUG(doBatteryVoltageCheck): Opening low voltage dialog.") end
            local buttons = {
                { label = "OK", action = function()
                    voltageDialogDismissed = true
                    if debug then print("DEBUG(doBatteryVoltageCheck): Voltage Dialog Dismissed") end
                    return true
                end }
            }

            if battsel.Config.doHaptic then
                system.playHaptic(hapticPatterns[battsel.Config.hapticPattern][1])
            end

            form.openDialog({
                title = "Low Battery Voltage",
                message = "Battery may not be charged!",
                width = 350,
                buttons = buttons,
                options = TEXT_LEFT,
            })
        end
        if debug then print("DEBUG(doBatteryVoltageCheck): Voltage check complete.") end
    end
end


local newPercent = 100

local function updateRemainingSensor()
    local debug = battsel.useDebug.updateRemainingSensor
    if not battsel.source.percent then
        if debug then print("Searching for Remaining Sensor") end
        battsel.source.percent = utils.getSensor("Remaining", UNIT_PERCENT)
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
        if debug then print("Unable to Find or Create Remaining Sensor") end
        return
    end
end


local lastAlertedThreshold 
local lastZeroAlertTime = os.clock()

-- Capacity Alerts
local function doCapAlert(threshold)
    local debug = battsel.useDebug.doCapAlert
    local now = os.clock()

    if threshold == 0 then
        -- For 0%, only play if at least 10 seconds have passed
        if now - lastZeroAlertTime < 10 then
            if debug then print("DEBUG(doCapAlert): 0% alert skipped (cooldown not met)") end
            return
        end
        lastZeroAlertTime = now
    else
        -- For other thresholds, only play if not already alerted
        if lastAlertedThreshold == threshold then
            if debug then print("DEBUG(doCapAlert): Alert for " .. threshold .. "% already played") end
            return
        end
        lastAlertedThreshold = threshold
    end
  
    if debug then print("DEBUG(doCapAlert): Playing alert for threshold: " .. threshold) end

    system.playFile(voicePath .. "/battery.wav")
    system.playNumber(threshold, UNIT_PERCENT, 0)
end

local lastVoltAlertTime = os.clock()

local function doVoltAlert(threshold, type)
    local debug = battsel.useDebug.doVoltAler
    local type = type or "low"

    local now = os.clock()
    if now - lastVoltAlertTime < 5 then
        if debug then print("DEBUG(doVoltAlert): Alert skipped (cooldown not met)") end
        return
    end
    lastVoltAlertTime = now

    if debug then print("DEBUG(doVoltAlert): Playing alert for threshold: " .. threshold) end

    if type == "low" then
        system.playFile(voicePath .. "/" .. battsel.Config.alertLowVoltAudio .. ".wav" or voicePath .. "/battery.wav")
    elseif type == "critical" then
        system.playFile(voicePath .. "/" .. battsel.Config.alertCriticalVoltAudio .. ".wav" or voicePath .. "/battery.wav")
    end
end


--- Retrieves the current battery consumption in milliampere-hours (mAh).
-- This function attempts to obtain the "Consumption" sensor value, caches it,
-- and returns the value rounded down to the nearest integer.
-- If the sensor or value is unavailable, it returns 0.
-- @return number The current battery consumption in mAh, or 0 if unavailable.
local function getmAh()
    local debug = battsel.useDebug.getmAh

    battsel.source.consumption = battsel.source.consumption or utils.getSensor("Consumption", UNIT_MILLIAMPERE_HOUR)

    if battsel.source.consumption then
        local value = battsel.source.consumption:value()
        if value then
            if debug then print("DEBUG(getmAh): mAh Reading: " .. math.floor(value) .. "mAh") end
            return math.floor(value)
        end
    end
    return 0
end

-- This function is called when the widget is first created, but is not currently used for anything
local function create()

end

local widgetInit = true
local matchingBatteries
local fieldHeight
local fieldWidth

local function build()
    local debug = battsel.useDebug.build
    local w, h = lcd.getWindowSize()

    -- Build matchingBatteries as a list of battery indices
    matchingBatteries = {}
    if #battsel.Data.Batteries > 0 then
        if currentModelID then
            for i = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[i].modelID == currentModelID then
                    table.insert(matchingBatteries, i)
                end
            end
            if #matchingBatteries == 0 then
                -- If none match currentModelID, use all batteries
                for i = 1, #battsel.Data.Batteries do
                    table.insert(matchingBatteries, i)
                end
            end
            -- If a favorite exists for the currentModelID, use it
            for i = 1, #battsel.Data.Batteries do
                if battsel.Data.Batteries[i].modelID == currentModelID and battsel.Data.Batteries[i].favorite then
                    selectedBattery = i
                    break
                end
            end
        else
            for i = 1, #battsel.Data.Batteries do
                table.insert(matchingBatteries, i)
            end
            if #matchingBatteries > 0 then
                selectedBattery = matchingBatteries[1]
            end
        end
    end

    if selectedBattery == nil then
        selectedBattery = 1
    end

    if debug then
        local batteryNames = {}
        for _, batteryIndex in ipairs(matchingBatteries) do
            table.insert(batteryNames, battsel.Data.Batteries[batteryIndex].name)
        end
        if batteryNames then print("DEBUG(build): Matching Batteries: " .. table.concat(batteryNames, ", ")) end
        if battsel.Data.Batteries[selectedBattery] then 
            print("DEBUG(build): Selected Battery: " .. battsel.Data.Batteries[selectedBattery].name)
        end
    end

    -- Initialize widget dimensions
    if widgetInit then
        if radio.board == "X18" or radio.board == "X18S" then
            fieldHeight = 30
        else
            fieldHeight = 40
        end
        local padding = 10
        fieldWidth, _ = lcd.getWindowSize()
        fieldWidth = math.min(fieldWidth - padding * 2, 200)
        form.create()
        widgetInit = false
    end

    if fieldHeight and fieldWidth and matchingBatteries then
        form.clear()
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)
        local fieldSize = {x = pos_x, y = pos_y, w = fieldWidth, h = fieldHeight}

        -- Create a display table from matchingBatteries (each entry is {batteryName, batteryIndex})
        local displayChoices = {}
        for _, batteryIndex in ipairs(matchingBatteries) do
            table.insert(displayChoices, {battsel.Data.Batteries[batteryIndex].name, batteryIndex})
        end

        -- Create the choice field using the actual battery indices
        formFields["batteryChoiceField"] = form.addChoiceField(
            nil,
            fieldSize,
            displayChoices,
            function() return selectedBattery end,
            function(value)
                selectedBattery = value
                if debug then
                    print("DEBUG(build): Battery chosen from picker; selectedBattery set to " .. tostring(selectedBattery))
                end
            end
        )
    end 
end

local lastmAh = 0
local lastModelID = nil
local lastTime = os.clock()
local lastBattCheckTime = os.clock()
local resetDone = false

local lastRunTimes = {}

-- Simple task scheduler
local function shouldRun(period)
    local now = os.clock()
    if not lastRunTimes[period] or (now - lastRunTimes[period] >= period) then
        lastRunTimes[period] = now
        return true
    else
        return false
    end
end

local function shouldRunBatteryCheck(delay, maxTime)
    local now = os.clock()
    if not batteryConnectTime then
        batteryConnectTime = now
    end
    if now - batteryConnectTime > maxTime then
        -- More than maxTime has passed since battery connect – do not run the check.
        return false
    elseif now - lastBattCheckTime >= delay then
        lastBattCheckTime = now
        return true
    else
        return false
    end
end

local voltageAlertTimer = {}

local function wakeup()
    local debug = battsel.useDebug.wakeup

    if shouldRun(0.05) then -- This loop runs every 50ms
        -- Assign telemetry active event to battsel.source.telem if not already
        if battsel.source.telem == nil then
            battsel.source.telem = system.getSource({category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE, options = nil})
        end
        if battsel.source.telem and battsel.source.telem:state() then
            tlmActive = battsel.source.telem:state() -- Get the telemetry state
        end

        -- Check for modelID sensor presence and assign currentModelID
        battsel.source.modelID = battsel.source.modelID or utils.getSensor("Model ID", nil)

        if battsel.source.modelID and battsel.source.modelID:value() then
            currentModelID = math.floor(battsel.source.modelID:value())
        end
    end

    if shouldRun(0.25) then -- This loop runs every 250ms
        if battsel.Config.checkBatteryVoltageOnConnect and tlmActive then
            if shouldRunBatteryCheck(5, 60) then -- This will only run if it's been more than 15s but less than 60s since tlm became active
                if not doneVoltageCheck and not voltageDialogDismissed then
                    if debug then print("Debug(wakeup): Running Battery Voltage Check") end
                    doBatteryVoltageCheck()
                end
            end
        else
            voltageDialogDismissed = false  -- Reset the dialog dismissed flag when telemetry becomes inactive
            lastBattCheckTime = os.clock()   -- Reset the battery check timer when telemetry becomes inactive
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

    if shouldRun(1.0) then -- This loop runs every 1000ms
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
        if #battsel.Data.Batteries > 0 and tlmActive and selectedBattery and battsel.Config.useCapacity  then
            local newmAh = getmAh()
            if newmAh ~= lastmAh then
                local usablemAh = battsel.Data.Batteries[selectedBattery].capacity * (battsel.Config.useCapacity / 100)
                newPercent = math.floor(100 - (newmAh / usablemAh) * 100 + 0.5)
                if newPercent < 0 then newPercent = 0 end
                lastmAh = newmAh
            end
        end

        if debug then print ("DEBUG(wakeup): Updating Remaining sensor.") end
        updateRemainingSensor() -- Update the remaining sensor based on newPercent value

        -- ######### Alerts ######### --
        -- Check if alert mute source is already assigned, if not, assign it
        if battsel.source.mute == nil then
            if battsel.Config.AlertMute then 
                battsel.source.mute = system.getSource({category = battsel.Config.AlertMute.category, member = battsel.Config.AlertMute.member}) 
            end
        end

        -- Set alertMute boolean if source exists and is valid
        local alertMute = battsel.source.mute and battsel.source.mute:state()

        -- If alerts are enabled and alerts are not muted, run doCapAlert if newPercent matches any of the thresholds
        if battsel.Config.enableAlerts and newPercent then
            if not alertMute then
                if debug then print("DEBUG(wakeup): Alerts check running...") end
                for _, threshold in ipairs(battsel.Config.Alerts) do
                    if newPercent == threshold then
                        doCapAlert(threshold)
                        break
                    end
                end
            else
                if debug then print("DEBUG(wakeup): Alerts are muted. Skipping alerts check...") end
            end
        end
        
        -- If voltage alerts are enabled and alerts are not muted, run doVoltAlert if currentVoltage matches any of the thresholds, but only if it's been below the threshold for the falsePositiveDelay
        if battsel.Config.enableVoltageAlerts then
            if not alertMute then
                if debug then print("DEBUG(wakeup): Voltage Alerts check running...") end
                local lowThreshold = battsel.Config.alertLowCellVoltage or 350
                local criticalThreshold = battsel.Config.alertCriticalCellVoltage or 330
                local falsePositiveDelay = battsel.Config.alertFalsePositiveDelay or 0

                -- Try to get voltage and cell count from sensors
                local currentVoltage
                if battsel.source.voltage then
                    currentVoltage = battsel.source.voltage:value()
                end

                if currentVoltage and cellCount and cellCount > 0 then
                    local cellVoltage = currentVoltage / cellCount
                    if debug then print("DEBUG(wakeup): Cell Voltage: " .. cellVoltage) end

                    -- Use a single timer for both thresholds
                    voltageAlertTimer = voltageAlertTimer or { state = nil, since = nil }

                    local now = os.clock()
                    local alertType = nil

                    if cellVoltage < (criticalThreshold / 100) then
                    alertType = "critical"
                    elseif cellVoltage < (lowThreshold / 100) then
                    alertType = "low"
                    end

                    if alertType then
                        if voltageAlertTimer.state ~= alertType then
                            voltageAlertTimer.state = alertType
                            voltageAlertTimer.since = now
                            if debug then print("DEBUG(wakeup): Starting " .. alertType .. " voltage alert timer") end
                        elseif now - voltageAlertTimer.since >= falsePositiveDelay then
                            if debug then print("DEBUG(wakeup): Cell Voltage is below " .. alertType .. " threshold for delay: " .. falsePositiveDelay) end
                            doVoltAlert(cellVoltage, alertType)
                            voltageAlertTimer.state = nil
                            voltageAlertTimer.since = nil
                        end
                    else
                    voltageAlertTimer.state = nil
                    voltageAlertTimer.since = nil
                    end
                end
            end
        end

        -- Set the model image based on the currentModelID.  If not present or invalid, set it to the default image
        if battsel.Config.modelImageSwitching then
            local currentBitmapName = model.bitmap():match("([^/]+)$")
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
    favoritesPanel = form.addExpansionPanel("Favorite Batteries")
    favoritesPanel:open(false)
    fillFavoritesPanel(favoritesPanel, battsel)

    -- Fill Images panel
    if debug then print("DEBUG(configure): Filling Images Panel") end
    imagePanel = form.addExpansionPanel("Model Image Switching")
    imagePanel:open(false)
    fillImagePanel(imagePanel, battsel)

    if debug then print("DEBUG(configure): Filling Voltage Alerts Panel") end
    voltAlertsPanel = form.addExpansionPanel("Voltage Alerts")
      voltAlertsPanel:open(false)
    fillVoltAlertsPanel(voltAlertsPanel, battsel)

    if debug then print("DEBUG(configure): Filling Alerts Panel") end
    capAlertsPanel = form.addExpansionPanel("Capacity Alerts")
    capAlertsPanel:open(false)
    fillCapAlertsPanel(capAlertsPanel, battsel)

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

    -- In your read() function, update the default configuration:
    local defaultConfig = {
        useCapacity = 80,
        checkBatteryVoltageOnConnect = false,
        minChargedCellVoltage = { lv = 415, hv = 430 },
        doHaptic = false,
        hapticPattern = 1,
        modelImageSwitching = true,
        Images = { Default = "" },
        AlertsID = 1,
        Alerts = { 50, 5, 0 }
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
