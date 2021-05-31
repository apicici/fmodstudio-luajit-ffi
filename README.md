# fmodstudio-luajit-ffi
Pure Lua script to generate a LuaJIT FFI wrapper for the [FMOD Engine](https://fmod.com/) (studio and core api). The generator *should* work for any version of FMOD, but it has only been tested on version 2.02.

The generator wraps the C api, but uses the C++ convention for classes by wrapping functions as methods. For example:
```lua
local fmod = require("folder_where_you_put_the_module")

local s = fmod.Studio.System.create()
s:initialize(...)
```
In the following it will be assumed that you load the generated module in Lua as
```lua
local fmod = require("folder_where_you_put_the_module")
```
although you can of course choose any other name for the Lua variable.

## How to generate the wrapper
1. First clone the repository or download a tagged version.
2. Download the FMOD Engine from the [FMOD website](FMOD Engine) and extract all of the C header files `fmod*.h` (both from Core and Studio) and place them in the `fmodstudio/headers` folder of the repository.
3. *Optional*: extract all the html files from the `doc` folder of the FMOD Engine archive to the `fmodstudio/html` folder of the repository. This step is only needed if you want the generator to figure out which function arguments are meant as output and treat them as such in Lua (i.e., drop them from the input list of the wrapped functions and return them istead—see the [section about it below](#about-output-arguments)), which is the default behaviour.
4. To generate the wrapper run
```luajit generator.lua```,
or
```luajit generator.lua --noargout```
if you don't want to treat output arguments differently.

5. The Lua module is generated in the `output` folder of the repository.

## Loading the module in Lua
After you generate the module, you can load it in lua by copying the `output` folder to your project, renaming it as you prefer, and loading it using `require`.

Note that the module needs to know where to find the two FMOD shared libraries `libfmod` and `libfmodstudio` in order to load them with `ffi.load`. You should change your `package.cpath` so that they can be found. This needs to be done *before* you load the module.
```lua
package.cpath = "path_to_libs/?.ext;" .. package.cpath -- ext depends on OS (so, dll, dylib)

-- Assuming you rename the folder to `fmodstudio`:
local fmod = require("fmodstudio")
-- or
local fmod = require("fmodstudio.init") -- if your package.path doesn't have "./?/init.lua"
```

## About output arguments

The default behaviour of the generator is to parse the html files in the documentation to find out which function arguments are treated as outputs. These arguments are excluded from the list of arguments to be passed to the wrapped functions, and are returned instead. Note that these outputs are returned *before* the actual return value of the C function. The arguments that are interpreted as outputs are listed in `output/output_arguments.txt`.
```lua
-- the variable fmod.NO_ARG_OUT is set to true if the module is generated with the --noargout option

local s, result

if not fmod.NO_ARG_OUT then -- default behaviour
    s, result = fmod.Studio.System.create()
else
    local ffi = require("ffi")
    local p = ffi.new("FMOD_STUDIO_SYSTEM*[1]")
    result = fmod.Studio.System.create(p)
    s = p[0]
end
```
The same applies with the few functions that have an array output argument (the various `getList` functions):
```lua
-- here s is an initialized Studio System

local bank_list, count, result

local capacity = 10 -- max size of the array
if not fmod.NO_ARG_OUT then -- default behaviour
    bank_list, count, result = s:getBankList(capacity)
else
    local ffi = require("ffi")
    bank_list = ffi.new("FMOD_STUDIO_BANK*[?]", capacity) -- array of size "capacity"
    local p = ffi.new("int[1]")
    result = s:getBankList(p1, capacity, p2)
    count = p[0]
end
```

## Wrapping conventions
* All the enums in the Core and Studio API are wrapped and accessible in the `fmod` table, for example `fmod.FMOD_OK`.
* All the constants defined through macros *should* be wrapped and accessible in the `fmod` table, for example `fmod.FMOD_VERSION`. Check the file `output/ignored_constants.txt` to see if any where not recognised by the generator. There should be none, but some may be introduced in newer versions and require a change in the generator script to be recognised.
* The only non-method functions that are wrapped are:
    * `FMOD_ErrorString` from `fmod_errors.h`, wrapped as `fmod.ErrorString`
    * `FMOD_System_Create`, wrapped as `fmod.System.create`
    * `FMOD_Studio_System_Create`, wrapped as `fmod.Studio.System.create`
    * `FMOD_Studio_ParseID`, wrapped as `fmod.Studio.System.parseID`
* All the function that are listed as (non-static) member functions in the C++ API are wrapped as methods using the C++ naming convention. For example `FMOD_System_Release(system)` can be called as `system:release()`.
* The C functions can be also be accessed directly through `ffi` instead of using the Lua wraps, and can be found in `fmod.C`. For example you can call directly `fmod.C.FMOD_System_Release(system)` where `system` is a `cdata` of type `FMOD_SYSTEM*`.






