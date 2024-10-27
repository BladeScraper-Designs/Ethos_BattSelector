-- Lua Battery Selector and Alarm widget
-- Written by Keith Williams
batsell = {}

local choiceField
local sensor

-- Set to true to enable debug output for each function
local useDebug = {
    fillBatteryPanel = false,
    updateRemainingSensor = false,
    getSensorValue = false,
    create = false,
    build = false,
    paint = false,
    wakeup = false,
    configure = false
}


-- local functions
local function fillBatteryPanel(batteryPanel, widget)
    -- Create a line for each Battery Size 
    for i = 1, widget.Config.numBatts do
        local line = batteryPanel:addLine("Battery " .. i)
        local field = form.addNumberField(line, nil, 0, 20000, function() return widget.Batteries["Battery " .. i] end, function(value) widget.Batteries["Battery " .. i] = value end)
        field:suffix("mAh")
        field:default(0)
        field:step(100)
    end

    -- Create table for Default Battery Options and add Last Used as an option
    local defaultOptions = {}
    for i = 1, widget.Config.numBatts do
        defaultOptions[i] = { "Battery " .. i, i }
    end
    -- Add Last Used as an option
    defaultOptions[widget.Config.numBatts + 1] = { "Last Used", widget.Config.numBatts + 1 }
    local line = batteryPanel:addLine("Default")
    local field = form.addChoiceField(line, nil,  defaultOptions, function() return widget.Config.defaultBattery end, function(value) widget.Config.defaultBattery = value end)

    -- If you reduce the nunber of batteries by more than 1 (e.g. from 3 to 1), the configured default battery may be invalid.
    -- This sets the default to last used (numBatts + 1) if so to prevent that.
    if widget.Config.defaultBattery > widget.Config.numBatts + 1 then
        widget.Config.defaultBattery = widget.Config.numBatts + 1
    end
end


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
    sensor:value(widget.Data.currentPercent)

    if useDebug.updateRemainingSensor then
        if sensor:value() ~= nil then
            print("Debug(updateRemainingSensor): Remaining: " .. sensor:value() .. "%")
        end
    end
end


local function getSensorValue()
    if sensor == nil then
        for member = 0, 25 do
            local candidate = system.getSource({category=CATEGORY_TELEMETRY_SENSOR, member=member})
            if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                sensor = candidate
                if useDebug.getSensorValue then
                    print("mAh Sensor Found: " .. (tostring(sensor)))
                end
                break -- Exit the loop once a valid mAh sensor is found
            end
        end
	else
        if sensor:value() ~= nil then
            if useDebug.getSensorValue then
                if sensor:value() ~= nil then
                print("Debug(getSensorValue): mAh Reading: " .. math.floor(sensor:value()) .. "mAh")
                end
            end
		    return math.floor(sensor:value())
        else
            return 0
        end
    end
end


-- This function is called when the widget is first created and returns the default configuration data
function batsell.create(widget)

    return {
        Config = { -- Set Default Configuration Data
            ["numBatts"] = 2, 
            ["flyTo"] = 80, 
            ["mAhSensor"] = nil,
            ["defaultBattery"] = 3,
            ["lastBattery"] = 1,
            ["selectedBattery"] = 1
        },

        Batteries = { -- Set mAh Values for Default Batteries
            ["Battery 1"] = 4000,
            ["Battery 2"] = 5000
        },
        
        Data = {
            ["currentmAh"] = nil,
            ["currentPercent"] = nil
        }
    }
end


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

    if widget.Config.numBatts > 0 then
        local pos_x = (w / 2 - fieldWidth / 2)
        local pos_y = (h / 2 - fieldHeight / 2)

        -- Create table for Battery Sizes to display in choice field
        local Batteries = {}
        for i = 1, widget.Config.numBatts do
            Batteries[i] = {widget.Batteries["Battery " .. i] .. "mAh", i }
        end
            -- Create form and add choice field for selecting battery
        form.create()
        choiceField = form.addChoiceField(line, {x=pos_x, y=pos_y, w=fieldWidth, h=fieldHeight}, Batteries, function() return widget.Config.selectedBattery end, function(value) 
        widget.Config.selectedBattery = value
        widget.Config.lastBattery = value
        end)
    end
end

function batsell.paint(widget)
    -- Idk if this is needed since I'm not drawing anything on the LCD but I'm leaving it here for now
end

function batsell.wakeup(widget)
    local newmAh = nil
    local newPercent = nil
    local newmAh = getSensorValue()

    -- Detect if mAh sensor has changed since the last loop.  If it has, update it and calculate new percentage.
    if widget.Data.currentmAh ~= newmAh then
	
        widget.Data.currentmAh = newmAh

        usablemAh = math.floor(widget.Batteries["Battery " .. tonumber(widget.Config.selectedBattery)] * (widget.Config.flyTo / 100))
		
        newPercent = 100 - math.floor((newmAh / usablemAh) * 100)
            if newPercent < 0 then
                newPercent = 0
            end
        
        -- If the new percentage is different from the current percentage, refresh widget
        if widget.Data.currentPercent ~= newPercent then
            widget.Data.currentPercent = newPercent
            lcd.invalidate()
        end

    end

    -- Recheck and update % Remaining Sensor every 1s
    local millis = os.clock()
    if (millis - (widget.lastMillis or 0)) >= 1.0 then
        updateRemainingSensor(widget)
        widget.lastMillis = millis
    end
end

-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
function batsell.configure(widget)


	doneConfigure = true
    -- Create field for choosing the number of batteries
    local line = form.addLine("Number of Batteries")
    local batteryPanel
    local field = form.addNumberField(line, nil, 1, 5, function() return widget.Config.numBatts end, function(value)
        widget.Config.numBatts = value
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, widget)
    end)

    -- Create Batteries expansion panel
    batteryPanel = form.addExpansionPanel("Batteries")
    batteryPanel:open(false)
    fillBatteryPanel(batteryPanel, widget)
   
    -- Create field for entering desired "fly-to" percentage (80% typical)
    local line  = form.addLine("Use Capacity") 
    local field = form.addNumberField(line, nil, 50, 100, function() return widget.Config.flyTo end, function(value) widget.Config.flyTo = value end)
    field:suffix("%")
    field:default(80)
end

-- Read configuration from storage
function batsell.read(widget)

    widget.Config.numBatts = storage.read("numBatts")
	if widget.Config.numBatts == nil then
		widget.Config.numBatts = 2
	end
	
    widget.Config.flyTo = storage.read("flyTo")
	if widget.Config.flyTo == nil then
		widget.Config.flyTo = 80
	end
	
    for i = 1, widget.Config.numBatts do
        widget.Batteries["Battery " .. i] = storage.read("Battery" .. i)
    end

    widget.Config.defaultBattery = storage.read("defaultBattery")
	if widget.Config.defaultBattery == nil then
		widget.Config.defaultBattery = 1
	end
	
    widget.Config.lastBattery = storage.read("lastBattery")
	if widget.Config.lastBattery == nil then
		widget.Config.lastBattery = 1
	end	
	
	
    if widget.Config.defaultBattery == widget.Config.numBatts + 1 then
        widget.Config.selectedBattery = storage.read("lastBattery")
		if widget.Config.selectedBattery == nil then
			widget.Config.selectedBattery = 1
		end
    else
        widget.Config.selectedBattery = widget.Config.defaultBattery 
    end
    widget.Config.DisplayPercent = storage.read("DisplayPercent")

end

-- Write configuration to storage
function batsell.write(widget)
    storage.write("numBatts", widget.Config.numBatts)
    storage.write("flyTo", widget.Config.flyTo)
    for i = 1, widget.Config.numBatts do
        if widget.Batteries["Battery " .. i] == nil then
            widget.Batteries["Battery " .. i] = 0
        end
        storage.write("Battery" .. i, widget.Batteries["Battery " .. i])
    end
    storage.write("defaultBattery", widget.Config.defaultBattery)
    storage.write("lastBattery", widget.Config.lastBattery)
    storage.write("selectedBattery", widget.Config.selectedBattery)
    storage.write("DisplayPercent", widget.Config.DisplayPercent)
end

function batsell.event(widget, category, value, x, y)

end

return batsell


