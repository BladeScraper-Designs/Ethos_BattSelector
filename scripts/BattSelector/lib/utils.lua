local M = {}


function M.printTable(t, mode, indent)
    mode = mode or "raw"
    indent = indent or ""
    
    if mode == "raw" then
        -- RAW mode: show braces and indentation
        print(indent .. "{")
        for k, v in pairs(t) do
            local key = tostring(k)
            if type(v) == "table" then
                print(indent .. "    " .. key .. " = ")
                M.printTable(v, "raw", indent .. "    ")
            else
                print(indent .. "    " .. key .. " = " .. tostring(v))
            end
        end
        print(indent .. "}")
    elseif mode == "pretty" then
        -- PRETTY mode: "Key: Value" lines
        for k, v in pairs(t) do
            local key = tostring(k)
            if type(v) == "table" then
                print(indent .. key .. ":")
                M.printTable(v, "pretty", indent .. "    ")
            else
                print(indent .. key .. ": " .. tostring(v))
            end
        end
    else
        print("Unknown mode '" .. tostring(mode) .. "', defaulting to raw.")
        M.printTable(t, "raw", indent)
    end
end  


--- Rounds a number to the specified number of decimal places.
-- @param num The number to be rounded.
-- @param numDecimalPlaces (optional) The number of decimal places to round to. Defaults to 0 if not provided.
-- @return The rounded number.
function M.round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end


function M.checkCompat(member)
    local rfSuiteRequired = {major = 2, minor = 2, revision = 0} -- Only required for extra features that utilize RFSuite tools and utilities like getSensorSource.
    local ethosRequired = {major = 1, minor = 6, revision = 2} -- Baseline requirement for latest script version and features.

    local rfSuiteVersion = {}
    local ethosVersion = {}

    local rfSuiteCompat = false
    local ethosCompat = false

    local member = member or ""

    if member == "" then
        print("No member specified for compatibility check.")
        return false
    end

    if member == "rfsuite" then
        if rfsuite and rfsuite.config.version then
            rfSuiteVersion = rfsuite.config.version
        else
            print("Unable to determine RFSuite version.")
            rfSuiteCompat = false
        end

        if rfSuiteVersion.major and rfSuiteVersion.minor and rfSuiteVersion.revision then
            rfSuiteCompat = rfSuiteVersion.major > rfSuiteRequired.major or
                            (rfSuiteVersion.major == rfSuiteRequired.major and rfSuiteVersion.minor > rfSuiteRequired.minor) or
                            (rfSuiteVersion.major == rfSuiteRequired.major and rfSuiteVersion.minor == rfSuiteRequired.minor and rfSuiteVersion.revision >= rfSuiteRequired.revision)
        end
        return rfSuiteCompat
    
    elseif member == "ethos" then   
        local ethos = system.getVersion().version
        if ethos then
            local versionParts = {}
            for part in ethos:gmatch("(%d+)") do
                table.insert(versionParts, tonumber(part))
            end
            ethosVersion = {
                major = versionParts[1],
                minor = versionParts[2],
                revision = versionParts[3]
            }

        else
            print("Unable to determine Ethos version.")
            ethosCompat = false
        end

        if ethosVersion.major and ethosVersion.minor and ethosVersion.revision then
            ethosCompat = ethosVersion.major > ethosRequired.major or
                        (ethosVersion.major == ethosRequired.major and ethosVersion.minor > ethosRequired.minor) or
                        (ethosVersion.major == ethosRequired.major and ethosVersion.minor == ethosRequired.minor and ethosVersion.revision >= ethosRequired.revision)
        end
        return ethosCompat
    end
end

function M.getSensor(name, unitFallback)
    print("[getSensor] Looking for sensor with name: " .. tostring(name) .. ", unitFallback: " .. tostring(unitFallback))

    if name == "Remaining" then
        print("[getSensor] Special-case lookup for Remaining sensor via appId/physId")
        local s = system.getSource({
            category = CATEGORY_TELEMETRY,
            appId    = 0x4402,
            physId   = 0x11
        })
        if s then
            print("[getSensor] Found Remaining via appId/physId: " .. tostring(s:name()))
            return s
        else
            print("[getSensor] appId/physId lookup failed for Remaining")
        end
    end

    -- Check if rfsuite version is compatible and if so, use its telemetry tools to get the sensor source
    if M.checkCompat("rfsuite") and rfsuite and rfsuite.tasks.active() then
        print("[getSensor] Using rfsuite telemetry tools to get sensor source.")
        local s = rfsuite.tasks.telemetry.getSensorSource(name)
        if s then
            print("[getSensor] Found sensor via rfsuite: " .. tostring(s:name()))
            return s
        else
            print("[getSensor] rfsuite did not find the sensor.")
        end
    else
        print("[getSensor] rfsuite not available or not compatible.")
    end

    -- if above failed, try by name
    print("[getSensor] Trying system.getSource by name.")
    local s = system.getSource({ category = CATEGORY_TELEMETRY, name = name })
    if s then
        print("[getSensor] Found sensor via system.getSource: " .. tostring(s:name()))
        return s
    else
        print("[getSensor] system.getSource did not find the sensor by name.")
    end

    -- full sensor scan if unitFallback provided.  It simply returns the first telemetry sensor that matches the unitFallback.
    if unitFallback then
        print("[getSensor] Scanning all telemetry sensors for unitFallback: " .. tostring(unitFallback))
        for member = 0, 50 do
            local c = system.getSource({ category = CATEGORY_TELEMETRY_SENSOR, member = member })
            if c and c:unit() == unitFallback then
                print("[getSensor] Found sensor by unitFallback: " .. tostring(c:name()))
                return c
            end
        end
        print("[getSensor] No sensor found with unitFallback: " .. tostring(unitFallback))
    end

    print("[getSensor] No sensor found. Returning nil.")
    return nil
end

--- Merges two tables into one.
-- @param t1 The first table.
-- @param t2 The second table.
-- @return A new table containing all key-value pairs from both tables.
function M.mergeTables(t1, t2)
    local result = {}
    for k, v in pairs(t1) do
        result[k] = v
    end
    for k, v in pairs(t2) do
        result[k] = v
    end
    return result
end

return M
