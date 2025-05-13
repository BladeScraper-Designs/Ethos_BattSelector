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
