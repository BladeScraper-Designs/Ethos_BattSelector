-- layout.lua
local M = {}

local function alignField(label, alignment, anchorRect, padding, offset, lineW, fieldY, fieldH, margin)
  padding = padding or 0
  local textW = lcd.getTextSize(label)
  local totalW = textW + 2 * padding
  local rect = {}
  if anchorRect then
    if alignment == "center" then
      rect.x = anchorRect.x + math.floor((anchorRect.w - totalW) / 2)
    elseif alignment == "right" then
      rect.x = anchorRect.x + anchorRect.w - totalW
    else -- left alignment
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

local function alignForButton(label, alignment, fieldY, fieldH, margin, maxRight)
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

-- getLayout now accepts a section parameter, e.g. "batteryPanel", "favoritesPanel", or "imagesPanel"
function M.getLayout(section)
  local lineW, lineH = lcd.getWindowSize()
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

  local maxRight = lineW - expansionPanelRightOffset
  local usableWidth = maxRight - margin
  local fieldH = lineH - (2 * margin) - 2
  local fieldY = margin

  local columns = {}
  if section == "batteryPanel" then
    -- Use a multi-column layout for the battery panel
    columns = {
      { name = "batName", ratio = 0.47 },
      { name = "batType", ratio = 0.13 },
      { name = "batCels", ratio = 0.07 },
      { name = "batCap",  ratio = 0.16 },
      { name = "batId",   ratio = 0.05 },
    }
  elseif section == "favoritesPanel" then
    -- For the favorites panel, assume a single-column layout (adjust as needed)
    columns = {
      { name = "favName", ratio = 1.0 },
    }
  elseif section == "imagesPanel" then
    -- For the images panel, assume a single-column layout for file fields
    columns = {
      { name = "imgField", ratio = 1.0 },
    }
  else
    -- Fallback to battery panel layout if no section is provided
    columns = {
      { name = "batName", ratio = 0.47 },
      { name = "batType", ratio = 0.13 },
      { name = "batCels", ratio = 0.07 },
      { name = "batCap",  ratio = 0.16 },
      { name = "batId",   ratio = 0.05 },
    }
  end

  local ratioSum = 0
  for _, col in ipairs(columns) do
    ratioSum = ratioSum + col.ratio
  end

  local nCols = #columns
  local totalColSpacing = (nCols - 1) * margin
  local availableForCols = usableWidth - totalColSpacing

  local colWidth = {}
  local totalW = 0
  for _, col in ipairs(columns) do
    local w = math.floor((col.ratio / ratioSum) * availableForCols)
    colWidth[col.name] = w
    totalW = totalW + w
  end

  local leftover = availableForCols - totalW
  if leftover ~= 0 and colWidth[columns[1].name] then
    colWidth[columns[1].name] = colWidth[columns[1].name] + leftover
    if colWidth[columns[1].name] < 1 then colWidth[columns[1].name] = 1 end
  end

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
    layout.field[col.name] = { x = x, y = fieldY, w = colWidth[col.name], h = fieldH }
    x = x + colWidth[col.name]
    if i < nCols then
      x = x + margin
    end
  end

  -- For the battery panel, add header and button positions.
  if section == "batteryPanel" then
    layout.header.batName = alignField("Name", "left", layout.field.batName, 2, nil, lineW, fieldY, fieldH, margin)
    layout.header.batType = alignField("Type", "left", layout.field.batType, 2, nil, lineW, fieldY, fieldH, margin)
    layout.header.batCels = alignField("Cells", "center", layout.field.batCels, 2, nil, lineW, fieldY, fieldH, margin)
    layout.header.batCap  = alignField("Capacity", "center", layout.field.batCap, 2, nil, lineW, fieldY, fieldH, margin)
    layout.header.batId   = alignField("ID", "center", layout.field.batId, 2, nil, lineW, fieldY, fieldH, margin)
    layout.button.batReorder = alignForButton("Reorder/Edit", "left", fieldY, fieldH, margin, maxRight)
    layout.button.batAdd     = alignForButton("Add New", "right", fieldY, fieldH, margin, maxRight)
  end

  return layout
end

return M
