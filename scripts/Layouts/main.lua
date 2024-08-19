-- Lua layout creator for RF2 (X20 and X18 Screen Size Only)

local function init()
    -- Determine if running on X18 or X20 (other radios not supported yet)
    local environment = system.getVersion()
    local radio = environment.board

    -- If screen size matches X20 Series Radio
    if string.match(radio, "^X20") then
        -- Main Front Page Layout
        system.registerLayout({key="RF2", widgets={
            {x=8, y=95, w=256, h=100},
            {x=8, y=203, w=256, h=100},
            {x=8, y=311, w=256, h=100},
            {x=272, y=95, w=256, h=154},
            {x=272, y=257, w=256, h=154},
            {x=536, y=95, w=256, h=154},
            {x=536, y=257, w=256, h=154},
        }})
        print("Layout registered for X20 Series Radio")
    end

    -- If screen size matches X18 Series Radio
    if string.match(radio, "^X18") then
        -- Main Front Page Layout
        system.registerLayout({key="RF2", widgets={
            {x=4, y=62, w=155, h=67},
            {x=4, y=133, w=155, h=67},
            {x=4, y=204, w=155, h=67},
            {x=163, y=62, w=155, h=105},
            {x=163, y=171, w=155, h=100},
            {x=322, y=62, w=155, h=105},
            {x=322, y=171, w=155, h=100},
        }})
        print("Layout registered for X18 Series Radio")
    end
end

return {init=init}
