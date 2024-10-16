-- Lua Battery Selector and Alarm widget
-- Written by Keith Williams
batsell = {}

local choiceField
local sensor

-- Set to true to enable debug output
local useDebug = false

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
    end
    
    sensor:value(widget.Data.currentPercent)
end

local function getSensorValue()
   if sensor == nil then
        for member = 0, 25 do
            local candidate = system.getSource({category=CATEGORY_TELEMETRY_SENSOR, member=member})
            if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                sensor = candidate
                break -- Exit the loop once a valid mAh sensor is found
            end
        end
	else
		return sensor:value()
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
            ["selectedBattery"] = 1,
            ["DisplayPercent"] = true
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


function batsell.build(widget)
    local w, h = lcd.getWindowSize()
    
    -- Create string that contains the remaining percent value plus the % symbol
    local str_rp = tostring(widget.Data.currentPercent) .. "%"
    local tsizeW_rp
    local tsizeH_rp
    local cHeight = 40
    local offset = 0

    -- Create form, position based on widget size and whether display percent on widget is enabled
    if w >= 256 then
        -- Check if Display Percentage on Widget is enabled
        -- If it is:
        if widget.Config.DisplayPercent then
            lcd.font(FONT_XL)
            tsizeW_rp, tsizeH_rp = lcd.getTextSize(str_rp)
            pos_x = (w / 2)
            pos_y = (h / 2)
        else
        -- If it isn't:
            pos_x = (w / 2)
            pos_y = (h / 2 - 40 / 2)
        end
 
    else
        -- do nothing, widget box is too small for widget to fit
    end    

    if tsizeW_rp ~= nil then
        -- Create table for Battery Sizes to display in choice field
        local Batteries = {}
        for i = 1, widget.Config.numBatts do
            Batteries[i] = {widget.Batteries["Battery " .. i] .. "mAh", i }
        end

        form.create()
        choiceField = form.addChoiceField(line, {x=pos_x - tsizeW_rp, y=pos_y, w=75 * 2, h=cHeight}, Batteries, function() return widget.Config.selectedBattery end, function(value) 
            widget.Config.selectedBattery = value
            widget.Config.lastBattery = value
        end)
    end
end

function batsell.paint(widget)
    local w, h = lcd.getWindowSize()

    lcd.color(lcd.RGB(255,255,255))

	local tsizeW_pc, tsizeH_pc = lcd.getTextSize("% ") -- grabbing this as diff font size and need as offset for flight battery

    if widget.Data.currentPercent ~= nil then
        if widget.Config.DisplayPercent then
			if h >= 150 then	
				--display percent below selector
				lcd.font(FONT_XL)
				local str_p = widget.Data.currentPercent .. "%"
				local tsizeW_p, tsizeH_p = lcd.getTextSize(str_p)				
				lcd.drawText((w / 2) - tsizeW_p / 2, ((h / 2) - 40 / 2) + 40, str_p)  
				lcd.font(FONT_STD)					
			elseif h >= 100 and h < 150 then
				--display percent to side of selector
				lcd.font(FONT_L)
				local str_p = widget.Data.currentPercent .. "%"
				local tsizeW_p, tsizeH_p = lcd.getTextSize(str_p)				
				lcd.drawText(((w / 3) - tsizeW_p / 2) + tsizeW_p * 2 , ((h / 2) - tsizeH_p / 2), str_p)
				lcd.font(FONT_STD)				
			elseif h >= 65 and h < 100 then
				--display percent to side of selector
				lcd.font(FONT_L)
				local str_p = widget.Data.currentPercent .. "%"
				local tsizeW_p, tsizeH_p = lcd.getTextSize(str_p)				
				lcd.drawText(((w / 3) - tsizeW_p / 2) + tsizeW_p * 2 , ((h / 2) - tsizeH_p / 2), str_p)
				lcd.font(FONT_STD)				
			else
				-- dont show as will be to small
			end
		end
    end
end

function batsell.wakeup(widget)
    local newmAh = nil
    local newPercent = nil

    -- Check if Lua is running in a simulator.  
    local environment = system.getVersion()

    newmAh = getSensorValue()

    -- Detect if mAh sensor has changed since the last loop.  If it has, update it and calculate new percentage.
    if widget.Data.currentmAh ~= newmAh then
	
        widget.Data.currentmAh = newmAh

        usablemAh = math.floor(widget.Batteries["Battery " .. widget.Config.selectedBattery] * (widget.Config.flyTo / 100))
		
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

    -- Create field for displaying % on widget screen
    local displayPercent = nil
    local line = form.addLine("Display % On Widget")
    local field = form.addBooleanField(line, nil, function() return widget.Config.DisplayPercent end, function(value) widget.Config.DisplayPercent = value end)

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


