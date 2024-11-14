-- Lua Battery Selector and Alarm widget

batsell = {}

-- Set to true to enable debug output for each function
local useDebug = {
    getModelID =            false,
    fillBatteryPanel =      false,
    updateRemainingSensor = false,
    getmAh =                false,
    create =                false,
    build =                 false,
    paint =                 false,
    wakeup =                false,
    configure =             false,
}

local sensor
local modelID
local numBatts
local flyTo
local Batteries = {}


-- Battery Panel in Configure
local function fillBatteryPanel(batteryPanel, widget)
    -- Battery Panel Header
    -- Header text positions.  Eventually I'll do math for different radios but for now I'm just hardcoding.
    local pos_Battery_Text = {x=10, y=8, w=200, h=40}
    local pos_Capacity_Text = {x=530, y=8, w=100, h=40}
    local pos_ModelID_Text = {x=655, y=8, w=100, h=40}

    local line = batteryPanel:addLine("")

    -- Create header for the battery panel
    local field = form.addStaticText(line, pos_Battery_Text, "Battery")
    local field = form.addStaticText(line, pos_Capacity_Text, "Capacity")
    local field = form.addStaticText(line, pos_ModelID_Text, "ID")

    -- Ensure numBatts is not nil
    if numBatts == nil then
        numBatts = 0
    end

    -- Battery List
        for i = 1, numBatts do
        -- Value positions.  Eventually I'll do math for different radios but for now I'm just hardcoding.
        local pos_Name_Value = {x=8, y=8, w=400, h=40}
        local pos_Capacity_Value = {x=504, y=8, w=130, h=40}
        local pos_ModelID_Value = {x=642, y=8, w=50, h=40}
        local pos_Delete_Button = {x=700, y=8, w=50, h=40}

        local line = batteryPanel:addLine("Battery " .. i)
            
        -- Create Capacity field for each Battery
        -- I can't get the addTextField below to work so disabling it for now to keep working on the rest of the script
        -- local field = form.addTextField(line, pos_Name_Value, function() return text end, function(newValue) text = newValue end)
        local field = form.addNumberField(line, pos_Capacity_Value, 0, 20000, function() return Batteries[i].capacity end, function(value) Batteries[i].capacity = value end)
        field:suffix("mAh")
        field:step(100)

        -- Create a Model ID field for each battery
        local field = form.addNumberField(line, pos_ModelID_Value, 0, 99, function() return Batteries[i].modelID end, function(value) Batteries[i].modelID = value end)
        field:default(0)
        
        -- Create a delete button for each battery and if pressed, create a dialog to confirm deletion
        local field = form.addTextButton(line, pos_Delete_Button, "X", function()
            local buttons = {
                {label="Yes", action=function()
                    table.remove(Batteries, i)
                    numBatts = numBatts - 1
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel, widget)
                    return true
                end},
                {label="No", action=function() return true end}
            }
            form.openDialog({
                title="Confirm Delete",
                message="Delete Battery " .. i .. "?",
                width=300,
                buttons=buttons,
                options=TEXT_LEFT,
            })
        end)
    end

    -- "Add New" button.  Eventually I'll do math for different radios but for now I'm just hardcoding.
    local pos_Add_Button = {x=642, y=8, w=108, h=40}
    local line = batteryPanel:addLine("")
    local field = form.addTextButton(line, pos_Add_Button, "Add New",  function() numBatts = numBatts + 1 batteryPanel:clear() fillBatteryPanel(batteryPanel, widget) end)

    -- Ensure that Batteries table entries matches numBatts always
    if numBatts > #Batteries then
        Batteries[numBatts] = {name = "Battery " .. numBatts, capacity = 0, modelID = 0}
    elseif numBatts < #Batteries then
        table.remove(Batteries, #Batteries)
    end
end

-- Alerts Panel, commented out for now as not in use
-- local function fillAlertsPanel(alertsPanel, widget)
--     local line = alertsPanel:addLine("Eventually")
-- end


local function updateRemainingSensor(widget)
    local sensor = system.getSource({category=CATEGORY_TELEMETRY, appId=0x4402})
    if sensor == nil then
        if useDebug then
            print("% Remaining sensor not found, creating...")
        end
    -- if sensor does not already exist, make it
        sensor = model.createSensor()
        if sensor == nil then
            if useDebug then
            print("Unable to create sensor")
            end
            return -- in case there is no room for another sensor, exit
        end
    sensor:name("Remaining")
    sensor:unit(UNIT_PERCENT)
    sensor:decimals(0)
    sensor:appId(0x4402)
    sensor:physId(0x10)
    end
    -- Write current % remaining to the % sensor
    sensor:value(currentPercent)

    if useDebug.updateRemainingSensor then
        if sensor:value() ~= nil then
            print("Debug(updateRemainingSensor): Remaining: " .. math.floor(sensor:value()) .. "%")
        end
    end
end


local function getmAh()
    local mAhSensor

    -- Debug: Check each sensor to see if it matches the required unit
    for member = 0, 25 do
        local candidate = system.getSource({category=CATEGORY_TELEMETRY_SENSOR, member=member})
        
        if candidate then
            if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                mAhSensor = candidate
                break -- Exit the loop once a valid mAh sensor is found
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
function batsell.create(widget)
    return
end


local matchingBatteries = {}
local formCreated = false
local selectedBattery

function batsell.build(widget)
    local w, h = lcd.getWindowSize()
    local pos_x 
    local pos_y
    
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
        -- So right now just using X18 numbers
        fieldHeight = 30
        fieldWidth = 100
    end

    -- Get the current Model ID
    sensor = system.getSource({category=CATEGORY_TELEMETRY, name="Model ID"})
    if sensor:value() ~= nil then
        modelID = math.floor(sensor:value())
    else
        return
    end

    matchingBatteries = {}
    if #Batteries > 0 and sensor:value() ~= nil then
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)

        for i = 1, #Batteries do
            if Batteries[i].modelID == modelID then
                matchingBatteries[#matchingBatteries + 1] = { Batteries[i].capacity .. "mAh", i }
            end
        end

        if useDebug.build then
            print("Debug(build): Current Model ID: " .. modelID .. ". Matching Batteries: " .. #matchingBatteries)
        end

        -- Create form and add choice field for selecting battery
        local choiceField
        form.create()
        
        -- Ensure selectedBattery is valid
        local isValid = false
        for _, battery in ipairs(matchingBatteries) do
            if battery[2] == selectedBattery then
                isValid = true
                break
            end
        end

        if not isValid then
            selectedBattery = matchingBatteries[1] and matchingBatteries[1][2] or 1
        end

        choiceField = form.addChoiceField(line, {x=pos_x, y=pos_y, w=fieldWidth, h=fieldHeight}, matchingBatteries, function() return selectedBattery end, function(value) selectedBattery = value end)
        
        -- Set the formCreated flag to true once it's created the first time
        formCreated = true
    end
end

function batsell.paint(widget)
    -- Idk if this is needed since I'm not drawing anything on the LCD but I'm leaving it here for now
end

local lastMillisUpdate = 0
local lastMillisBuild = 0

function batsell.wakeup(widget)
    local newmAh = getmAh()
    
    if numBatts > 0 and newmAh ~= nil then
        -- Ensure selectedBattery is valid
        if selectedBattery == nil or not Batteries[selectedBattery] then
            selectedBattery = 1
        end

        -- Detect if mAh sensor has changed since the last loop. If it has, update it and calculate new percentage.
        if currentmAh ~= newmAh then
            currentmAh = newmAh
            usablemAh = math.floor(Batteries[selectedBattery].capacity * (flyTo / 100))
            
            newPercent = 100 - math.floor((newmAh / usablemAh) * 100)
            if newPercent < 0 then
                newPercent = 0
            end
            
            -- If the new percentage is different from the current percentage, refresh widget
            if currentPercent ~= newPercent then
                currentPercent = newPercent
                lcd.invalidate()
            end
        end

        local millis = os.clock()
        if (millis - lastMillisUpdate) >= 1.0 then
            updateRemainingSensor(widget)
            lastMillisUpdate = millis
        end

        -- Check if the form has been built yet
        local sensor = system.getSource({category=CATEGORY_TELEMETRY, name="Model ID"})
        local currentModelID = sensor and sensor:value() and math.floor(sensor:value()) or nil

        if not formCreated then
            -- If not, build it as soon as sensor:value() is not nil
            if currentModelID ~= nil then
                batsell.build(widget)
                lastModelID = currentModelID
            end
        else
            -- Rebuild the form if the model ID has changed
            if currentModelID ~= lastModelID then
                batsell.build(widget)
                lastModelID = currentModelID
            end

            local previousMatchingBatteries = #matchingBatteries
            local newMatchingBatteries = 0
            for i = 1, #Batteries do
                if Batteries[i].modelID == currentModelID then
                    newMatchingBatteries = newMatchingBatteries + 1
                end
            end

            if newMatchingBatteries ~= previousMatchingBatteries then
                batsell.build(widget)
            end
        end
    end
end

-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
function batsell.configure(widget)
	doneConfigure = true

    -- Create Batteries expansion panel
    local batteryPane
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, widget)
   
    -- Create field for entering desired "fly-to" percentage (80% typical)
    if flyTo == nil then
        flyTo = 80
    end
    local line  = form.addLine("Use Capacity") 
    local field = form.addNumberField(line, nil, 50, 100, function() return flyTo end, function(value) flyTo = value end)
    field:suffix("%")
    field:default(80)

    -- Alerts Panel.  Commented out for now as not in use
    -- local alertsPanel
    -- alertsPanel = form.addExpansionPanel("Alerts")
    -- alertsPanel:open(false)
    -- fillAlertsPanel(alertsPanel, widget)
end

-- Read configuration from storage
function batsell.read(widget)
    numBatts = storage.read("numBatts")
    flyTo = storage.read("flyTo")
    Batteries = {}
    if numBatts ~= nil then
        for i = 1, numBatts do
            local capacity = storage.read("Battery" .. i .. "_capacity")
            local modelID = storage.read("Battery" .. i .. "_modelID")
            Batteries[i] = {capacity = capacity or 0, modelID = modelID or 0}
        end
    end
    selectedBattery = storage.read("selectedBattery")
end


-- Write configuration to storage
function batsell.write(widget)
    storage.write("numBatts", numBatts)
    storage.write("flyTo", flyTo)
    if numBatts ~= nil then
        for i = 1, numBatts do
            storage.write("Battery" .. i .. "_capacity", Batteries[i].capacity)
            storage.write("Battery" .. i .. "_modelID", Batteries[i].modelID)
        end
    end
    storage.write("selectedBattery", selectedBattery)
end

function batsell.event(widget, category, value, x, y) 
    
end

return batsell