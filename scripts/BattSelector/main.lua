-- Lua Battery Selector and Alarm widget

-- Include json library for read/write of config and battery data
local json = require("lib.dkjson")

-- Set to true to enable debug output for each function as needed
local useDebug = {
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

local numBatts = 0
local useCapacity 
local Batteries = {}
local uniqueIDs = {}
local modelImageSwitching = false
local Images = {}

local favoritesPanel
local imagePanel
local batteryPanel
local prefsPanel

local rebuildWidget = false
local rebuildImages = false
local rebuildPrefs = false

local tlmActive = false
local currentModelID = nil

-- Get Radio Version to determine field size
local radio = system.getVersion()

-- Favorites Panel in Configure
local function fillFavoritesPanel(favoritesPanel, widget)
    -- Create list of Unique IDs from on all Batteries' IDs
    uniqueIDs = {}
    local seen = {}
    for i = 1, #Batteries do
        local id = Batteries[i].modelID
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
        for j = 1, numBatts do
            if Batteries[j].modelID == id then
                matchingNames[#matchingNames + 1] = {Batteries[j].name, j}
            end
        end
        local field = form.addChoiceField(line, nil, matchingNames, function()
            for j = 1, #Batteries do
                if Batteries[j].modelID == id and Batteries[j].favorite then
                    return j
                end
            end
            return nil
        end, function(value)
            for j = 1, #Batteries do
                if Batteries[j].modelID == id then
                    Batteries[j].favorite = (j == value)
                end
            end
        end)
    end
end


local function fillImagePanel(imagePanel, widget)
    local debug = useDebug.fillImagePanel

    local line = imagePanel:addLine("Enable Model Image Switching")
    local field = form.addBooleanField(line, nil, function() return modelImageSwitching end, function(newValue) 
        if debug then print("Model Image Switching: " .. tostring(newValue)) end
        modelImageSwitching = newValue 
        rebuildImages = true
    end)
    
    if modelImageSwitching then
        local line = imagePanel:addLine("Default Image")
        local field = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function() return Images.Default or "" end, function(newValue) Images.Default = newValue end)
        if debug then print("Debug(fillImagePanel):" .. "Default Image: " .. Images.Default) end

        -- List out available Model IDs in the Favorites panel
        for i, id in ipairs(uniqueIDs) do
            local line = imagePanel:addLine("ID " .. id .. " Image")
            local key = tostring(id)  -- Convert to string
        
            local field = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function()
                return Images[key] or ""
            end, function(newValue)
                Images[key] = newValue
            end)
            if debug then print("Debug(fillImagePanel): Image for ID " .. id .. ": " .. (Images[key] or "")) end
        end
    end
end


local function fillBatteryPanel(batteryPanel, widget)
    local debug = useDebug.fillBatteryPanel
    if debug then print("Debug(fillBatteryPanel): Filling Battery Panel") end

    local pos_header_battery
    local pos_header_capacity
    local pos_header_id
    local pos_value_name
    local pos_value_capacity
    local pos_value_id
    local pos_options_button
    local pos_add_button

    if string.find(radio.board, "X20") or radio.board == "X18R" or radio.board == "X18RS" then
        -- Header text positions
        pos_header_battery = {x = 10, y = 8, w = 200, h = 40}
        pos_header_capacity = {x = 530, y = 8, w = 100, h = 40}
        pos_header_id = {x = 655, y = 8, w = 100, h = 40}
        -- Value positions
        pos_value_name = {x = 8, y = 8, w = 400, h = 40}
        pos_value_capacity = {x = 504, y = 8, w = 130, h = 40}
        pos_value_id = {x = 642, y = 8, w = 50, h = 40}
        pos_options_button = {x = 700, y = 8, w = 50, h = 40}
        pos_add_button = {x = 642, y = 8, w = 108, h = 40}
    elseif radio.board == "X18" or radio.board == "X18S" or radio.board == "TWXLITE" or radio.board == "TWXLITES" then
        -- Header text positions
        pos_header_battery = {x = 6, y = 6, w = 200, h = 30}
        pos_header_capacity = {x = 300, y = 6, w = 100, h = 30}
        pos_header_id = {x = 390, y = 6, w = 100, h = 30}
        -- Value positions
        pos_value_name = {x = 6, y = 6, w = 275, h = 30}
        pos_value_capacity = {x = 288, y = 6, w = 85, h = 30}
        pos_value_id = {x = 379, y = 6, w = 35, h = 30}
        pos_options_button = {x = 420, y = 6, w = 35, h = 30}
        pos_add_button = {x = 375, y = 6, w = 80, h = 30}
    else
        -- Currently not tested on other radios (X10,X12,X14)
    end

    -- Create header for the battery panel
    local line = batteryPanel:addLine("")
    local field = form.addStaticText(line, pos_header_battery, "Name")
    local field = form.addStaticText(line, pos_header_capacity, "Capacity")
    local field = form.addStaticText(line, pos_header_id, "ID")

    for i = 1, numBatts do
        local line = batteryPanel:addLine("")
        local field = form.addTextField(line, pos_value_name, function() return Batteries[i].name end, function(newName)
            Batteries[i].name = newName
            rebuildWidget = true
        end)

        local field = form.addNumberField(line, pos_value_capacity, 0, 20000, function() return Batteries[i].capacity end, function(value)
            Batteries[i].capacity = value
            rebuildWidget = true
        end)
        field:suffix("mAh")
        field:step(100)
        field:default(0)
        field:enableInstantChange(false)
        local field = form.addNumberField(line, pos_value_id, 0, 99, function() return Batteries[i].modelID end, function(value)
            Batteries[i].modelID = value
            favoritesPanel:clear()
            fillFavoritesPanel(favoritesPanel, widget)
            imagePanel:clear()
            fillImagePanel(imagePanel, widget)
            rebuildWidget = true
        end)
        field:default(0)
        field:enableInstantChange(false)
        local field = form.addTextButton(line, pos_options_button, "...", function()
            local buttons = {
                {label = "Cancel", action = function() return true end},
                {label = "Delete", action = function()
                    table.remove(Batteries, i)
                    numBatts = numBatts - 1
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel, widget)
                    favoritesPanel:clear()
                    fillFavoritesPanel(favoritesPanel, widget)
                    rebuildWidget = true
                    return true
                end},
                {label = "Clone", action = function()
                    local newBattery = {name = Batteries[i].name, capacity = Batteries[i].capacity, modelID = Batteries[i].modelID, favorite = false}
                    table.insert(Batteries, newBattery)
                    numBatts = numBatts + 1
                    favoritesPanel:clear()
                    fillFavoritesPanel(favoritesPanel, widget)
                    imagePanel:clear()
                    fillImagePanel(imagePanel, widget)
                    rebuildWidget = true
                    return true
                end}
            }
            form.openDialog({
                title = (Batteries[i].name ~= "" and Batteries[i].name or "Unnamed Battery"),
                message = "Select Action",
                width = 350,
                buttons = buttons,
                options = TEXT_LEFT,
            })
        end)
    end

    local line = batteryPanel:addLine("")
    local field = form.addTextButton(line, pos_add_button, "Add New", function()
        numBatts = numBatts + 1
        Batteries[numBatts] = {name = "Battery " .. numBatts, capacity = 0, modelID = 0}
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, widget)
        favoritesPanel:clear()
        fillFavoritesPanel(favoritesPanel, widget)
        imagePanel:clear()
        fillImagePanel(imagePanel, widget)
        rebuildWidget = true
    end)
end


local checkBatteryVoltageOnConnect
local minChargedCellVoltage
local doHaptic
local hapticPatterns = {{". . . . . .", 1}, {". - . - . - .", 2}, {". - - . - - . - - . - - .", 3}}
local hapticPattern

-- Settings Panel
local function fillPrefsPanel(prefsPanel, widget)
    local debug = useDebug.fillPrefsPanel
    if debug then print("Debug(fillPrefsPanel): Filling Preferences Panel") end

    local line = prefsPanel:addLine("Use Capacity")
    local field = form.addNumberField(line, nil, 50, 100, function() return useCapacity or 80 end, function(value) useCapacity = value end)
    field:suffix("%")
    field:default(80)

    -- Create field to enable/disable battery voltage checking on connect
    local line = prefsPanel:addLine("Enable Voltage Check")
    local field = form.addBooleanField(line, nil, function() return checkBatteryVoltageOnConnect end, function(newValue) checkBatteryVoltageOnConnect = newValue rebuildPrefs = true end)
    if checkBatteryVoltageOnConnect then
        -- Set default min charged cell voltage to 4.15V
        if minChargedCellVoltage == nil then minChargedCellVoltage = 415 end
        local line = prefsPanel:addLine("Min Charged Volt/Cell")
        local field = form.addNumberField(line, nil, 400, 430, function() return minChargedCellVoltage end, function(value) minChargedCellVoltage = value end)
        field:decimals(2)
        field:suffix("V")
        field:enableInstantChange(false)
        local line = prefsPanel:addLine("Haptic Warning")
        local field = form.addBooleanField(line, nil, function() return doHaptic end, function(newValue) doHaptic = newValue rebuildPrefs = true end)
        if doHaptic then 
            if hapticPattern == nil then hapticPattern = 1 end
            local line = prefsPanel:addLine("Haptic Pattern")
            local field = form.addChoiceField(line, nil, hapticPatterns, function() return hapticPattern end, function(newValue) hapticPattern = newValue end)
        end
    end

    if useDebug.fillPrefsPanel then
        print("fillingPrefsPanel")
    end
end

-- Alerts Panel, commented out for now as not in use
-- local function fillAlertsPanel(alertsPanel, widget)
--     local line = alertsPanel:addLine("Eventually")
-- end

local cellSensor
local voltageSensor
local voltageDialogDismissed = false
local doneVoltageCheck = false
local batteryConnectTime

-- Estimate cellcount and check if battery is charged.  If not, popup dialog to alert user
local function doBatteryVoltageCheck(widget)
    local debug = useDebug.doBatteryVoltageCheck
    local minChargedCellVoltage = minChargedCellVoltage / 100 or 4.15

    local cellCount
    local currentVoltage
    local isCharged

    if not batteryConnectTime then
        batteryConnectTime = os.clock()
    end

    if batteryConnectTime and (os.clock() - batteryConnectTime) <= 60 then
        -- Check if cell count sensor exists (RF 2.2? only), if not, get it
        if not cellSensor then
            cellSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Cell Count"})
            if cellSensor then
                if debug then print("Debug(doBatteryVoltageCheck): RF Cell Count sensor found.  Continuing") end
            else
                if debug then print("Debug(doBatteryVoltageCheck): RF Cell Count sensor not found.  Proceeding with estimation from Voltage") end
            end
        end

        -- Check if voltage sensor exists, if not, get it
        if not voltageSensor then
            voltageSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Voltage"})
            if voltageSensor then 
                if debug then print("Debug(doBatteryVoltageCheck): Voltage Sensor Found.  Continuing") end
            else
                if debug then print ("Debug(doBatteryVoltageCheck): Voltage sensor not found.  Exiting") end
                return
            end
        end
        
        if cellSensor and voltageSensor then
            if cellSensor:value() == nil or voltageSensor:value() == nil then
                if debug then print("Debug(doBatteryVoltageCheck): Cell Count or Voltage sensor reading is nil.  Exiting") end
                return
            end
            currentVoltage = voltageSensor:value()
            cellCount = math.floor(cellSensor:value())
            isCharged = currentVoltage >= cellCount * minChargedCellVoltage 
            doneVoltageCheck = true
        elseif voltageSensor then
            if voltageSensor:value() == nil then 
                if debug then print("Debug(doBatteryVoltageCheck): Voltage sensor reading is nil.  Exiting") end
                return
            end
            currentVoltage = voltageSensor:value()
            -- Estimate cell count based on voltage
            cellCount = math.floor(currentVoltage / minChargedCellVoltage + 0.5)
            -- To prevent accidentally reading a very low battery as a lower cell count than actual, add 1 to cellCount if the voltage is higher than cellCount * 4.35 (HV battery max cell voltage)
            if currentVoltage >= cellCount * 4.35 then
                cellCount = cellCount + 1
            end    
        end

        if cellCount == 0  then
            cellCount = 1
        end

        if cellCount and currentVoltage then 
            isCharged = currentVoltage >= cellCount * minChargedCellVoltage 
            if debug then 
                print("Debug(doBatteryVoltageCheck): Voltage Sensor Found.  Reading: " .. currentVoltage .. "V")
                print("Debug(doBatteryVoltageCheck): Cell Count: " .. cellCount)
                print("Debug(doBatteryVoltageCheck): Battery Charged: " .. tostring(isCharged)) 
            end

            if isCharged == false and voltageDialogDismissed == false then
                if debug then print ("Debug(doBatteryVoltageCheck): Battery not charged!  Popup dialog") end
                local buttons = {
                    {label = "OK", action = function()
                        voltageDialogDismissed = true 
                        if debug then print("Debug(doBatteryVoltageCheck): Voltage Dialog Dismissed") end
                        return true 
                    end}}
                if doHaptic then
                    if debug then print("Debug(doBatteryVoltageCheck): Playing Haptic") end
                    system.playHaptic(hapticPatterns[hapticPattern][1])
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


local percentSensor
local newPercent = 100

local function updateRemainingSensor(widget)
    local debug = useDebug.updateRemainingSensor
    if percentSensor == nil then
        if debug then print("Searching for Remaining Sensor") end
        percentSensor = system.getSource({category = CATEGORY_TELEMETRY, appId = 0x4402, physId = 0x11, name = "Remaining"})
        if percentSensor == nil then
            print("Remaining Sensor Not Found. Creating...")
            percentSensor = model.createSensor()
            percentSensor:name("Remaining")
            percentSensor:unit(UNIT_PERCENT)
            percentSensor:decimals(0)
            percentSensor:appId(0x4402)
            percentSensor:physId(0x11)
            if debug then print(string.format("Remaining Sensor Created: 0x%04X 0x%02X", percentSensor:appId(), percentSensor:physId())) end
        else
            if debug then print(string.format("Remaining Sensor Found: 0x%04X 0x%02X", percentSensor:appId(), percentSensor:physId())) end
        end
    end

    if percentSensor ~= nil then
        if debug then print("Updating Remaining Sensor: " .. newPercent .. "%") end
        percentSensor:value(newPercent)
    else
        if debug then print("Unable to Find/Create Remaining Sensor") end
        return
    end
end


local mAhSensor

local function getmAh()
    if mAhSensor == nil then
        for member = 0, 50 do
            local candidate = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, member = member})
            if candidate then
                if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                    mAhSensor = candidate
                    break -- Exit the loop once a valid mAh sensor is found
                end
            end
        end

        if mAhSensor == nil then
            print("No mAh sensor found!")
            return 0
        end
    end
    
    -- Return the value or 0 if no valid sensor was found
    if mAhSensor and mAhSensor:value() ~= nil then
        if useDebug.getmAh then
            print("Debug(getmAh): mAh Reading: " .. math.floor(mAhSensor:value()) .. "mAh")
        end
        return math.floor(mAhSensor:value())
    else
        return 0
    end
end

-- This function is called when the widget is first created
local function create(widget)
    -- return
end


local lastmAh = 0
local modelIDSensor
local widgetInit = true
local selectedBattery
local matchingBatteries
local fieldHeight
local fieldWidth

local function build(widget)
    local debug = useDebug.build

    local w, h = lcd.getWindowSize()

    -- Refresh the matchingBatteries list based on currentModelID
    matchingBatteries = {}
    if #Batteries > 0 then
        if currentModelID then
            if debug then print("Debug(build): Current Model ID: " .. currentModelID) end
            -- First, try to add batteries matching currentModelID.
            for i = 1, #Batteries do
                if Batteries[i].modelID == currentModelID then
                    matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
                end
            end
            -- If no batteries matched, fall back to adding all batteries.
            if #matchingBatteries == 0 then
                if debug then print("Debug(build): No batteries match currentModelID, falling back to all batteries.") end
                for i = 1, #Batteries do
                    matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
                end
            end
    
            -- Select a battery if a favorite is marked for the currentModelID.
            for i = 1, #Batteries do
                if Batteries[i].modelID == currentModelID and Batteries[i].favorite then
                    selectedBattery = i
                    break
                end
            end
        else
            -- No currentModelID provided; simply add all batteries.
            for i = 1, #Batteries do
                matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
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
        if batteryNames then print("Debug(build): Matching Batteries: " .. table.concat(batteryNames, ", ")) end
        if Batteries[selectedBattery] then 
            local batteryInfo = "Debug(build): Selected Battery: " .. Batteries[selectedBattery].name
            if Batteries[selectedBattery].favorite then
            batteryInfo = batteryInfo .. " (Favorite)"
            end
            print(batteryInfo)
        end
    end

    -- Initialize widget based on radio type
    if widgetInit then
        if debug then print("Debug(build): Widget Init") end
        -- Set form size based on radio type
        if string.find(radio.board, "X20") or radio.board == "X18R" or radio.board == "X18RS" then
            fieldHeight = 40
            fieldWidth = 145
        elseif radio.board == "X18" or radio.board == "X18S" or radio.board == "TWXLITE" or radio.board == "TWXLITES" then
            fieldHeight = 30
            fieldWidth = 100
        else
            -- Currently not tested on other radios (X10,X12,X14)
        end
        if debug then print("Debug(build): Creating form") end
        form.create()
        widgetInit = false
    end
    
    if fieldHeight and fieldWidth and matchingBatteries then
        form.clear()
        if debug then print("Debug(build): Updating Choice Field") end
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)

        -- Create form and add choice field for selecting battery
        local choiceField = form.addChoiceField(line, {x = pos_x, y = pos_y, w = fieldWidth, h = fieldHeight}, matchingBatteries, function() return selectedBattery end, function(value) 
            selectedBattery = value 
        end)
    end
end


local lastModelID = nil
local rebuildMatching = true
local lastTime = os.clock()
local lastBattCheckTime = os.clock()

local function wakeup(widget)
    local debug = useDebug.wakeup

    -- Get the current uptime
    local currentTime = os.clock()

    if checkBatteryVoltageOnConnect and tlmActive then
        -- Only run the battery voltage check 15 seconds after telemetry becomes active to prevent reading voltage before Voltage telemetry is established and valid (nonzero)
        -- Initially this was 3 seconds, but some ESCs take longer to initialize and provide valid voltage telemetry (Scorpion takes over 10 seconds to start sending telemetry)
        if currentTime - lastBattCheckTime >= 15 then
            lastBattCheckTime = currentTime
            -- If telemetry is active and voltage check is enabled, run check if it hasn't been done and dismissed yet
            if not doneVoltageCheck and not voltageDialogDismissed then
                if debug then print ("Debug(wakeup): Running Battery Voltage Check") end
                doBatteryVoltageCheck(widget)
            end
        end
    else
        voltageDialogDismissed = false -- Reset the dialog dismissed flag when telemetry becomes inactive
        lastBattCheckTime = currentTime -- Reset the timer when telemetry becomes inactive
    end

    if currentTime - lastTime >= 1 then
        tlmActive = system.getSource({category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE, options = nil}):state()
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
        if #Batteries > 0 and tlmActive and selectedBattery and newmAh ~= nil and useCapacity ~= nil then
            if newmAh ~= lastmAh then
                local usablemAh = Batteries[selectedBattery].capacity * (useCapacity / 100)
                newPercent = 100 - (newmAh / usablemAh) * 100
                if newPercent < 0 then newPercent = 0 end
                lastmAh = newmAh
            end
        end

        if debug then print ("Debug(wakeup): Updating Remaining Sensor") end
        updateRemainingSensor(widget) -- Update the remaining sensor
        
        -- Check for modelID sensor presence and its value
        if not modelIDSensor then 
            modelIDSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Model ID"})
        end
        if modelIDSensor and modelIDSensor:value() ~= nil then
            currentModelID = math.floor(modelIDSensor:value())
        end
        
        local currentBitmapName = model.bitmap():match("([^/]+)$")

        -- Set the model image based on the currentModelID.  If not present or invalid, set it to the default image
        if modelImageSwitching then
            if tlmActive and currentModelID and Images[tostring(currentModelID)] then
                if currentBitmapName ~= Images[tostring(currentModelID)] then
                    model.bitmap(Images[tostring(currentModelID)])
                    if debug then print("Debug(wakeup): Setting model image to " .. Images[tostring(currentModelID)]) end
                end
            elseif Images and Images.Default and Images.Default ~= "" then
                if currentBitmapName ~= Images.Default then
                    model.bitmap(Images.Default)
                    if debug then print("Debug(wakeup): Setting model image to Default: " .. Images.Default) end
                end
            end
        end
        lastTime = currentTime
    end

    -- Check if the modelID has changed since last wakeup, and if so, set the rebuildMatching flag to true
    if currentModelID ~= lastModelID then
        if debug then print("Debug(wakeup): Model ID has changed") end
        lastModelID = currentModelID 
        rebuildWidget = true
    end

    if rebuildWidget then
        if debug then print ("Debug(wakeup): Rebuilding widget") end
        build(widget)
        rebuildWidget = false
    end

    if rebuildImages then
        if debug then print ("Debug(wakeup): Rebuilding Images Panel") end
        imagePanel:clear()
        fillImagePanel(imagePanel, widget)
        rebuildImages = false
    end

    if rebuildPrefs then
        if debug then print ("Debug(wakeup): Rebuilding Preferences Panel") end
        prefsPanel:clear()
        fillPrefsPanel(prefsPanel, widget)
        rebuildPrefs = false
    end
end


-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure(widget)
    local debug = useDebug.configure
    -- Fill Batteries panel
    if debug then print("Debug(configure): Filling Battery Panel") end
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, widget)

    -- Fill Favorites panel
    if debug then print("Debug(configure): Filling Favorites Panel") end
    favoritesPanel = form.addExpansionPanel("Favorites")
    favoritesPanel:open(false)
    fillFavoritesPanel(favoritesPanel, widget)

    -- Fill Images panel
    if debug then print("Debug(configure): Filling Images Panel") end
    imagePanel = form.addExpansionPanel("Images")
    imagePanel:open(false)
    fillImagePanel(imagePanel, widget)

    -- Preferences Panel
    if debug then print("Debug(configure): Filling Preferences Panel") end
    prefsPanel = form.addExpansionPanel("Preferences")
    prefsPanel:open(false)
    fillPrefsPanel(prefsPanel, widget)

    -- Alerts Panel.  Commented out for now as not in use
    -- local alertsPanel
    -- alertsPanel = form.addExpansionPanel("Alerts")
    -- alertsPanel:open(false)
    -- fillAlertsPanel(alertsPanel, widget)
end

-- Helper function to read a file line by line
local function readFileContent(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil
    end
    local content = ""
    while true do
        local line = file:read("*l")
        if not line then break end
        content = content .. line .. "\n"
    end
    file:close()
    return content
end

-- Helper function to read a file line by line
local function readFileContent(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil
    end
    local content = ""
    while true do
        local line = file:read("*l")
        if not line then break end
        content = content .. line .. "\n"
    end
    file:close()
    return content
end

local function read() 
    local debug = useDebug.read  -- Toggle debug prints for read
    local configFileName = "config.json"
    local batteriesFileName = "batteries.json"

    if debug then print("Debug(read): Starting read()") end
    if debug then print("Debug(read): Config file: " .. configFileName) end
    if debug then print("Debug(read): Batteries file: " .. batteriesFileName) end

    -- Read the configuration data
    local configData = {}
    if debug then print("Debug(read): Attempting to open config file...") end
    local content = readFileContent(configFileName)
    if content then
        if debug then
            print("Debug(read): Raw config file content:")
            print(content)
        end
        if content ~= "" then
            configData = json.decode(content)
            if configData then
                if debug then print("Debug(read): Successfully decoded config data.") end
            else
                if debug then print("Debug(read): Error decoding config data!") end
            end
        else
            if debug then print("Debug(read): Config file is empty!") end
        end
    else
        if debug then print("Debug(read): Config file not found!") end
    end

    -- Set config variables with defaults if needed
    numBatts = configData.numBatts or 0
    useCapacity = configData.useCapacity or 80
    checkBatteryVoltageOnConnect = configData.checkBatteryVoltageOnConnect or false
    minChargedCellVoltage = configData.minChargedCellVoltage or 415
    doHaptic = configData.doHaptic or false
    hapticPattern = configData.hapticPattern or 1
    modelImageSwitching = configData.modelImageSwitching or false
    Images = configData.Images or {}  -- May be empty if not stored

    if debug then
        print("Debug(read): Config variables set:")
        print("  numBatts = " .. tostring(numBatts))
        print("  useCapacity = " .. tostring(useCapacity))
        print("  checkBatteryVoltageOnConnect = " .. tostring(checkBatteryVoltageOnConnect))
        print("  minChargedCellVoltage = " .. tostring(minChargedCellVoltage))
        print("  doHaptic = " .. tostring(doHaptic))
        print("  hapticPattern = " .. tostring(hapticPattern))
        print("  modelImageSwitching = " .. tostring(modelImageSwitching))
        print("  Images = " .. json.encode(Images, { indent = "  " }))
    end

    -- Read the batteries data
    if debug then print("Debug(read): Attempting to open batteries file...") end
    local content2 = readFileContent(batteriesFileName)
    if content2 then
        if debug then
            print("Debug(read): Raw batteries file content:")
            print(content2)
        end
        if content2 ~= "" then
            Batteries = json.decode(content2)
            if Batteries then
                if debug then print("Debug(read): Successfully decoded batteries data.") end
            else
                if debug then print("Debug(read): Error decoding batteries data!") end
                Batteries = {}
            end
        else
            if debug then print("Debug(read): Batteries file is empty!") end
            Batteries = {}  -- Default to an empty table
        end
    else
        if debug then print("Debug(read): Batteries file not found!") end
        Batteries = {}  -- File not found; initialize empty table
    end

    -- Update numBatts based on the Batteries table length
    numBatts = #Batteries
    if debug then print("Debug(read): Final numBatts = " .. tostring(numBatts)) end
    
    if debug then
        local prettyConfig = json.encode(configData, { indent = "  " })
        print("Loaded config data:\n" .. prettyConfig)
        local prettyBatteries = json.encode(Batteries, { indent = "  " })
        print("Loaded batteries data:\n" .. prettyBatteries)
    end
end

local function write()
    local debug = useDebug.write  -- Toggle debug prints for write
    local configFileName = "config.json"
    local batteriesFileName = "batteries.json"

    -- Gather configuration data into a table (excluding battery details)
    local configData = {
        numBatts = numBatts,
        useCapacity = useCapacity,
        checkBatteryVoltageOnConnect = checkBatteryVoltageOnConnect,
        minChargedCellVoltage = minChargedCellVoltage,
        doHaptic = doHaptic,
        hapticPattern = hapticPattern,
        modelImageSwitching = modelImageSwitching,
        Images = Images
    }

    -- Serialize tables with pretty printing (for human readability)
    local jsonConfig = json.encode(configData, { indent = "  " })
    local jsonBatteries = json.encode(Batteries, { indent = "  " })

    -- Write config data to file
    local file = io.open(configFileName, "w")
    if file then
        file:write(jsonConfig)
        file:close()
        if debug then print("Debug(write): Config data written to " .. configFileName) end
    else
        if debug then print("Debug(write): Error: Unable to open " .. configFileName .. " for writing.") end
    end

    -- Write batteries data to file
    local file2 = io.open(batteriesFileName, "w")
    if file2 then
        file2:write(jsonBatteries)
        file2:close()
        if debug then print("Debug(write): Batteries data written to " .. batteriesFileName) end
    else
        if debug then print("Debug(write): Error: Unable to open " .. batteriesFileName .. " for writing.") end
    end
end

local function paint(widget) end

local function event(widget, category, value, x, y) end

local function close()
    Batteries = nil
    matchingBatteries = nil
    currentModelID = nil
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
        runDebug = runDebug,
        close = close
    })
end


return {init = init}
