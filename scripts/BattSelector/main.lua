-- Lua Battery Selector and Alarm widget
-- BattSelect + ETHOS LUA configuration
-- Set to true to enable debug output for each function
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
local flyTo
local Batteries = {}

local favoritesPanel
local batteryPanel

local rebuildForm = false
local rebuildWidget = false

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
        local field = form.addNumberField(line, pos_ModelID_Value, 0, 99, function() return Batteries[i].modelID end, function(value)
            Batteries[i].modelID = value
            rebuildForm = true
        end)
        field:default(0)
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

-- Alerts Panel, commented out for now as not in use
-- local function fillAlertsPanel(alertsPanel, widget)
--     local line = alertsPanel:addLine("Eventually")
-- end

local voltageSensor
local voltageDialogDismissed = false
local isCharged
local batteryConnectTime
local doneVoltageCheck = false
local checkBatteryVoltageOnConnect

-- Estimate cellcount and check if battery is charged
-- Will be implemented properly later, only popping up if it's just after first plugging in the battery
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
        local currentVoltage = voltageSensor:value() or nil
        if currentVoltage ~= nil then
                
            -- Minimum and maximum voltages per cell
            local minChargedCellVoltage, maxChargedCellVoltage = 4.15, 4.35 -- Voltage per cell (used for estimation)
    
            local estimatedCells = math.floor(currentVoltage / minChargedCellVoltage + 0.5)
    
            if currentVoltage >= estimatedCells * maxChargedCellVoltage then
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
                end}
            }
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
        percentSensor = system.getSource({category = CATEGORY_TELEMETRY, appId = 0x4402})

        if percentSensor == nil then
            if useDebug then
                print("% Remaining sensor not found, creating...")
            end
            -- if sensor does not already exist, make it
            percentSensor = model.createSensor()
            if percentSensor == nil then
                if useDebug then print("Unable to create sensor") end
                return -- in case there is no room for another sensor, exit
            end

            percentSensor:name("Remaining")
            percentSensor:unit(UNIT_PERCENT)
            percentSensor:decimals(0)
            percentSensor:appId(0x4402)
            percentSensor:physId(0x10)
        end
    end
    
    -- Write current % remaining to the % sensor
    percentSensor:value(math.floor(newPercent))

    if useDebug.updateRemainingSensor then
        if percentSensor:value() ~= nil then
            print("Debug(updateRemainingSensor): Remaining: " .. math.floor(percentSensor:value()) .. "%")
        end
    end
end


local mAhSensor

local function getmAh()
    if mAhSensor == nil then
        if useDebug.getmAh then
            print("Debug(getmAh): Searching for mAh Sensor...")
        end
        for member = 0, 25 do
            local candidate = system.getSource({
                category = CATEGORY_TELEMETRY_SENSOR,
                member = member
            })

            if candidate then
                if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                    mAhSensor = candidate
                    if useDebug.getmAh then
                        print("Debug(getmAh): Found mAh sensor: " .. "'" .. mAhSensor:name() .. "'")
                    end
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
        if useDebug.getmAh then
            print("Debug(getmAh): No valid mAh sensor found or value is nil.")
        end
        return 0
    end
end

-- This function is called when the widget is first created
local function create(widget)
    -- return
end

local formCreated = false
local selectedBattery
local matchingBatteries = {}
local currentModelID = 0

local function build(widget)
    if selectedBattery == nil then
        selectedBattery = 1
    end

    local w, h = lcd.getWindowSize()

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

    if #Batteries > 0 and currentModelID ~= nil and selectedBattery ~= nil then
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

local function paint(widget)
    -- Idk if this is needed since I'm not drawing anything on the LCD but I'm leaving it here for now
end

local lastMillis = 0
local lastmAh = 0
local doTheMaths = false
local modelIDSensor

local function wakeup(widget)
    -- Check time since last loop, if >1.0s, do all the stuff
    local millis = os.clock()
    if (millis - lastMillis) >= 1.0 then
        tlmActive = system.getSource({category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE, options = nil}):state()
        if not tlmActive then -- Reset all doBatteryVoltageCheck parameters so that it can run again on next battery connect
            voltageDialogDismissed = false
            doneVoltageCheck = false
            batteryConnectTime = nil
        else -- If telemetry is active, run doBatteryVoltageCheck if it hasn't been done yet or already run but dismissed
            if checkBatteryVoltageOnConnect == true and not doneVoltageCheck and not voltageDialogDismissed then
                doBatteryVoltageCheck(widget)
            end
        end

        local newmAh = getmAh()
        lastMillis = millis -- Reset looptime 
        -- if Batteries exist, telemetry is active, a battery is selected, and the mAh reading is not nil, do the maths
        if #Batteries > 0 and tlmActive and selectedBattery and newmAh ~= nil then
            if newmAh ~= lastmAh then
                usablemAh = Batteries[selectedBattery].capacity * (flyTo / 100)
                newPercent = 100 - (newmAh / usablemAh) * 100
                if newPercent < 0 then newPercent = 0 end
                lastmAh = newmAh
                doTheMaths = false
            end
        end 
        updateRemainingSensor(widget) -- Update the remaining sensor

        -- If modelID sensor is not yet acquired, acquire it
        if modelIDSensor == nil then 
            modelIDSensor = system.getSource({category = CATEGORY_TELEMETRY, name = "Model ID"})
        end
        
        -- Get current model ID from Model ID sensor
        currentModelID = modelIDSensor:value() or nil
    
        -- If Batteries are configured and ModelID is valid, create matchingBatteries table and populate it with any Battery that matches the current Model ID 
        if #Batteries > 0 and currentModelID ~= nil then
            matchingBatteries = {}
            for i = 1, #Batteries do
                if Batteries[i].modelID == currentModelID then
                    matchingBatteries[#matchingBatteries + 1] = {
                        Batteries[i].name, i
                    }
                end
            end
            build(widget)
        -- If there is no selectedBattery or it is not valid, find the favorite battery for current Model ID and select it
        if selectedBattery == nil or not Batteries[selectedBattery] or Batteries[selectedBattery].modelID ~= currentModelID then
            for i = 1, #Batteries do
                if Batteries[i].modelID == currentModelID and Batteries[i].favorite then
                    selectedBattery = i
                    break
                    end
                end
            end
        end

        -- Check to see if ModelID has changed, if so, rebuild the widget to update the battery choices
        if currentModelID ~= nil then
            build(widget)
            lastModelID = currentModelID
        elseif currentModelID ~= lastModelID then
            build(widget)
            lastModelID = currentModelID
        else
            return
        end
    end

    -- Rebuild form and widget if needed.  This is done outside of the 1s looptime so that the form/widget updates instantly when required
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

    -- Create field for entering desired "fly-to" percentage (80% typical)
    local line = form.addLine("Use Capacity")
    local field = form.addNumberField(line, nil, 50, 100, function() return flyTo end, function(value) flyTo = value end)
    field:suffix("%")
    field:default(80)

    -- Create field to enable/disable battery voltage checking on connect
    local line = form.addLine("Battery Voltage Check")
    local field = form.addBooleanField(line, nil, function() return checkBatteryVoltageOnConnect end, function(newValue) checkBatteryVoltageOnConnect = newValue end)

    -- Alerts Panel.  Commented out for now as not in use
    -- local alertsPanel
    -- alertsPanel = form.addExpansionPanel("Alerts")
    -- alertsPanel:open(false)
    -- fillAlertsPanel(alertsPanel, widget)
end


local function read(widget) -- Read configuration from storage
    numBatts = storage.read("numBatts") or 0
    flyTo = storage.read("flyTo") or 80
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
end


local function write(widget) -- Write configuration to storage
    storage.write("numBatts", numBatts)
    storage.write("flyTo", flyTo)
    if numBatts > 0 then
        for i = 1, numBatts do
            storage.write("Battery" .. i .. "_name", Batteries[i].name)
            storage.write("Battery" .. i .. "_capacity", Batteries[i].capacity)
            storage.write("Battery" .. i .. "_modelID", Batteries[i].modelID)
            storage.write("Battery" .. i .. "_favorite", Batteries[i].favorite)
        end
    end
    storage.write("checkBatteryVoltageOnConnect", checkBatteryVoltageOnConnect)
end


local function event(widget, category, value, x, y) end


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
        runDebug = runDebug
    })
end


return {init = init}
