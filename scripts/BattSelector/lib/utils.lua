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
          print(indent .. "  " .. key .. " = ")
          M.printTable(v, "raw", indent .. "  ")
        else
          print(indent .. "  " .. key .. " = " .. tostring(v))
        end
      end
      print(indent .. "}")
    elseif mode == "pretty" then
      -- PRETTY mode: "Key: Value" lines
      for k, v in pairs(t) do
        local key = tostring(k)
        if type(v) == "table" then
          print(indent .. key .. ":")
          M.printTable(v, "pretty", indent .. "  ")
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