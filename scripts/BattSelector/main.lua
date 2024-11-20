-- Lua Battery Selector and Alarm widget
-- BattSelect + ETHOS LUA configuration
-- Set to true to enable debug output for each function

-- Known Issues:
-- 1. If you change models to another model with BattSelector, the Remaining Sensor will not function.
-- 2. If you change models to another model with BattSelector, the matchingBatteries list (and therefore widget choiceField) will not update. 

-- Restarting the radio makes 1 and 2 work again, but I'd like to figure out *why* it happens and fix it properly at some point.

local useDebug = {
    fillBatteryPanel = false,
    updateRemainingSensor = false,
    getmAh = false,
    create = false,
    build = false,
    paint = false,
    wakeup = false,
    configure = false
}

local numBatts
local useCapacity
local Batteries = {}

local favoritesPanel
local batteryPanel
local prefsPanel

local rebuildForm = false
local rebuildWidget = false
local rebuildPrefs = false

local tlmActive

-- Favorites Panel in Configure
local uniqueIDs = {}
local function fillFavoritesPanel(favoritesPanel, widget)
    -- Favorites Panel Header
    -- Header text positions. Eventually I'll do math for different radios but for now I'm just hardcoding.
    local pos_ModelID_Text = {x = 10, y = 8, w = 200, h = 40}
    local pos_Favorite_Text = {x = 530, y = 8, w = 100, h = 40}
    -- Value positions. Eventually I'll do math for different radios but for now I'm just hardcoding.
    local pos_ModelID_Value = {x = 8, y = 8, w = 400, h = 40}
    local pos_Favorite_Value = {x = 350, y = 8, w = 400, h = 40}
    local pos_Delete_Button = {x = 700, y = 8, w = 50, h = 40}

    local line = favoritesPanel:addLine("")

    -- Create header for the battery panel
    local field = form.addStaticText(line, pos_ModelID_Text, "ID")
    local field = form.addStaticText(line, pos_Favorite_Text, "Favorite")

    -- Create a list of unique Model IDs
    local IDs = {}
    local uniqueIDs = {}

    for i = 1, #Batteries do
        local id = Batteries[i].modelID
        if not uniqueIDs[id] then
            uniqueIDs[id] = true
            table.insert(IDs, id)
        end
    end

    -- List out available Model IDs in the Favorites panel
    for i = 1, #IDs do
        local line = favoritesPanel:addLine("")
        local id = IDs[i]

        -- Create Model ID field
        local field = form.addStaticText(line, pos_ModelID_Value, id)

        -- Create Favorite picker field
        local matchingNames = {}
        for j = 1, #Batteries do
            if Batteries[j].modelID == id then
                matchingNames[#matchingNames + 1] = {Batteries[j].name, j}
            end
        end
        local field = form.addChoiceField(line, pos_Favorite_Value,
                                          matchingNames, function()
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

local function fillBatteryPanel(batteryPanel, widget)
    -- Battery Panel Header
    local pos_Battery_Text = {x = 10, y = 8, w = 200, h = 40}
    local pos_Capacity_Text = {x = 530, y = 8, w = 100, h = 40}
    local pos_ModelID_Text = {x = 655, y = 8, w = 100, h = 40}
    local pos_Name_Value = {x = 8, y = 8, w = 400, h = 40}
    local pos_Capacity_Value = {x = 504, y = 8, w = 130, h = 40}
    local pos_ModelID_Value = {x = 642, y = 8, w = 50, h = 40}
    local pos_Options_Button = {x = 700, y = 8, w = 50, h = 40}

    local line = batteryPanel:addLine("")
    local field = form.addStaticText(line, pos_Battery_Text, "Name")
    local field = form.addStaticText(line, pos_Capacity_Text, "Capacity")
    local field = form.addStaticText(line, pos_ModelID_Text, "ID")

    if numBatts == nil then 
        numBatts = 0 
    end

    for i = 1, numBatts do
        local line = batteryPanel:addLine("")
        local field = form.addTextField(line, pos_Name_Value, function() return Batteries[i].name end, function(newName)
            Batteries[i].name = newName
            rebuildForm = true
            rebuildWidget = true
        end)
        local field = form.addNumberField(line, pos_Capacity_Value, 0, 20000, function() return Batteries[i].capacity end, function(value)
            Batteries[i].capacity = value
            rebuildWidget = true
        end)
        field:suffix("mAh")
        field:step(100)
        field:enableInstantChange(false)
        local field = form.addNumberField(line, pos_ModelID_Value, 0, 99, function() return Batteries[i].modelID end, function(value)
            Batteries[i].modelID = value
            rebuildForm = true
        end)
        field:default(0)
        field:enableInstantChange(false)
        local field = form.addTextButton(line, pos_Options_Button, "...", function()
            local buttons = {
                {label = "Cancel", action = function() return true end},
                {label = "Delete", action = function()
                    table.remove(Batteries, i)
                    numBatts = numBatts - 1
                    rebuildForm = true
                    return true
                end},
                {label = "Clone", action = function()
                    local newBattery = {name = Batteries[i].name, capacity = Batteries[i].capacity, modelID = Batteries[i].modelID, favorite = false}
                    table.insert(Batteries, newBattery)
                    numBatts = numBatts + 1
                    rebuildForm = true
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

    local pos_Add_Button = {x = 642, y = 8, w = 108, h = 40}
    local line = batteryPanel:addLine("")
    local field = form.addTextButton(line, pos_Add_Button, "Add New", function()
        numBatts = numBatts + 1
        Batteries[numBatts] = {name = "", capacity = 0, modelID = 0}
        rebuildForm = true
    end)
end


local checkBatteryVoltageOnConnect
local minChargedCellVoltage

-- Settings Panel
local function fillPrefsPanel(prefsPanel, widget)
    print("fillingPrefsPanel")
    local line = prefsPanel:addLine("Use Capacity")
    local field = form.addNumberField(line, nil, 50, 100, function() return useCapacity end, function(value) useCapacity = value end)
    field:suffix("%")
    field:default(80)

    -- Create field to enable/disable battery voltage checking on connect
    local line = prefsPanel:addLine("Battery Voltage Check")
    local field = form.addBooleanField(line, nil, function() return checkBatteryVoltageOnConnect end, function(newValue) checkBatteryVoltageOnConnect = newValue rebuildPrefs = true end)
    if checkBatteryVoltageOnConnect then
        local line = prefsPanel:addLine("Min Charged Voltage Per Cell")
        local field = form.addNumberField(line, nil, 400, 420, function() return minChargedCellVoltage end, function(value) minChargedCellVoltage = value end)
        field:decimals(2)
        field:suffix("V")
    end
end

-- Alerts Panel, commented out for now as not in use
-- local function fillAlertsPanel(alertsPanel, widget)
--     local line = alertsPanel:addLine("Eventually")
-- end

local voltageSensor
local voltageDialogDismissed = false
local batteryConnectTime
local doneVoltageCheck = false
local doHaptic = true

-- Estimate cellcount and check if battery is charged.  If not, popup dialog to alert user
local function doBatteryVoltageCheck(widget)
    if batteryConnectTime == nil then
        batteryConnectTime = os.clock()
    end

    if batteryConnectTime and (os.clock() - batteryConnectTime) <= 30 then
        -- Check if voltage sensor exists, if not, get it
        if voltageSensor == nil then
            voltageSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Voltage"})
        end

        -- Get the current voltage reading
        local currentVoltage
        if voltageSensor ~= nil then
            currentVoltage = voltageSensor:value() or nil
        end

        local isCharged

        if currentVoltage ~= nil then
            -- Minimum and maximum voltages per cell
    
            local estimatedCells = math.floor(currentVoltage / minChargedCellVoltage + 0.5)
            
            if currentVoltage >= estimatedCells * 4.35 then
                estimatedCells = estimatedCells + 1
            end

            -- Calculate the fully charged voltage for the estimated number of cells
            local chargedVoltage = estimatedCells * minChargedCellVoltage
            
            isCharged = currentVoltage >= chargedVoltage
            doneVoltageCheck = true
        end
    
        if isCharged == false and voltageDialogDismissed == false then
            local buttons = {
                {label = "OK", action = function() 
                    voltageDialogDismissed = true 
                    return true 
                end}}
            if doHaptic then
            system.playHaptic("- . - . - . - .")
            end
            form.openDialog({
                title = "Low Battery Voltage",
                message = "Battery may not be charged!",
                width = 325,
                buttons = buttons,
                options = TEXT_LEFT,
            })
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
        for member = 0, 25 do
            local candidate = system.getSource({
                category = CATEGORY_TELEMETRY_SENSOR,
                member = member
            })

            if candidate then
                if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                    mAhSensor = candidate
                    break -- Exit the loop once a valid mAh sensor is found
                end
            end
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
local currentModelID

local function build(widget)
    local w, h = lcd.getWindowSize()
    if matchingBatteries and selectedBattery then
        for i, battery in ipairs(matchingBatteries) do
        end
    end

    -- Get Radio Version to determine field size
    local radio = system.getVersion()

    -- Set form size based on radio type
    if string.find(radio.board, "X20") then
        fieldHeight = 40
        fieldWidth = 145
    elseif string.find(radio.board, "X18") then
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
local lastLoopTime = os.clock()

-- Used to calculated the looptime of wakeup.  Only used for testing purposes.  Enable useDebug.wakeup to enable
local function calculateLoopTime()
    local currentTime = os.clock()
    local elapsedTime = currentTime - lastLoopTime
    lastLoopTime = currentTime
    local looptimeMs = elapsedTime * 1000
    local looptimeHz = 1 / elapsedTime
    print(string.format("Loop time: %.0fms (%.3fHz)", looptimeMs, looptimeHz))
end

local function wakeup(widget)
    -- Get the current uptime
    local currentTime = os.clock()

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

        -- If telemetry is active and voltage check is enabled, run check if it hasn't been done yet
        if tlmActive and checkBatteryVoltageOnConnect and not doneVoltageCheck and not voltageDialogDismissed then
            doBatteryVoltageCheck(widget)
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
        updateRemainingSensor(widget) -- Update the remaining sensor
        -- Check for modelID sensor presence and its value
        if modelIDSensor == nil then 
            modelIDSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Model ID"})
            if modelIDSensor ~= nil and modelIDSensor:value() ~= nil then
                currentModelID = math.floor(modelIDSensor:value()) or nil
            end
        else
            if modelIDSensor:value() ~= nil then
                currentModelID = math.floor(modelIDSensor:value()) or nil
            end
        end
        
            -- If the modelID has changed, reset the selectedBattery to nil and set rebuildMatching to true
        if currentModelID ~= lastModelID then
            selectedBattery = nil
            lastModelID = currentModelID
            rebuildMatching = true
        end
        lastTime = currentTime
    end
    -- If the rebuildMatching flag is true, refresh the matchingBatteries list and rebuild the widget
    if rebuildMatching then 
        refreshMatchingBatteries()
        rebuildMatching = false
        rebuildWidget = true
    end

    -- Rebuild form and widget if needed. This is done outside of the 1s looptime so that the form/widget updates instantly when required
    if rebuildForm then
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, widget)
        favoritesPanel:clear()
        fillFavoritesPanel(favoritesPanel, widget)
        rebuildForm = false
    end

    if rebuildWidget then
        build(widget)
        rebuildWidget = false
    end

    if rebuildPrefs then
        prefsPanel:clear()
        fillPrefsPanel(prefsPanel, widget)
        rebuildPrefs = false
    end

    if useDebug.wakeup then
        calculateLoopTime()
    end
end


-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure(widget)
    -- Fill Batteries panel
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, widget)

    -- Fill Favorites panel
    favoritesPanel = form.addExpansionPanel("Favorites")
    favoritesPanel:open(false)
    fillFavoritesPanel(favoritesPanel, widget)

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
            local name = storage.read("Battery" .. i .. "_name") or ""
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
    checkBatteryVoltageOnConnect = storage.read("checkBatteryVoltageOnConnect") or false
    if checkBatteryVoltageOnConnect then
        minChargedCellVoltage = storage.read("minChargedCellVoltage") or 4.15
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
