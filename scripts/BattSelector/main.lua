-- BattSelect + ETHOS LUA configuration
local config = {}
config.widgetName = "Battery Select"				    -- name of the tool
config.widgetDir = "/scripts/BattSelector/"				-- base path the script is installed into
config.useCompiler = false								-- enable or disable compilation

compile = assert(loadfile(config.widgetDir .. "compile.lua"))(config)

battsel = assert(compile.loadScript(config.widgetDir .. "battsel.lua"))(config, compile)

local function wakeup(widget)
    battsel.wakeup(widget)
end

local function paint(widget)
    battsel.paint(widget)
end

local function event(widget, category, value, x, y)
    return battsel.event(widget, category, value, x, y)
end

local function create(widget)
    return battsel.create(widget)
end

local function close(widget)
    return battsel.close()
end

local function build(widget)
    return battsel.build(widget)
end

local function configure(widget)
    return battsel.configure(widget)
end

local function read(widget)
    return battsel.read(widget)
end

local function write(widget)
    return battsel.write(widget)
end

local function init()
    system.registerWidget({
        key="battsel", 
        name=config.widgetName, 
        create=create, 
        build=build,
        paint=paint, 
		event=event,
        wakeup=wakeup,
        configure=configure, 
        read=read, 
        write=write, 
        runDebug=runDebug
    })
end

return {init = init}
