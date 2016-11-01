--- Function call tracing
-- @module generic.trace

-- Copyright (C) 2013-2016 emlix GmbH, see file AUTHORS
--
-- This file is part of e2factory, the emlix embedded build system.
-- For more information see http://www.e2factory.org
--
-- e2factory is a registered trademark of emlix GmbH.
--
-- e2factory is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details.

local trace = {}
local e2lib = require("e2lib")
local strict = require("strict")

local module_blacklist = {}
local function_blacklist = {}
local trace_flags = "c"

--- Function call tracer. Logs all function calls at debug level while active.
-- @param event string: type of event
-- @param line line number of event (unused)
local function tracer(event, line)
    local ftbl, module, out, name, value, isbinary, svalue, overlen, fnbl

    ftbl = debug.getinfo(2)
    if ftbl == nil or ftbl.name == nil then
        return
    end

    -- approximate module name, not always accurate but good enough
    if ftbl.source == nil or ftbl.source == "=[C]" then
        module = "C."
    else
        module = string.match(ftbl.source, "([^/]+%.)lua$")
        if module == nil then
            module = "<unknown module>."
        end
    end

    if module_blacklist[module] then
        return
    end

    fnbl = function_blacklist[ftbl.name]
    if fnbl then
        if fnbl[module] then
            return
        end
    end

    if event == "call" then
        out = string.format("(%d) %s%s(", e2lib.getpid(), module, ftbl.name)
        for lo = 1, 10 do
            name, value = debug.getlocal(2, lo)
            if name == nil or name == "(*temporary)" then
                break
            end
            if lo > 1 then
                out = out .. ", "
            end

            if type(value) == "string" then
                isbinary = false

                -- check the first 40 bytes for values common in binary data
                for _,v in ipairs({string.byte(value, 1, 40)}) do
                    if (v >= 0 and v < 9) or (v > 13 and v < 32) then
                        isbinary = true
                        break
                    end
                end

                if isbinary then
                    out = string.format("%s%s=<binary data>", out, name)
                else
                    overlen = ""
                    svalue = string.sub(value, 1, 300)
                    if string.len(value) > string.len(svalue) then
                        overlen = "..."
                    end

                    out = string.format("%s%s=%q%s", out, name, svalue, overlen)
                end
            else
                out = string.format("%s%s=%s", out, name, tostring(value))
            end

        end
        out = out .. ")"
        e2lib.log(4, out)
    else
        e2lib.logf(4, "< %s%s", module, ftbl.name)
    end
end

--- Enable function call tracer.
function trace.enable()
    debug.sethook(tracer, trace_flags)
end

--- Disable function call tracer.
function trace.disable()
    debug.sethook()
end

--- Exclude entire module from being logged by the tracer.
-- @param module_name Module name.
function trace.filter_module(module_name)
    module_name = module_name.."."
    module_blacklist[module_name] = true
end

--- Exclude function in a module from being logged by the tracer.
-- @param module_name Module name.
-- @param function_name Function name.
function trace.filter_function(module_name, function_name)
    local fnbl

    module_name = module_name.."."
    if not function_blacklist[function_name] then
        function_blacklist[function_name] = {}
    end

    function_blacklist[function_name][module_name] = true
end

--- Default filter setup.
function trace.default_filter()
    trace_flags = os.getenv("E2_TRACE") or "c"
    trace.filter_module("<unknown module>")
    trace.filter_module("C")
    trace.filter_module("assrt")
    trace.filter_module("err")
    trace.filter_module("trace")
    trace.filter_function("e2lib", "log")
    trace.filter_function("e2lib", "logf")
    trace.filter_function("e2lib", "getlog")
    trace.filter_function("e2lib", "warnf")
    trace.filter_function("e2lib", "(for generator)")
    trace.filter_function("eio", "new")
    trace.filter_function("eio", "is_eio_object")
end

return strict.lock(trace)

-- vim:sw=4:sts=4:et:
