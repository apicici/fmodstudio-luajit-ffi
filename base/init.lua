local path = (...):gsub(".init$", "") .. "."

require(path .. "cdef")

local M = require(path .. "master")
local ffi = require("ffi")

-- search for fmod shared libraries in package.cpath
local paths = {
    fmod = package.searchpath("libfmod", package.cpath),
    fmodstudio = package.searchpath("libfmodstudio", package.cpath)
}
assert(paths.fmod and paths.fmodstudio, "FMOD shared libraries not found!")

-- pretend to load libfmod through Lua (it's going to fail but not raise any errors)
-- so that its location is known when loading libfmodstudio through ffi
package.loadlib(paths.fmod, "")
M.C = ffi.load(paths.fmodstudio)

require(path .. "enums")
require(path .. "constants")
require(path .. "wrap")
require(path .. "errors")

return M