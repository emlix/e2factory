module("environment", package.seeall)
require("sha1")

--- create new environment
-- @return environment
function new()
  local env = {}
  local meta = { __index = environment }
  setmetatable(env, meta)
  env.dict = {}
  env.sorted = {}
  return env
end

--- set variable
-- @param env environment
-- @param var key
-- @param val value
-- @return env as passed in the first parameter
function set(env, var, val)
  env.dict[var] = val
  table.insert(env.sorted, var)
  table.sort(env.sorted)
  return env
end

--- return a hash representing the environment
-- @param env environment
function id(env)
  local sha1 = sha1.sha1_init()
  for var, val in env:iter() do
    sha1:update(string.format("%s=%s", var, val))
  end
  return sha1:final()
end

--- merge environment from merge into env.
-- @param env environment
-- @param merge environment
-- @param override bool: shall vars from merge override vars from env?
-- @return environment as merged from env and merge
function merge(env, merge, override)
  for i, var in ipairs(merge.sorted) do
    if not env.dict[var] then
      table.insert(env.sorted, var)
    end
    if not env.dict[var] or override then
      env.dict[var] = merge.dict[var]
    end
  end
  return env
end

--- iterate over the environment, in alphabetical order
-- @param env environment
function iter(env)
  local index = nil
  local function _iter(t)
    local var
    index, var = next(t, index)
    return var, env.dict[var]
  end
  return _iter, env.sorted
end

--- return a (copy of the) dictionary
-- @param env environment
-- @return a copy of the dictionary representing the environment
function get_dict(env)
  local dict = {}
  for k,v in env:iter() do
    dict[k] = v
  end
  return dict
end

function unittest(env)
  local function p(...)
    --print(...)
  end

  e1 = new()
  e1:set("var1.3", "val1.3")
  e1:set("var1.1", "val1.1")
  e1:set("var1.2", "val1.2")
  e1:set("var1.4", "val1.4")
  assert(e1:id() == "84C3CB1BFF877D12F500C05D7B133DA2B8BC0A4A")

  e2 = new()
  e2:set("var2.3", "val2.3")
  e2:set("var2.1", "val2.1")
  e2:set("var2.2", "val2.2")
  e2:set("var2.4", "val2.4")
  assert(e2:id() == "7E63398D2CA50AE2763042392628E8031AF30B02")

  for var, val in e1:iter() do
    p(var, val)
  end

  for var, val in e2:iter() do
    p(var, val)
  end

  e1:merge(e2)
  assert(e1:id() == "AF0572C5622CD21D3839AEA8D43234F6A67B7BA2")

  for var, val in e1:iter() do
    p(var, val)
  end

  -- check merge without / with override
  e3 = new()
  e3:set("var", "val3")
  e4 = new()
  e4:set("var", "val4")
  e3:merge(e4, false)
  for var, val in e3:iter() do
    p(var, val)
  end
  assert(e3:id() == "0728A49396F211F911E69FB929F7FEE715F4F981")

  e5 = new()
  e5:set("var", "val5")
  e5:merge(e4, true)
  for var, val in e5:iter() do
    p(var, val)
  end
  assert(e5:id() == "404AA226CF94A483FD61878682F8E2759998B197")

  local dict = e5:get_dict()
  assert(dict['var'] == "val4")
end
