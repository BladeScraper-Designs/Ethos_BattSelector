-- Lua Battery Selector and Alarm widget
-- Written by Keith Williams

local translations = { en = "Battery Select" }

-- Enable debugging output.  Set to false for no debug
local debug = true

-- Debugging function.  Prints debug output to the console when debug = true
local function runDebug(section, widget, selectedBattery)
        -- Debugging for create function
    if section == "create" then
        print("Creating Widget")
        print("Applying Default Configuration Data")

        -- Debugging for build function
    elseif section == "build" then
        local w, h = lcd.getWindowSize()
        print("Building Widget. Size: " .. w .. "x" .. h .. "px")
        print("Selected Battery: " .. widget.Config.selectedBattery)
        -- Debugging for paint function
    elseif section == "paint" then
        print("Painting Widget")
        print("Current Consumed mAh Value: " .. widget.Data.currentmAh .. "mAh")
        print("Current Remaining Percent: " .. widget.Data.currentPercent .. "%")
        if newmAh ~= nil and newPercent ~= nil then
            print("New Consumed mAh Value: " .. newmAh .. "mAh")
            print("New Remaining Percentage: " .. newPercent .. "%")
        end
        -- Debugging for configure function
    elseif section == "configure" then
        print("Run Configuration")

        -- Debugging for wakeup function
    elseif section == "wakeup" then
        print("wakeup")

        -- Debugging for read and write functions
    elseif section == "storage" then
        print("Number of Batteries: " .. widget.Config.numBatts)
        print("Fly To Percentage: " .. widget.Config.flyTo .. "%")
        print(widget.Config.mAhSensor)
        if widget.Config.defaultBattery < widget.Config.numBatts + 1 then
            print("Default Battery: " .. widget.Config.defaultBattery)
        elseif widget.Config.defaultBattery == widget.Config.numBatts + 1 then
            print("Default Battery: Last Used")
            print("Last Battery: " .. widget.Config.lastBattery)
        end
        print("Selected Battery: " .. widget.Config.selectedBattery)
        for i = 1, widget.Config.numBatts do
            print("Battery Size " .. i .. ": " .. widget.Batteries["Battery " .. i])
        end
        print("")
    end
end

-- Determine region and Widget name (EN translation only for now)
local function name()
    local locale = system.getLocale()
    return translations[locale] or translations["en"]
end

-- This function is called when the widget is first created and returns the default configuration data
local function create(widget)
    if debug then
        runDebug("create", widget)
    end

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
            ["Battery 1"] = 0,
            ["Battery 2"] = 0
        },
        
        Data = {
            ["currentmAh"] = nil,
            ["currentPercent"] = nil
        }
    }
end

local function build(widget)
    local Batteries = {}
    -- Create table for possible Battery Sizes
    for i = 1, widget.Config.numBatts do
        Batteries[i] = {widget.Batteries["Battery " .. i] .. "mAh", i }
    end
    -- Get Widget size  
    local w, h = lcd.getWindowSize()

    -- Currently the only size available.  Default screen right side widget.
    if w == 256 and h == 100 then
        form.create()
        form.addStaticText(line, {x=15, y=10, w=150, h=40}, "Flight Battery")
        form.addChoiceField(line, {x=5, y=45, w=150, h=40}, Batteries, function() return widget.Config.selectedBattery end, function(value) 
        widget.Config.selectedBattery = value
        widget.Config.lastBattery = value
        end)
    else
        print("Unsupported Widget Size")
        form.create()
        form.addStaticText(line, {x=0, y = (h/2) - 20, w=300, h=40}, "Unsupported Widget Size")
    end

    if debug then
        runDebug("build", widget)
    end
end

local function updateRemainingSensor(widget)
    local sensor = system.getSource({category=CATEGORY_TELEMETRY, appId=0x4402})
    if sensor == nil then
        -- if sensor does not already exist, make it
    sensor = model.createSensor()
    if sensor == nil then
        return -- in case there is no room for an extra sensor!
    end
    sensor:name("Remaining")
    sensor:unit(UNIT_PERCENT)
    sensor:decimals(0)
    sensor:appId(0x4402)
    sensor:physId(0x10)
    print("Percent Sensor created")
        print(sensor)
    end
    sensor:value(widget.Data.currentPercent)
end

local function paint(widget)
    local w, h = lcd.getWindowSize()
    local text_w, text_h = lcd.getTextSize("")
    lcd.font(FONT_XL)
    lcd.color(lcd.RGB(255,255,255))

    if widget.Data.currentPercent ~= nil then
        lcd.drawText(165, 35, widget.Data.currentPercent .. "%")
    end
    
    if debug then
        runDebug("paint", widget)
    end
end

local function wakeup(widget)
    -- Check if Lua is running in a simulator.  If it is, set newmAh to 1000 for math testing purposes.
    local environment = system.getVersion()
    local newmAh = nil
    local newPercent = nil

    if environment.simulation then 
        newmAh = 1000
    else -- Otherwise, get mAh value from configured mAh sensor
        local sensor = system.getSource("ESC Consumption")
        if sensor ~= nil then
            newmAh = sensor:value()
        end
    end

    -- Detect if mAh sensor has changed since the last loop.  If it has, update it and calculate new percentage.
    if widget.Data.currentmAh ~= newmAh then
        widget.Data.currentmAh = newmAh
        usablemAh = math.floor(widget.Batteries["Battery " .. widget.Config.selectedBattery] * (widget.Config.flyTo / 100))
        newPercent = 100 - math.floor((newmAh / usablemAh) * 100)
            if newPercent < 0 then
                newPercent = 0
            end
        
        -- If mAh sensor has changed, update the % Remaining Sensor too
        if widget.Data.currentPercent ~= newPercent then
            widget.Data.currentPercent = newPercent
            lcd.invalidate()
        end

        -- Run debug if enabled
        if debug then
            runDebug("wakeup", widget)
        end
    end

    -- Recheck and update % Remaining Sensor every 0.5s
    local millis = os.clock()
    if (millis - (widget.lastMillis or 0)) >= 1.0 then
        updateRemainingSensor(widget)
        widget.lastMillis = millis
        print("Updating % Remaining Sensor")
    end
end


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

-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure(widget)
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

    -- Create field for selecting mAh sensor to be used for percent calculations
    local line = form.addLine("mAh Source Sensor")
    form.addSensorField(line, nil, function() return widget.Config.mAhSensor end, function(newValue) widget.Config.mAhSensor = newValue end, function(candidate) return candidate:unit() == UNIT_MILLIAMPERE_HOUR end)
    
    -- Create field for entering desired "fly-to" percentage (80% typical)
    local line  = form.addLine("Use Capacity") 
    local field = form.addNumberField(line, nil, 50, 100, function() return widget.Config.flyTo end, function(value) widget.Config.flyTo = value end)
    field:suffix("%")
    field:default(80)
    
    if debug then
        runDebug("configure", widget, defaultOptions)
    end
end

-- Read configuration from storage
local function read(widget)
    widget.Config.numBatts = storage.read("numBatts")
    widget.Config.flyTo = storage.read("flyTo")
    for i = 1, widget.Config.numBatts do
        widget.Batteries["Battery " .. i] = storage.read("Battery" .. i)
    end
    widget.Config.mAhSensor = storage.read("mAhSensor")
    widget.Config.defaultBattery = storage.read("defaultBattery")
    widget.Config.lastBattery = storage.read("lastBattery")
    if widget.Config.defaultBattery == widget.Config.numBatts + 1 then
        widget.Config.selectedBattery = storage.read("lastBattery")
    else
        widget.Config.selectedBattery = widget.Config.defaultBattery 
    end

    -- config read debug output if enabled
    if debug then 
        print("")
        print("Reading Configuration")
        runDebug("storage", widget)
    end
end

-- Write configuration to storage
local function write(widget)
    storage.write("numBatts", widget.Config.numBatts)
    storage.write("flyTo", widget.Config.flyTo)
    for i = 1, widget.Config.numBatts do
        if widget.Batteries["Battery " .. i] == nil then
            widget.Batteries["Battery " .. i] = 0
        end
        storage.write("Battery" .. i, widget.Batteries["Battery " .. i])
    end

    storage.write("mAhSensor", widget.Config.mAhSensor)
    storage.write("defaultBattery", widget.Config.defaultBattery)
    storage.write("lastBattery", widget.Config.lastBattery)
    storage.write("selectedBattery", widget.Config.selectedBattery)
    -- config write debug output if enabled
    if debug then 
        print("")
        print("Writing Configuration")
        runDebug("storage", widget)
    end
end

local function init()
    system.registerWidget({
        key="battsel", 
        name=name, 
        create=create, 
        build=build,
        paint=paint, 
        wakeup=wakeup,
        configure=configure, 
        read=read, 
        write=write, 
        title=false,
        runDebug=runDebug
    })
end

return {init=init}  