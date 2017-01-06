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
local trace_enabled = true

--- Function call tracer. Logs all function calls at debug level while active.
-- @param event string: type of event
-- @param line line number of event (unused)
local function tracer(event, line)
    local ftbl, module, out, name, value, isbinary, svalue, overlen, fnbl

    if not trace_enabled then
        return
    end

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
            module = "<unknown>."
        end
    end

    if module_blacklist[module] then
        return
    end

    if function_blacklist[module] and function_blacklist[module][ftbl.name] then
        return
    end

    if event == "call" then
        -- out = string.format("(%d) %s%s(", e2lib.getpid(), module, ftbl.name)
        out = string.format("%s%s(", module, ftbl.name)
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
                for i=1,40 do
                    svalue = string.byte(value, i)
                    if svalue == nil then
                        break
                    elseif (svalue >= 0 and svalue < 9)
                        or (svalue > 13 and svalue < 32) then
                        isbinary = true
                        break
                    end
                end

                if isbinary then
                    out = string.format("%s%s=<binary>", out, name)
                else
                    overlen = ""
                    svalue = string.sub(value, 1, 200)
                    if string.len(value) > string.len(svalue) then
                        overlen = "..."
                    end

                    out = string.format("%s%s=%q%s", out, name, svalue, overlen)
                end
            elseif type(value) == "table" then
                out = string.format("%s%s=T", out, name)
            elseif type(value) == "function" then
                out = string.format("%s%s=F", out, name)
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

--- Install function call tracer hook.
function trace.install()
    debug.sethook(tracer, trace_flags)
end

--- Remove function call tracer hook.
-- Note this interacts badly with the e2lib.interrupt_hook magic.
-- Do not use without care.
function trace.uninstall()
    debug.sethook()
end

--- Switch on trace logging if a trace hook is active.
function trace.on()
    trace_enabled = true
end

--- Switch off trace logging if a trace hook is active.
function trace.off()
    trace_enabled = false
end

--- Exclude entire module from being logged by the tracer.
-- @param module_name Module name.
function trace.filter_module(module_name)
    assertIsStringN(module_name)
    module_blacklist[module_name.."."] = true
end

--- Remove module from blacklist
-- @param module_name Module name.
function trace.filter_module_remove(module_name)
    assertIsStringN(module_name)
    module_blacklist[module_name.."."] = nil
end

--- Exclude function in a module from being logged by the tracer.
-- @param module_name Module name.
-- @param function_name Function name.
function trace.filter_function(module_name, function_name)
    assertIsStringN(module_name)
    assertIsStringN(function_name)
    module_name = module_name.."."
    if not function_blacklist[module_name] then
        function_blacklist[module_name] = {}
    end

    function_blacklist[module_name][function_name] = true
end

--- Remove function from blacklist
-- @param module_name Module name.
-- @param function_name Function name.
function trace.filter_function_remove(module_name, function_name)
    assertIsStringN(module_name)
    assertIsStringN(function_name)
    module_name = module_name.."."

    if function_blacklist[module_name] then
        function_blacklist[module_name][function_name] = nil
        if next(function_blacklist[module_name]) == nil then
             function_blacklist[module_name] = nil
         end
     end
end

--- Default filter setup.
function trace.default_filter()
    trace_flags = os.getenv("E2_TRACE") or "c"
    trace.filter_module("<unknown>")
    trace.filter_module("C")
    trace.filter_module("assrt")
    trace.filter_module("class")
    trace.filter_module("err")
    trace.filter_module("sl")
    trace.filter_module("trace")
    trace.filter_module("strict")

    trace.filter_function("cache", "assertFlags")
    trace.filter_function("cache", "ce_by_server")
    trace.filter_function("cache", "server_names")
    trace.filter_function("e2lib", "(for generator)")
    trace.filter_function("e2lib", "getlog")
    trace.filter_function("e2lib", "join")
    trace.filter_function("e2lib", "log")
    trace.filter_function("e2lib", "logf")
    trace.filter_function("e2lib", "warnf")
    trace.filter_function("e2tool", "info")
    trace.filter_function("eio", "is_eio_object")
    trace.filter_function("eio", "new")
    trace.filter_function("environment", "(for generator)")
    trace.filter_function("environment", "get_dict")
    trace.filter_function("environment", "iter")
    trace.filter_function("hash", "hash_append")
end

return strict.lock(trace)

-- vim:sw=4:sts=4:et:
