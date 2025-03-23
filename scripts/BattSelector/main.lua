-- Lua Battery Selector and Alarm widget

-- Include json library for read/write of config and battery data
local json = require("lib.dkjson")

-- Predeclare read and write functions to allow calling them before definition
local read  -- Function to load configuration and battery data from JSON
local write -- Function to save configuration and battery data to JSON
local configLoaded = false  -- Flag to indicate if the configuration has been loaded yet

-- Set to true to enable debug output for each function as needed
local useDebug = {
    getLayout = true,
    fillFavoritesPanel = false,
    fillImagePanel = false,
    fillBatteryPanel = true,
    fillPrefsPanel = false,
    doBatteryVoltageCheck = false,
    updateRemainingSensor = false,
    getmAh = false,
    create = true,
    build = false,
    read = false,
    write = false,
    paint = false,
    wakeup = false,
    configure = false
}

-- Print table function for debugging tables
local function printTable(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        local key = tostring(k)
        if type(v) == "table" then
            print(indent .. key .. " = {")
            printTable(v, indent .. "  ")
            print(indent .. "}")
        else
            print(indent .. key .. " = " .. tostring(v))
        end
    end
end

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

local lineW, lineH

local function getLayout(reorderMode)
    local debug = useDebug.getLayout
    if not lineW or not lineH then
        lineW, lineH = lcd.getWindowSize()
    end
    local board = system.getVersion().board

    --------------------------------------------------
    -- 1) margin & offset per board
    --------------------------------------------------
    local margin, expansionPanelRightOffset
    if board == "X20" or board == "X20S" or board == "X20PRO" or board == "X20PROAW"
       or board == "X20R" or board == "X20RS" then
        margin = 8
        expansionPanelRightOffset = 32
    elseif board == "X18R" or board == "X18RS" then
        margin = 8
        expansionPanelRightOffset = 32
    elseif board == "X18" or board == "X18S"
       or board == "TWXLITE" or board == "TWXLITES" then
        margin = 4
        expansionPanelRightOffset = 18
    elseif board == "X14" or board == "X14S" then
        margin = 4
        expansionPanelRightOffset = 22
    else
        margin = 6
        expansionPanelRightOffset = 0
        if debug then print("Unsupported board: " .. board) end
    end

    local maxRight = lineW - expansionPanelRightOffset
    local usableWidth = maxRight - margin

    local fieldH = lineH - (2 * margin) - 2
    local fieldY = margin

    --------------------------------------------------
    -- 2) Define columns based on reorderMode
    --------------------------------------------------
    local columns
    if reorderMode then
        -- REORDER columns
        columns = {
            { name="batName",   ratio=0.47 }, -- Name field
            { name="batDelete", ratio=0.15 }, -- "Delete" button
            { name="batClone",  ratio=0.15 }, -- "Clone" button
            { name="batUp",     ratio=0.08 }, -- "Up" button
            { name="batDown",   ratio=0.08 }, -- "Down" button
        }
    else
        -- NORMAL columns
        columns = {
            { name="batName", ratio=0.47 },  -- Name
            { name="batType", ratio=0.13 },  -- Type
            { name="batCels", ratio=0.07 },  -- Cells
            { name="batCap",  ratio=0.16 },  -- Capacity
            { name="batId",   ratio=0.05 },  -- ID
        }
    end

    local ratioSum = 0
    for _, col in ipairs(columns) do
        ratioSum = ratioSum + col.ratio
    end
    local nCols = #columns
    local totalColSpacing = (nCols - 1) * margin
    local availableForCols = usableWidth - totalColSpacing

    --------------------------------------------------
    -- 3) Compute each column’s width
    --------------------------------------------------
    local colWidth = {}
    local totalW = 0
    for _, col in ipairs(columns) do
        local w = math.floor((col.ratio / ratioSum) * availableForCols)
        colWidth[col.name] = w
        totalW = totalW + w
    end

    -- leftover => adjust the first column (batName)
    local leftover = availableForCols - totalW
    if leftover ~= 0 and colWidth["batName"] then
        colWidth["batName"] = colWidth["batName"] + leftover
        if colWidth["batName"] < 1 then
            colWidth["batName"] = 1
        end
    end

    --------------------------------------------------
    -- 4) Assign x positions in one pass
    --------------------------------------------------
    local layout = {
        margin = margin,
        fieldH = fieldH,
        fieldY = fieldY,
        field  = {},
        header = {},
        button = {},
    }

    local x = margin
    for i, col in ipairs(columns) do
        layout.field[col.name] = {
            x = x,
            y = fieldY,
            w = colWidth[col.name],
            h = fieldH
        }
        x = x + colWidth[col.name]
        if i < nCols then
            x = x + margin
        end
    end

    -- Helper function to align header text to an anchor rect (usually an existing field)
    local function alignField(label, alignment, anchorRect, padding, offset)
        padding = padding or 0
        local textW = lcd.getTextSize(label)
        local totalW = textW + 2 * padding
        local rect = {}
        
        if anchorRect then
          if alignment == "center" then
            rect.x = anchorRect.x + math.floor((anchorRect.w - totalW) / 2)
          elseif alignment == "right" then
            rect.x = anchorRect.x + anchorRect.w - totalW
          else  -- left alignment
            rect.x = anchorRect.x
          end
          rect.y = anchorRect.y
        else
          if alignment == "right" then
            offset = offset or (margin * 4)
            rect.x = lineW - totalW - offset
          elseif alignment == "center" then
            rect.x = margin + math.floor((lineW - 2 * margin - totalW) / 2)
          else
            rect.x = margin
          end
          rect.y = fieldY
        end
        
        rect.w = totalW
        rect.h = fieldH
        return rect
      end      

    -- 
    layout.header.batName = alignField("Name", "left",   layout.field.batName, 2)
    layout.header.batType = alignField("Type", "left", layout.field.batType, 2)
    layout.header.batCels = alignField("Cells", "center", layout.field.batCels, 2)
    layout.header.batCap  = alignField("Capacity", "center", layout.field.batCap, 2)
    layout.header.batId   = alignField("ID", "center",   layout.field.batId, 2)

    --------------------------------------------------
    -- 6) Buttons alignment stays the same
    --------------------------------------------------
    local function alignForButton(label, alignment)
        local textW = lcd.getTextSize(label)
        local sidePadding = 10
        local rectW = textW + (2 * sidePadding)
        local rect = { y = fieldY, w = rectW, h = fieldH }

        if alignment == "right" then
            rect.x = maxRight - rectW
        else
            rect.x = margin
        end
        return rect
    end

    layout.button.batReorder = alignForButton("Reorder/Edit", "left")
    layout.button.batAdd     = alignForButton("Add New",      "right")

    return layout
end

local reorderMode = false

local function fillBatteryPanel(batteryPanel, widget)
    -- Debug if enabled
    local debug = useDebug.fillBatteryPanel
    if debug then print("Debug(fillBatteryPanel): Filling Battery Panel") end

    -- Get the layout
    local layout = getLayout(reorderMode)
    print("Layout:")
    printTable(layout.field)
    -- if debug then printTable(layout) end

    -- Header text positions for reorder mode
    local pos_header_move = {x = 665, y = layout.margin, w = 100, h = layout.fieldH}

    -- Create header for the battery panel
    local line = batteryPanel:addLine("")
    form.addStaticText(line, layout.header.batName, "Name")
    if not reorderMode then
        form.addStaticText(line, layout.header.batType, "Type")
        form.addStaticText(line, layout.header.batCels, "Cells")
        form.addStaticText(line, layout.header.batCap, "Capacity")
        form.addStaticText(line, layout.header.batId, "ID")
    else
        form.addStaticText(line, pos_header_move, "Move")
    end

    for i = 1, numBatts do
        local line = batteryPanel:addLine("")
        local field = form.addTextField(line, layout.field.batName, function() return Batteries[i].name end, function(newName)
            Batteries[i].name = newName
            rebuildWidget = true
        end)

        if not reorderMode then
            local field = form.addChoiceField(line, layout.field.batType, {{"LiPo", 1},{ "LiHV", 2}}, function() return Batteries[i].type end, function(value) 
                Batteries[i].type = value
            end)

            local field = form.addNumberField(line, layout.field.batCels, 1, 16, function() return Batteries[i].cells end, function(value)
                Batteries[i].cells = value
                rebuildWidget = true
            end)

            local field = form.addNumberField(line, layout.field.batCap, 0, 20000, function() return Batteries[i].capacity end, function(value)
                Batteries[i].capacity = value
                rebuildWidget = true
            end)
            field:suffix("mAh")
            field:step(100)
            field:default(0)
            field:enableInstantChange(false)
            local field = form.addNumberField(line, layout.field.batId , 0, 99, function() return Batteries[i].modelID end, function(value)
                Batteries[i].modelID = value
                favoritesPanel:clear()
                fillFavoritesPanel(favoritesPanel, widget)
                imagePanel:clear()
                fillImagePanel(imagePanel, widget)
                rebuildWidget = true
            end)
            field:default(0)
            field:enableInstantChange(false)

        else
            local deleteButton = form.addTextButton(line, layout.field.batDelete, "Delete", function()
                table.remove(Batteries, i)
                numBatts = numBatts - 1
                batteryPanel:clear()
                fillBatteryPanel(batteryPanel, widget)
                return true
            end)
            local cloneButton = form.addTextButton(line, layout.field.batClone, "Clone", function()
                numBatts = numBatts + 1
                Batteries[numBatts] = {name = Batteries[i].name .. " (Copy)", capacity = Batteries[i].capacity, modelID = Batteries[i].modelID}
                batteryPanel:clear()
                fillBatteryPanel(batteryPanel, widget)
                return true
            end)
            -- Add Up/Down buttons in reorder mode
            if i > 1 then
                local upButton = form.addTextButton(line, layout.field.batUp, "↑", function()
                    Batteries[i], Batteries[i-1] = Batteries[i-1], Batteries[i]
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel, widget)
                    return true
                end)
            end
            if i < numBatts then
                local downButton = form.addTextButton(line, layout.field.batDown, "↓", function()
                    Batteries[i], Batteries[i+1] = Batteries[i+1], Batteries[i]
                    batteryPanel:clear()
                    fillBatteryPanel(batteryPanel, widget)
                    return true
                end)
            end
        end
    end

    local line = batteryPanel:addLine("")
    local field = form.addTextButton(line, layout.button.batReorder, reorderMode and "Done" or "Reorder/Edit", function()
        reorderMode = not reorderMode
        batteryPanel:clear()
        fillBatteryPanel(batteryPanel, widget)
    end)
    
    local field = form.addTextButton(line, layout.button.batAdd, "Add New", function()
        numBatts = numBatts + 1
        Batteries[numBatts] = {name = "Battery " .. numBatts, type = 1, cells = 6, capacity = 0, modelID = 0}
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
        local line = prefsPanel:addLine("Min Charged Volt/Cell")
        local field = form.addNumberField(line, nil, 400, 430, function() return minChargedCellVoltage or 415 end, function(value) minChargedCellVoltage = value end)
        field:decimals(2)
        field:suffix("V")
        field:enableInstantChange(false)
        local line = prefsPanel:addLine("Haptic Warning")
        local field = form.addBooleanField(line, nil, function() return doHaptic end, function(newValue) doHaptic = newValue rebuildPrefs = true end)
        if doHaptic then 
            local line = prefsPanel:addLine("Haptic Pattern")
            local field = form.addChoiceField(line, nil, hapticPatterns, function() return hapticPattern or 1 end, function(newValue) hapticPattern = newValue end)
        end
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
    read()
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
        
        if radio.board == "X18" or radio.board == "X18S" then
            fieldHeight = 30
        else
            fieldHeight = 40
        end

        local padding = 10
        fieldWidth, _ = lcd.getWindowSize()
        fieldWidth = fieldWidth - padding * 2

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

    -- Check if the modelID has changed since last wakeup, and if so, set the rebuildWidgetflag to true
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
    if not configLoaded then
        read()
        configLoaded = true
    end
    
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
read = function ()
    configLoaded = false  -- Reset the configLoaded flag to false before reading
    local debug = useDebug.read  

    local configFileName = "config.json"
    local batteriesFileName = "batteries.json"

    if debug then print("Debug(read): Starting read()") end

    -- Read config.json
    local configData = {}
    local content = readFileContent(configFileName)
    if content and content ~= "" then
        configData = json.decode(content) or {}
        if debug then print("Debug(read): Successfully decoded config data.") end
    else
        if debug then print("Debug(read): Config file not found or empty, using defaults.") end
    end

    -- Check versioning for config
    if not configData.version then
        if debug then print("Debug(read): No version detected in config.json, assuming version 1.") end
        configData.version = 1  -- Assume version 1 for old formats
    end

    -- Set config variables with defaults
    numBatts = configData.numBatts or 0
    useCapacity = configData.useCapacity or 80
    checkBatteryVoltageOnConnect = configData.checkBatteryVoltageOnConnect or false
    minChargedCellVoltage = configData.minChargedCellVoltage or 415
    doHaptic = configData.doHaptic or false
    hapticPattern = configData.hapticPattern or 1
    modelImageSwitching = configData.modelImageSwitching or false
    Images = configData.Images or {}

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

    -- Read batteries.json
    local content2 = readFileContent(batteriesFileName)
    if content2 and content2 ~= "" then
        local decoded = json.decode(content2)
        if decoded then
            if decoded.version and decoded.batteries then
                -- New format
                Batteries = decoded.batteries
                if debug then print("Debug(read): Versioned battery format detected (v" .. decoded.version .. ")") end
            elseif type(decoded) == "table" and #decoded > 0 and decoded[1].name then
                -- Old format (plain array)
                Batteries = decoded
                if debug then print("Debug(read): Legacy battery format detected, assuming version 1.") end
            else
                if debug then print("Debug(read): Unknown structure in batteries.json, using empty.") end
                Batteries = {}
            end
        else
            if debug then print("Debug(read): Failed to decode batteries.json!") end
            Batteries = {}
        end
    else
        Batteries = {}  -- File not found or empty
        if debug then print("Debug(read): batteries.json not found or empty.") end
    end

    -- Debug battery output
    if debug then
        print("Debug(read): Batteries list:")
        for i, battery in ipairs(Batteries) do
            print(string.format("  Battery %d:", i))
            print(string.format("    Name: %s", battery.name or "N/A"))
            print(string.format("    Type: %s", battery.type or "N/A"))
            print(string.format("    Cells: %d", battery.cells or 0))
            print(string.format("    Capacity: %d mAh", battery.capacity or 0))
            print(string.format("    Model ID: %s", tostring(battery.modelID or "N/A")))
            print(string.format("    Favorite: %s", battery.favorite and "Yes" or "No"))
        end
    end

    if debug then print("Debug(read): Finished read()") end
end

write = function ()
    local debug = useDebug.write  
    local configFileName = "config.json"
    local batteriesFileName = "batteries.json"

    -- Gather config data
    local configData = {
        version = 1,  -- Ensure future compatibility
        numBatts = numBatts,
        useCapacity = useCapacity,
        checkBatteryVoltageOnConnect = checkBatteryVoltageOnConnect,
        minChargedCellVoltage = minChargedCellVoltage,
        doHaptic = doHaptic,
        hapticPattern = hapticPattern,
        modelImageSwitching = modelImageSwitching,
        Images = Images
    }

    -- Gather battery data in a versioned structure
    local batteryData = {
        version = 1,  -- Ensure future compatibility
        batteries = Batteries
    }

    -- Serialize tables
    local jsonConfig = json.encode(configData, { indent = "  " })
    local jsonBatteries = json.encode(batteryData, { indent = "  " })

    -- Write config.json
    local file = io.open(configFileName, "w")
    if file then
        file:write(jsonConfig)
        file:close()
        if debug then print("Debug(write): Config data written to " .. configFileName) end
    else
        if debug then print("Debug(write): Error: Unable to open " .. configFileName .. " for writing.") end
    end

    -- Write batteries.json
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
