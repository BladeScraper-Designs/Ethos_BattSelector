-- Lua Battery Selector and Alarm widget
-- BattSelect + ETHOS LUA configuration

-- Known Issues:
-- 1. If you change models to another model with BattSelector, the Remaining Sensor will not function.
-- 2. If you change models to another model with BattSelector, the matchingBatteries list (and therefore widget choiceField) will not update. 

-- Restarting the radio makes 1 and 2 work again, but I'd like to figure out *why* it happens and fix it properly at some point.

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
    paint = false,
    wakeup = false,
    configure = false
}

local numBatts = 0
local useCapacity
local Batteries = {}
local uniqueIDs = {}
local defaultImage
local Images = {}

local favoritesPanel
local imagePanel
local batteryPanel
local prefsPanel

local rebuildWidget = false
local rebuildPrefs = false

local tlmActive
local currentModelID

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

    local line = imagePanel:addLine("Default Image")
    local field = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function()
        return defaultImage
    end, function(newValue)
        defaultImage = newValue
    end)

    if debug then print("Debug(fillImagePanel):" .. "Default Image: " .. defaultImage) end

    -- List out available Model IDs in the Favorites panel
    for i, id in ipairs(uniqueIDs) do
        local line = imagePanel:addLine("ID " .. uniqueIDs[i] .. " Image")
        local id = uniqueIDs[i]

        local field = form.addFileField(line, nil, "/bitmaps/models", "image+ext", function()
            return Images[id] or ""
        end, function(newValue)
            Images[id] = newValue
        end)
    end

    if debug then
        for i, id in ipairs(uniqueIDs) do
        print("Debug(fillImagePanel): Image for ID " .. id .. ": " .. Images[id])
        end
    end
end


local function fillBatteryPanel(batteryPanel, widget)
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

    elseif string.find(radio.board, "X18") or radio.board == "X18S" or radio.board == "TWXLITES" then
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
    local line = prefsPanel:addLine("Use Capacity")
    local field = form.addNumberField(line, nil, 50, 100, function() return useCapacity end, function(value) useCapacity = value end)
    field:suffix("%")
    field:default(80)

    -- Create field to enable/disable battery voltage checking on connect
    local line = prefsPanel:addLine("Enable Voltage Check")
    local field = form.addBooleanField(line, nil, function() return checkBatteryVoltageOnConnect end, function(newValue) checkBatteryVoltageOnConnect = newValue rebuildPrefs = true end)
    if checkBatteryVoltageOnConnect then
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
    if debug then print("Debug(doBatteryVoltageCheck): Running Battery Voltage Check") end

    local cellCount
    local currentVoltage
    local isCharged

    if not batteryConnectTime then
        batteryConnectTime = os.clock()
    end

    if batteryConnectTime and (os.clock() - batteryConnectTime) <= 30 then
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
            currentVoltage = voltageSensor:value()
            cellCount = math.floor(cellSensor:value())
            isCharged = currentVoltage >= cellCount * minChargedCellVoltage 
            doneVoltageCheck = true
        elseif voltageSensor then
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
                    width = 325,
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
    if percentSensor == nil then
        percentSensor = system.getSource({category = CATEGORY_TELEMETRY, appId = 0x4402, physId = 0x11, name = "Remaining"})
        if percentSensor == nil then
            percentSensor = model.createSensor()
            percentSensor:name("Remaining")
            percentSensor:unit(UNIT_PERCENT)
            percentSensor:decimals(0)
            percentSensor:appId(0x4402)
            percentSensor:physId(0x11)
        end
    end 
    if percentSensor ~= nil then
        percentSensor:value(newPercent)
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

local formCreated = false
local selectedBattery
local matchingBatteries

local function build(widget)
    local w, h = lcd.getWindowSize()
    if matchingBatteries and selectedBattery then
        for i, battery in ipairs(matchingBatteries) do
        end
    end

    -- Set form size based on radio type
    if string.find(radio.board, "X20") or radio.board == "X18R" or radio.board == "X18RS" then
        fieldHeight = 40
        fieldWidth = 145
    elseif radio.board == "X18" or radio.board == "X18S" or radio.board == "TWXLITES" then
        fieldHeight = 30
        fieldWidth = 100
    else
        -- Currently not tested on other radios (X10,X12,X14)
    end

    if #Batteries > 0 and selectedBattery ~= nil then
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)

        -- Create form and add choice field for selecting battery
        local choiceField
        form.create()
        choiceField = form.addChoiceField(line, {x = pos_x, y = pos_y, w = fieldWidth, h = fieldHeight}, matchingBatteries, function() return selectedBattery end, function(value) 
            selectedBattery = value 
        end)
        -- Set the formCreated flag to true once it's created the first time
        formCreated = true
    end
end

local lastmAh = 0
local modelIDSensor

local function refreshMatchingBatteries()
    matchingBatteries = {}

    if #Batteries > 0 then
        if modelIDSensor ~= nil then
            if currentModelID == nil then
                for i = 1, #Batteries do
                    matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
                end
            else
                for i = 1, #Batteries do
                    if Batteries[i].modelID == currentModelID then
                        matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
                    end
                end
            end
        else
            for i = 1, #Batteries do
                matchingBatteries[#matchingBatteries + 1] = {Batteries[i].name, i}
            end
        end

        if selectedBattery == nil then
            if currentModelID ~= nil then
                for i = 1, #Batteries do
                    if Batteries[i].modelID == currentModelID and Batteries[i].favorite then
                        selectedBattery = i
                        break
                    end
                end
            elseif selectedBattery == nil and #matchingBatteries > 0 then
                selectedBattery = matchingBatteries[1][2]
            end
        end
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
        -- Only run the battery voltage check 3 seconds after telemetry becomes active to prevent reading voltage before Voltage telemetry is established and valid (nonzero)
        if currentTime - lastBattCheckTime >= 3 then
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
        if modelIDSensor == nil then 
            modelIDSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Model ID"})
            if modelIDSensor ~= nil and modelIDSensor:value() ~= nil then
                currentModelID = math.floor(modelIDSensor:value())
            end
        else
            if modelIDSensor:value() ~= nil then
                currentModelID = math.floor(modelIDSensor:value())
            end
        end
            
        local currentBitmapName = model.bitmap():match("([^/]+)$")

        -- Set the model image based on the currentModelID.  If not present or invalid, set it to the default image
        if tlmActive and currentModelID and Images[currentModelID] then
            if currentBitmapName ~= Images[currentModelID] then
                model.bitmap(Images[currentModelID])
                if debug then print("Debug(wakeup: Setting model image to " .. (Images[currentModelID])) end
            end
        elseif not tlmActive and currentBitmapName ~= defaultImage then
            if defaultImage then
                model.bitmap(defaultImage)
                if debug then print("Debug(wakeup): Setting model image to " .. defaultImage) end
            end
        end
        
        -- If the modelID has changed, reset the selectedBattery to nil and set rebuildMatching to true
        if currentModelID ~= lastModelID then
            selectedBattery = nil
            lastModelID = currentModelID 
            rebuildMatching = true
            if debug then print ("Debug(wakeup): Model ID changed.  Rebuilding matchingBatteries list") end
        end
        lastTime = currentTime
    end

    -- If the rebuildMatching flag is true, refresh the matchingBatteries list and rebuild the widget
    if rebuildMatching then 
        refreshMatchingBatteries()
        rebuildMatching = false
        rebuildWidget = true
    end

    if rebuildWidget then
        refreshMatchingBatteries()
        build(widget)
        rebuildWidget = false
    end

    if rebuildPrefs then
        prefsPanel:clear()
        fillPrefsPanel(prefsPanel, widget)
        rebuildPrefs = false
    end
end


-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure(widget)
    if numBatts == nil then
        numBatts = 0
    end
    -- Fill Batteries panel
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, widget)

    -- Fill Favorites panel
    favoritesPanel = form.addExpansionPanel("Favorites")
    favoritesPanel:open(false)
    fillFavoritesPanel(favoritesPanel, widget)

    imagePanel = form.addExpansionPanel("Images")
    imagePanel:open(false)
    fillImagePanel(imagePanel, widget)

    prefsPanel = form.addExpansionPanel("Preferences")
    prefsPanel:open(false)
    fillPrefsPanel(prefsPanel, widget)

    -- Alerts Panel.  Commented out for now as not in use
    -- local alertsPanel
    -- alertsPanel = form.addExpansionPanel("Alerts")
    -- alertsPanel:open(false)
    -- fillAlertsPanel(alertsPanel, widget)
end

local function read(widget) -- Read configuration from storage
    numBatts = storage.read("numBatts") or 0
    useCapacity = storage.read("useCapacity") or 80
    Batteries = {}
    if numBatts > 0 then
        for i = 1, numBatts do
            local name = storage.read("Battery" .. i .. "_name") or "Battery " .. i
            local capacity = storage.read("Battery" .. i .. "_capacity") or 0
            local modelID = storage.read("Battery" .. i .. "_modelID") or 0
            local favorite = storage.read("Battery" .. i .. "_favorite") or false
            Batteries[i] = {
                name = name,
                capacity = capacity,
                modelID = modelID,
                favorite = favorite
            }
        end
    end
    local uniqueIDs = {}
    local seen = {}
    for i = 1, numBatts do
        local id = Batteries[i].modelID
        if not seen[id] then
            seen[id] = true
            table.insert(uniqueIDs, id)
        end
    end

    checkBatteryVoltageOnConnect = storage.read("checkBatteryVoltageOnConnect") or false
    if checkBatteryVoltageOnConnect then
        minChargedCellVoltage = storage.read("minChargedCellVoltage") or 415
        doHaptic = storage.read("doHaptic") or false
        hapticPattern = storage.read("hapticPattern") or 1
    end
    
    defaultImage = storage.read("defaultImage") or ""

    Images = {}
    for i = 1, #uniqueIDs do
        local id = uniqueIDs[i]
        Images[id] = storage.read("Images" .. id)
    end
end


local function write(widget) -- Write configuration to storage
    storage.write("numBatts", numBatts)
    storage.write("useCapacity", useCapacity)
    if numBatts > 0 then
        for i = 1, numBatts do
            storage.write("Battery" .. i .. "_name", Batteries[i].name)
            storage.write("Battery" .. i .. "_capacity", Batteries[i].capacity)
            storage.write("Battery" .. i .. "_modelID", Batteries[i].modelID)
            storage.write("Battery" .. i .. "_favorite", Batteries[i].favorite)
        end
    end
    storage.write("checkBatteryVoltageOnConnect", checkBatteryVoltageOnConnect)
    if checkBatteryVoltageOnConnect then
        storage.write("minChargedCellVoltage", minChargedCellVoltage)
        storage.write("doHaptic", doHaptic)
        if doHaptic then storage.write("hapticPattern", hapticPattern) end
    end
    
    storage.write("defaultImage", defaultImage)
    for id, image in pairs(Images) do storage.write("Images" .. id, image) end
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
