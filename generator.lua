local cparser = require("cparser.cparser")

local f, tmpfile

---------------------
-- copy base files --
---------------------

local to_copy = {"init.lua", "master.lua"}

for _, name in ipairs(to_copy) do
    f = io.open("output/" .. name, "w")
    for line in io.lines("base/" .. name) do f:write(line .. "\n") end
    f:close()
end

--------------------
-- generate cdefs --
--------------------

tmpfile = io.tmpfile()

cparser.cpp("fmodstudio/headers/fmod_studio.h", tmpfile, { "-Ifmodstudio/headers"})

tmpfile:seek("set")
local data = tmpfile:read("*all")
tmpfile:close()

local cdef = {
    'local ffi = require("ffi")',
    'ffi.cdef[[',
    data:gsub("#.-\n", ""),
    ']]'
}

f = io.open("output/cdef.lua", "w")
f:write(table.concat(cdef, "\n"))
f:close()

--------------------
-- generate enums --
--------------------

local enums = {}
for line in io.lines("base/enums.lua") do enums[#enums + 1] = line end

for match in data:gmatch("typedef enum .-\n%{(.-)%}") do
    for line in match:gmatch("    ([^\n]+)") do
        line = line:gsub(",.*$", "")
        line = line:gsub(" =.*$", "")
        enums[#enums + 1] = string.format("M.%s = ffi.C.%s", line, line)
    end
end

f = io.open("output/enums.lua", "w")
f:write(table.concat(enums, "\n"))
f:close()


------------------------
-- generate constants --
------------------------

local ignored = {}
local constants = {}
for line in io.lines("base/constants.lua") do constants[#constants + 1] = line end

local function recursion(filename, t)
    -- recurse through the headers to extract (almost) all the #define macros
    t = t or {}
    local f = io.open("fmodstudio/headers/" .. filename)
    if f then
        for line in f:lines() do
            local include = line:match('^#include "(.+)"')
            if include then recursion(include, t) end

            -- function-like macros are ignored, as well as macros that don't start with "FMOD" and macros with no value
            local name, value = line:match("^#define (FMOD[%w_]+) (.+)$")
            if name and value then
                value = value:gsub("%s*", "")
                value = value:gsub("//.*$", "")
                value = value:gsub("/%*.-%*/", "")
                value = value:gsub("(FMOD[%w_]*)", "M.%1")
                t[#t + 1] = {name=name, value=value:gsub("%s*", "")}
            end
        end
    end
    return t
end

local defines = recursion("fmod_studio.h")

for _, t in ipairs(defines) do
    local name, value = t.name, t.value
    local processed_value

    if name:match("^FMOD_PRESET") then
        local tmp = value:gsub("f", "")
        tmp = tmp:match("%{(.-)%}")
        processed_value = string.format([[ffi.new("FMOD_REVERB_PROPERTIES", %s)]], tmp)
    elseif value:match("^+?-?%d+$") then -- integer
        processed_value = value
    elseif value:match("^0x" .. string.rep("%x", 16) .. "$") then -- long long
        processed_value = value .. "LL"
    elseif value:match("^0x%x+$") then -- hexadecimal
        processed_value = value
    elseif value:match("^M%.FMOD[%w_]*$") then -- same as other constant
        processed_value = value
    elseif value:match("^%(M%.FMOD[%w_]*%-%d*%)$") then -- subtract number from other constant
        processed_value = value
    elseif value:match("^%(%d+<<%d+%)$") then -- lshift
        processed_value = string.format("bit.lshift(%s,%s)",value:match("(%d+)<<(%d+)"))
    elseif value:match("^%(%-?%d+%*%d+%)$") then -- multiplication
        processed_value = string.format("%s*%s",value:match("(-?%d+)%*(%d+)"))
    elseif value:match("^%(.*%)$") then
        -- bitwise-or
        local t, is_bor = {}, true
        for m in value:gmatch("[^()|]+") do
            if not m:match("^M%.FMOD[%w_]*$") then
                is_bor = false
                break
            end
            t[#t + 1] = m
        end
        if is_bor then
            processed_value = string.format("bit.bor(%s)", table.concat(t, ","))
        end
    end

    if processed_value then
        constants[#constants + 1] = string.format("M.%s = %s", name, processed_value)
    else
        ignored[#ignored + 1] = string.format("#define %s %s", name, value)
    end

end

f = io.open("output/constants.lua", "w")
f:write(table.concat(constants, "\n"))
f:close()

f = io.open("output/ignored_constants.txt", "w")
f:write(table.concat(ignored, "\n"))
f:close()

------------------
-- wrap classes --
------------------

local wrap = {}
for line in io.lines("base/wrap.lua") do wrap[#wrap + 1] = line end

local classes = {
    core = {"System", "Sound", "ChannelControl", "Channel", "ChannelGroup", "SoundGroup", "DSP", "DSPConnection", "Geometry", "Reverb3D"},
    studio = {"System", "EventDescription", "EventInstance", "Bus", "VCA", "Bank", "CommandReplay"}
}

local is_class = {core={}, studio={}}
for _, x in ipairs(classes.core) do is_class.core[x] = true end
for _, x in ipairs(classes.studio) do is_class.studio[x] = true end

-- parse html files to find out which arguments are meant as output
local argouts = {}

local function parse_html(filename)
    local f = io.open("fmodstudio/html/" .. filename)
    local html = f:read("*all") .. "&&&&"
    html = html:gsub("<h2", "&&&&<h2")
    f:close()
    for m in html:gmatch("(<h2.-)&&&&") do
        if m:match('^<h2 api="function"') then
            local name = m:match('<div class="highlight language%-c">[^\n]-<span class="nf">(.-)</span>')
            if name then
                argouts[name] = {}
                local counter = 0
                for arg in m:gmatch('<dt>.-</dt>') do
                    counter = counter + 1
                    arg = arg:match('<dt>([^\n]-) <span><a class="token" href="glossary%.html#documentation%-conventions" title="Output">')
                    argouts[name][counter] = arg or false
                end
            end
        end
    end
end

if arg[1] ~= "--noargout" then
    for _, class in ipairs(classes.core) do
        parse_html(string.format("core-api-%s.html", class:lower()))
    end
    for _, class in ipairs(classes.studio) do
        parse_html(string.format("studio-api-%s.html", class:lower()))
    end 
end
wrap[#wrap + 1] = string.format("M.NO_ARG_OUT = %s", arg[1] == "--noargout" and "true" or "false")


f = io.open("output/output_arguments.txt", "w")
for name, t in pairs(argouts) do
    for _, a in ipairs(t) do
        if a then f:write(string.format("%s: %s\n", name, a)) end
    end
end
f:close()

wrap[#wrap + 1] = [[local core, studio = {}, {}]]
for _, class in ipairs(classes.core) do
    wrap[#wrap + 1] = string.format("core.%s = {}\ncore.%s.__index = core.%s", class, class, class)
end
for _, class in ipairs(classes.studio) do
    wrap[#wrap + 1] = string.format("studio.%s = {}\nstudio.%s.__index = studio.%s", class, class, class)
end

tmpfile = io.tmpfile()
cparser.parse("fmodstudio/headers/fmod_studio.h", tmpfile, { "-Ifmodstudio/headers"})

local tmp = {"return {"}
tmpfile:seek("set")
for line in tmpfile:lines() do
    if line:match("^| Declaration%{type=Function") then
        line = line:gsub("%.%.", "")
        line = line:gsub("| Declaration", "")
        tmp[#tmp + 1] = line .. ","
    end
end
tmp[#tmp + 1] = "}"
tmpfile:close()

local func = loadstring(table.concat(tmp, "\n"))
local env = {}
env.Type = function(t) return t.n end
env.Pointer = function(t) return (type(t.t) == "table" and t.t.n or t.t) .. "*" end
env.Pair = function(t) return t end
env.Function = function(t) return t end
env.Qualified = function(t) return (t.const and "const " or  "") .. (type(t.t) == "table" and t.t.n or t.t) end

setfenv(func, env)
tmp = func()

if arg[1] ~= "--noargout" then
    for _, fn in ipairs(tmp) do
        for i, a in ipairs(fn.type) do
            if argouts[fn.name] and argouts[fn.name][i - 1] then
                a.out = true
                if argouts[fn.name][i - 1] == "array" then a.array = true end
            end
        end
    end
end

local template = {}
template.begin = [[function &mt&:&name&(&args&)]]
template.argout = [[    local &arg& = ffi.new("&type&[1]")]]
template.out_array = [[    local &arg& = ffi.new("&type&[?]", &capacity&)]]
template.finish = 
[[    local result = C.&cname&(&fullargs&)
    return &outargs&
end]]

local function print_args(fn, full)
    local t = {full and "self" or nil}
    local counter = 1
    for i, a in ipairs(fn.type) do
        if i > 1 then
            if not a.out then
                t[#t + 1] = string.format("i%d", counter)
                counter = counter + 1
            elseif full then
                t[#t + 1] = string.format("o%d", i - counter)
            end
        end
    end
    return table.concat(t, ",")
end

local function print_out_args(fn)
    local t = {}
    for _, a in ipairs(fn.type) do
        if a.out then
            t[#t + 1] = string.format(a.array and "o%d" or "o%d[0]", #t + 1)
        end
    end
    t[#t + 1] = "result"
    return table.concat(t, ",")
end

wrap[#wrap + 1] = ""

for _, fn in ipairs(tmp) do
    local name = fn.name:match("_(%w+)$")
    local studio_class = fn.name:match("^FMOD_Studio_(%w+)_")
    local core_class = not studio_class and  fn.name:match("^FMOD_(%w+)_")

    if name ~= "Create" and (is_class.core[core_class] or is_class.studio[studio_class]) then
        name = name:gsub("^%u", function(c) return c:lower() end)
        local mt = studio_class and ("studio." .. studio_class) or ("core." .. core_class)
        wrap[#wrap + 1] = template.begin:gsub("&%w+&", {
            ["&name&"] = name,
            ["&mt&"] = mt,
            ["&args&"] = print_args(fn)
        })
        local counter = 0
        for i, a in ipairs(fn.type) do
            if a.out then
                counter = counter + 1
                if a.array then
                    wrap[#wrap + 1] = template.out_array:gsub("&%w+&", {
                        ["&arg&"] = string.format("o%d", counter),
                        ["&type&"] = a[1]:gsub("*$", ""),
                        ["&capacity&"] = string.format("i%d", i - counter), -- next input
                    })
                else
                    wrap[#wrap + 1] = template.argout:gsub("&%w+&", {
                        ["&arg&"] = string.format("o%d", counter),
                        ["&type&"] = a[1]:gsub("*$", "")
                    })
                end
            end
        end
        wrap[#wrap + 1] = template.finish:gsub("&%w+&", {
            ["&fullargs&"] = print_args(fn, true),
            ["&cname&"] = fn.name,
            ["&outargs&"] = print_out_args(fn)
        })
    end

end

wrap[#wrap + 1] = ""

for _, class in ipairs(classes.core) do
    wrap[#wrap + 1] = string.format([[ffi.metatype("FMOD_%s", core.%s)]], class:upper(), class)
end
for _, class in ipairs(classes.studio) do
    wrap[#wrap + 1] = string.format([[ffi.metatype("FMOD_STUDIO_%s", studio.%s)]], class:upper(), class)
end

f = io.open("output/wrap.lua", "w")
f:write(table.concat(wrap, "\n"))
f:close()

-----------------
-- ErrorString --
-----------------

local errors = {}
for line in io.lines("base/errors.lua") do errors[#errors + 1] = line end

errors[#errors + 1] = "\nM.ErrorString = function(e)"

for line in io.lines("fmodstudio/headers/fmod_errors.h") do
    local result, ret = line:match('^%s*case%s*([%w_]+):%s*(return ".-");')
    if result and ret then
        errors[#errors + 1] = string.format("    if e == M.%s then %s end", result, ret)
    end
end

errors[#errors + 1] = "end"

f = io.open("output/errors.lua", "w")
f:write(table.concat(errors, "\n"))
f:close()
