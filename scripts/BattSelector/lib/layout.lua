-- layout.lua
local M = {}

local lineW, lineH

-- Helper: compute widths and x positions for an array of columns.
-- Each column has a 'ratio' field. If ratio is "flex-fill", that column
-- gets the remaining space after fixed columns are allocated.
local function computeColumnPositions(columns, totalWidth, margin)
    local totalSpacing = margin * (#columns - 1)
    local available = totalWidth - totalSpacing

    local widths = {}
    local positions = {}
    local fixedTotal = 0
    local flexIndex = nil

    for i, col in ipairs(columns) do
        if col.ratio == "flex-fill" then
            flexIndex = i
        else
            widths[i] = math.floor( available * col.ratio )
            fixedTotal = fixedTotal + widths[i]
        end
    end

    if flexIndex then
        widths[flexIndex] = math.floor( available - fixedTotal )
    end

    local x = margin
    for i = 1, #columns do
        positions[i] = math.floor(x)
        x = x + widths[i] + margin
    end

    return widths, positions
end

-- getFieldCoords returns the coordinates for a given column.
-- It returns a table with integer values for x, y, w, and h.
-- align can be:
--   "auto" (default; no adjustment),
--   "absolute" (in which case offset is used as the exact x), or
--   a table { anchor, alignmentDirection } where anchor is another coords table.
local function getFieldCoords(colIndex, fieldType, columns, totalWidth, margin, fieldY, fieldH, align, offset)
    local widths, positions = computeColumnPositions(columns, totalWidth, margin)
    local coords = {
        x = positions[colIndex],
        w = widths[colIndex],
        y = fieldY,
        h = fieldH
    }

    if fieldType and type(fieldType) == "table" then
        local ft = fieldType[1]  -- e.g., "header" or "number" etc.
        local content = fieldType[2]
        if ft == "header" and content then
            local padding = 4  -- adjust padding as needed
            local textW = lcd.getTextSize(content)
            local newW = math.floor(textW + padding)
            coords.w = newW
            if type(align) == "table" then
                local anchor = align[1]  -- expected to be the field's coords
                local aType = align[2]
                if aType == "center" then
                    coords.x = math.floor(anchor.x + (anchor.w / 2) - (newW / 2))
                elseif aType == "left" then
                    coords.x = math.floor(anchor.x)
                elseif aType == "right" then
                    coords.x = math.floor(anchor.x + anchor.w - newW)
                end
            end
        end
    else
        if align == "absolute" then
            coords.x = math.floor(offset or coords.x)
        elseif type(align) == "table" then
            if type(align[2]) == "string" then
                local anchor = align[1]
                local aType = align[2]
                if aType == "left" then
                    coords.x = math.floor(anchor.x)
                elseif aType == "center" then
                    coords.x = math.floor(anchor.x + (anchor.w / 2) - (coords.w / 2))
                elseif aType == "right" then
                    coords.x = math.floor(anchor.x + anchor.w - coords.w)
                end
            elseif type(align[2]) == "table" then
                -- Combined centering between two anchors.
                local anchor1 = align[1]
                local anchor2 = align[2]
                local combinedX = math.min(anchor1.x, anchor2.x)
                local combinedRight = math.max(anchor1.x + anchor1.w, anchor2.x + anchor2.w)
                local combinedW = combinedRight - combinedX
                coords.x = math.floor(combinedX + (combinedW / 2) - (coords.w / 2))
            end
        end
    end
    
    return coords
end


function M.getLayout(section, reorderMode)
    if not lineW or not lineH then
        lineW, lineH = lcd.getWindowSize()
    end

    local board = system.getVersion().board
    local margin, expansionPanelRightOffset

    if board == "X20" or board == "X20S" or board == "X20PRO" or board == "X20PROAW" or
       board == "X20R" or board == "X20RS" then
        margin = 8
        expansionPanelRightOffset = 32
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

    local fieldY = margin
    local fieldH = lineH - (2 * margin) - 2

    -- Calculate usable width: subtract left margin and expansionPanelRightOffset.
    local usableWidth = lineW - expansionPanelRightOffset - margin

    local layout = { field = {}, header = {}, button = {} }
    local columns = {}

    if section == "batteryPanel" then
        if reorderMode then
            -- Reorder mode: 5 fields in order: batName, batClone, batDel, batUp, batDown.
            columns = {
                { name = "batName", ratio = "flex-fill" },
                { name = "batClone", ratio = 0.12 },
                { name = "batDel",   ratio = 0.12 },
                { name = "batUp",    ratio = 0.08 },
                { name = "batDown",  ratio = 0.08 },
            }
            -- Build field coordinates.
            layout.field.batName  = getFieldCoords(1, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batClone = getFieldCoords(2, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batDel   = getFieldCoords(3, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batUp    = getFieldCoords(4, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batDown  = getFieldCoords(5, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)

            -- Header: Use the batName field for batName header.
            layout.header.batName = getFieldCoords(1, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batName, "left" }, 0)
            -- For batMove header, use batUp as the anchor (or combine batUp and batDown if desired) with an absolute offset.
            layout.header.batMove = getFieldCoords(2, columns, usableWidth, margin, fieldY, fieldH, {layout.field.batUp, layout.field.batDown}, 50)
        else
            -- Normal mode: 5 fields: batName, batType, batCels, batCap, batId.
            columns = {
                { name = "batName", ratio = "flex-fill" },
                { name = "batType", ratio = 0.13 },
                { name = "batCels", ratio = 0.06 },
                { name = "batCap",  ratio = 0.20 },
                { name = "batId",   ratio = 0.06 },
            }
            layout.field.batName = getFieldCoords(1, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batType = getFieldCoords(2, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batCels = getFieldCoords(3, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batCap  = getFieldCoords(4, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)
            layout.field.batId   = getFieldCoords(5, columns, usableWidth, margin, fieldY, fieldH, "auto", 0)

            layout.header.batName = getFieldCoords(1, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batName, "left" }, 0)
            layout.header.batType = getFieldCoords(2, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batType, "left" }, 0)
            layout.header.batCels = getFieldCoords(3, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batCels, "center" }, 0)
            layout.header.batCap  = getFieldCoords(4, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batCap, "center" }, 0)
            layout.header.batId   = getFieldCoords(5, { "header", "ID" }, columns, usableWidth, margin, fieldY, fieldH, { layout.field.batId, "center" }, 0)
        end

        -- Define buttons with fixed values.
        layout.button.batReorder = { x = math.floor(margin), y = fieldY, w = 150, h = fieldH }
        layout.button.batAdd     = { x = layout.button.batReorder.w + margin * 2, y = fieldY, w = 150, h = fieldH }
    else
        return false  -- Unknown section
    end

    return layout
end

return M
