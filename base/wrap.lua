local env = {
    assert = assert,
    type = type,
    tonumber = tonumber,
    tostring = tostring,
    require = require,
    error = error,
    getmetatable = getmetatable,
    setmetatable = setmetatable,
    string = string,
    table = table,
}
setfenv(1, env)


local path = (...):gsub("[^%.]*$", "")
local M = require(path .. "master")
local ffi = require("ffi")

local C = M.C
M.Studio = {}

---------------------
-- manual wrapping --
---------------------

M.System = {}
M.System.create = function(i1, i2)
    if M.NO_ARG_OUT then
        i2 = i2 or M.FMOD_VERSION
        return C.FMOD_System_Create(i1, i2)
    else
        i1 = i1 or M.FMOD_VERSION
        local p = ffi.new("FMOD_SYSTEM*[1]")
        local result = C.FMOD_System_Create(p, i1)
        return p[0], result
    end
end

M.Studio.System = {}
M.Studio.System.create = function(i1, i2)
    if M.NO_ARG_OUT then
        i2 = i2 or M.FMOD_VERSION
        return C.FMOD_Studio_System_Create(i1, i2)
    else
        i1 = i1 or M.FMOD_VERSION
        local p = ffi.new("FMOD_STUDIO_SYSTEM*[1]")
        local result = C.FMOD_Studio_System_Create(p, i1)
        return p[0], result
    end
end

M.Studio.parseID = function(i1, i2)
    if M.NO_ARG_OUT then
        return C.FMOD_Studio_ParseID(i1, i2)
    else
        local p = ffi.new("FMOD_GUID[1]")
        local result = C.FMOD_Studio_ParseID(i1, p)
        return p[0], result
    end
end

--------------------------
-- begin generated code --
--------------------------
