local path = (...):gsub("[^%.]*$", "")
local M = require(path .. "master")
local ffi = require("ffi")