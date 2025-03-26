-- layout.lua

local M = {}

-- Required libraries
local utils = require("lib.utils") -- Utility library

-- Local variables to store screen dimensions
local lineW, lineH


--- Computes the widths and positions of columns based on their ratios, total width, and margin.
--- This function calculates the width of each column and their starting x-positions.
--- Columns can have fixed ratios or a "flex-fill" ratio to occupy remaining space.
---
--- @param columns table A table of column definitions, where each column has a `ratio` field.
--- @param totalWidth number The total available width for all columns combined.
--- @param margin number The spacing (in pixels) between adjacent columns.
---
--- @return table widths A table containing the computed widths for each column.
--- @return table positions A table containing the computed starting x-positions for each column.
local function computeColumnPositions(columns, totalWidth, margin)
    local totalSpacing = margin * (#columns - 1) -- Total space occupied by margins
    local available = totalWidth - totalSpacing -- Remaining width after accounting for margins

    local widths = {}
    local positions = {}
    local fixedTotal = 0 -- Total width of fixed-ratio columns
    local flexIndex = nil -- Index of the "flex-fill" column, if any

    -- Calculate widths for fixed-ratio columns and identify the "flex-fill" column
    for i, col in ipairs(columns) do
        if col.ratio == "flex-fill" then
            flexIndex = i
        else
            widths[i] = math.floor(available * col.ratio)
            fixedTotal = fixedTotal + widths[i]
        end
    end

    -- Assign remaining width to the "flex-fill" column
    if flexIndex then
        widths[flexIndex] = math.floor(available - fixedTotal)
    end

    -- Calculate starting x-positions for each column
    local x = 0
    for i = 1, #columns do
        positions[i] = math.floor(x)
        x = x + widths[i] + margin
    end

    return widths, positions
end

--- Calculates the coordinates and dimensions of a field within a layout.
--- Determines the position and size of a field based on its column index, alignment, and other parameters.
---
--- @param colIndex number The index of the column where the field is located.
--- @param fieldType table|string|nil The type of the field, used to determine specific field behaviors.
--- @param columns number The total number of columns in the layout.
--- @param totalWidth number The total width of the layout container.
--- @param margin number The margin between columns in the layout.
--- @param fieldY number The Y-coordinate of the field.
--- @param fieldH number The height of the field.
--- @param align string|table|nil The alignment of the field (e.g., "left", "center", "right", or table-based anchors).
--- @param offset number|nil An optional offset applied to the X-coordinate of the field.
---
--- @return table coords A table containing the calculated coordinates and dimensions of the field.
local function getFieldCoords(colIndex, fieldType, columns, totalWidth, margin, fieldY, fieldH, align, offset)
    local widths, positions = computeColumnPositions(columns, totalWidth, margin)
    local coords = {
        x = positions[colIndex], -- X-coordinate of the field
        w = widths[colIndex],    -- Width of the field
        y = fieldY,              -- Y-coordinate of the field
        h = fieldH               -- Height of the field
    }

    local containerLeft = 0
    local containerRight = margin + totalWidth

    -- Handle specific field types (e.g., headers with content)
    if fieldType and type(fieldType) == "table" then
        local ft = fieldType[1]  -- Field type (e.g., "header")
        local content = fieldType[2]
        if ft == "header" and content then
            coords.w = lcd.getTextSize(content) -- Calculate text width

            -- Handle alignment relative to anchors
            if type(align) == "table" then
                if type(align[2]) == "string" then
                    local anchor = align[1]
                    local aType = align[2]
                    if aType == "center" then
                        coords.x = math.floor(anchor.x + (anchor.w / 2) - (coords.w / 2) + (offset or 0))
                    elseif aType == "left" then
                        coords.x = math.floor(anchor.x + (offset or 0))
                    elseif aType == "right" then
                        coords.x = math.floor(anchor.x + anchor.w - coords.w + (offset or 0))
                    end
                elseif type(align[2]) == "table" then
                    -- Centering between two anchors
                    local anchor1 = align[1]
                    local anchor2 = align[2]
                    local combinedX = math.min(anchor1.x, anchor2.x)
                    local combinedRight = math.max(anchor1.x + anchor1.w, anchor2.x + anchor2.w)
                    local combinedW = combinedRight - combinedX
                    coords.x = math.floor(combinedX + (combinedW / 2) - (coords.w / 2) + (offset or 0))
                end
            end
        end
    else
        -- Handle alignment for non-header fields
        if align == "absolute" then
            coords.x = math.floor(offset or coords.x)
        elseif type(align) == "string" then
            if align == "left" then
                coords.x = math.floor(containerLeft + (offset or 0))
            elseif align == "center" then
                local centerX = containerLeft + (totalWidth / 2)
                coords.x = math.floor(centerX - (coords.w / 2) + (offset or 0))
            elseif align == "right" then
                coords.x = math.floor((containerLeft + totalWidth) - coords.w + (offset or 0))
            end
        elseif type(align) == "table" then
            -- Alignment relative to anchors
            if type(align[2]) == "string" then
                local anchor = align[1]
                local aType = align[2]
                if aType == "left" then
                    coords.x = math.floor(anchor.x + (offset or 0))
                elseif aType == "center" then
                    coords.x = math.floor(anchor.x + (anchor.w / 2) - (coords.w / 2) + (offset or 0))
                elseif aType == "right" then
                    coords.x = math.floor(anchor.x + anchor.w - coords.w + (offset or 0))
                end
            elseif type(align[2]) == "table" then
                -- Centering between two anchors
                local anchor1 = align[1]
                local anchor2 = align[2]
                local combinedX = math.min(anchor1.x, anchor2.x)
                local combinedRight = math.max(anchor1.x + anchor1.w, anchor2.x + anchor2.w)
                local combinedW = combinedRight - combinedX
                coords.x = math.floor(combinedX + (combinedW / 2) - (coords.w / 2) + (offset or 0))
            end
        end
    end

    return coords
end

--- Generates the layout configuration for a specific section of the UI.
--- Calculates and returns the layout for a given section, such as "batteryPanel".
---
--- @param section string The section of the UI for which the layout is being generated.
--- @param reorderMode boolean Indicates whether the layout is in reorder mode or normal mode.
--- @return table|boolean A table containing the layout configuration or `false` if the section is unknown.
function M.getLayout(section, reorderMode)
    if not lineW or not lineH then
        lineW, lineH = lcd.getWindowSize() -- Get screen dimensions
    end

    local board = system.getVersion().board -- Get board type
    local margin, expansionPanelRightOffset

    -- Determine margin and offset based on board type
    if board == "X20" or board == "X20S" or board == "X20PRO" or board == "X20PROAW" or
       board == "X20R" or board == "X20RS" then
        margin = 8
        expansionPanelRightOffset = 30
    elseif board == "X18R" or board == "X18RS" then
        margin = 8
        expansionPanelRightOffset = 32
    elseif board == "X18" or board == "X18S" or board == "TWXLITE" or board == "TWXLITES" then
        margin = 4
        expansionPanelRightOffset = 18
    elseif board == "X14" or board == "X14S" then
        margin = 4
        expansionPanelRightOffset = 22
    else
        margin = 6
        expansionPanelRightOffset = 0
    end

    local fieldY = margin -- Initial Y-coordinate for fields
    local fieldH = lineH - (2 * margin) - 2 -- Field height
    local usableWidth = lineW - expansionPanelRightOffset -- Usable width for layout

    local layout = { field = {}, header = {}, button = {} }
    local columns = {}

    if section == "batteryPanel" then
        if reorderMode then
            -- Reorder mode: Define columns for fields and headers
            columns = {
                { name = "batName", ratio = "flex-fill" },
                { name = "batClone", ratio = 0.12 },
                { name = "batDel",   ratio = 0.12 },
                { name = "batUp",    ratio = 0.08 },
                { name = "batDown",  ratio = 0.08 },
            }
            -- Build field coordinates
            layout.field.batName  = getFieldCoords(1, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batClone = getFieldCoords(2, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batDel   = getFieldCoords(3, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batUp    = getFieldCoords(4, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batDown  = getFieldCoords(5, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)

            -- Build header coordinates
            layout.header.batName = getFieldCoords(1, { "header", "Name"}, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batName, "left" }, 0)
            layout.header.batMove = getFieldCoords(2, { "header", "Move"}, columns, usableWidth, margin, fieldY, fieldH, {layout.field.batUp, layout.field.batDown}, 0)
        else
            -- Normal mode: Define columns for fields and headers
            columns = {
                { name = "batName", ratio = "flex-fill" },
                { name = "batType", ratio = 0.16 },
                { name = "batCels", ratio = 0.06 },
                { name = "batCap",  ratio = 0.20 },
                { name = "batID",   ratio = 0.06 },
            }
            -- Build field coordinates
            layout.field.batName = getFieldCoords(1, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batType = getFieldCoords(2, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batCels = getFieldCoords(3, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batCap  = getFieldCoords(4, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batID   = getFieldCoords(5, nil, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)

            -- Build header coordinates
            layout.header.batName = getFieldCoords(1, { "header", "Name" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batName, "left" }, 0)
            layout.header.batType = getFieldCoords(2, { "header", "Type" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batType, "left" }, 0)
            layout.header.batCels = getFieldCoords(3, { "header", "Cells" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batCels, "center" }, 0)
            layout.header.batCap  = getFieldCoords(4, { "header", "Capacity" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batCap, "center" }, 0)
            layout.header.batID   = getFieldCoords(5, { "header", "ID" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batID, "center" }, 0)
        end

        -- Define button layout
        local buttonColumns = {
            { name = "batReorder", ratio = 0.25 },
            { name = "batAdd", ratio = 0.25 },
        }
        layout.button.batReorder = getFieldCoords(1, nil, buttonColumns, usableWidth, margin, fieldY, fieldH, "left", 0)
        layout.button.batAdd     = getFieldCoords(2, nil, buttonColumns, usableWidth, margin, fieldY, fieldH, "right", 0)
    else
        return false -- Unknown section
    end

    return layout
end

return M
