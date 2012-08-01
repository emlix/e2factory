--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2007-2009 Gordon Hecker <gh@emlix.com>, emlix GmbH
   Copyright (C) 2007-2009 Oskar Schirmer <os@emlix.com>, emlix GmbH
   Copyright (C) 2007-2008 Felix Winkelmann, emlix GmbH

   For more information have a look at http://www.e2factory.org

   e2factory is a registered trademark by emlix GmbH.

   This file is part of e2factory, the emlix embedded build system.

   e2factory is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

-- Topological sorting
--
--   table.tsort(DAG) -> ARRAY
--
--     Expects a table of tables as input, where each sub-table contains
--     the node name followed by its dependencies, and returns a topologically
--     sorted array of all entries.
--     When DAG is cyclic, return nil

function table.tsort(dag)
  local sorted = {}
  local adjust = {}
  local colour = {}
  local function visit(u, path)
    local p = path
    if p[u] then sorted = nil end
    if sorted and not colour[u] then
      local v = adjust[u]
      colour[u] = true
      if v then
        p[u] = true
        for i = 1, #v do visit(v[i], p) end
        p[u] = nil
      end
      if sorted then table.insert(sorted, u) end
    end
  end
  for i = 1, #dag do
    local l = {}
    for j = 2, #dag[i] do table.insert(l, dag[i][j]) end
    adjust[dag[i][1]] = l
  end
  for i = 1, #dag do visit(dag[i][1], {}) end
  return sorted
end


-- Table operations
--
--   table.reverse(TABLE) -> TABLE'
--
--     Reverse array elements and return new table.
--
--   table.map(TABLE, FUNCTION) -> TABLE'
--
--     Map over table elements creating new table. FUNCTION is called for each
--     table value and the result will be stored under the same key as the original
--     value.
--
--   table.filter(TABLE, FUNCTION) -> TABLE'
--
--     Returns a new table with all elements from TABLE removed that do not
--     satisfy the predicate FUNCTION.
--
--
--   table.grep(TABLE, PATTERN) -> TABLE'
--
--     Filter strings matching a pattern.
--
--   table.print(TABLE, [OUT])
--
--     Prints table contents on OUT, which defaults to io.stdout.
--
--   table.compare(TABLE1, TABLE2, [FUNCTION]) -> BOOL
--
--     Compares tables element by element by passing each pair of elements
--     to FUNCTION (which defaults to "function(x, y) return x == y end").
--
--   table.find(TABLE, VAL, [FUNCTION]) -> KEY, VAL
--
--     Searches TABLE for an entry VAL and returns the key (and value). FUNCTION
--     is the comparison function used to compare the values and defaults to
--     "function(x, y) return x == y end".

function table.reverse(t)
  local t2 = {}
  local len = #t
  local j = 1
  for i = len, 1, -1 do
    t2[ j ] = t[ i ]
    j = j + 1
  end
  return t2
end

function table.map(t, f)
  local t2 = {}
  for k, x in pairs(t) do
    t2[ k ] = f(x)
  end
  return t2
end

function table.filter(t, f)
  local t2 = {}
  local i = 1
  for k, x in pairs(t) do
    if f(x) then
      t2[ i ] = x
      i = i + 1
    end
  end
  return t2
end

function table.grep(t, p)
  local function match(x)
    return string.find(x, p)
  end
  return table.filter(t, match)
end

function table.print(t, out)
  local out = out or io.stdout
  out:write(tostring(t), ":\n")
  for k, v in pairs(t) do
    print("", k, "->", v)
  end
end

function table.compare(t1, t2, p)
  local p = p or function(x, y) return x == y end
  if #t1 ~= #t2 then return false
  else
    for k, v in pairs(t1) do
      local x = t2[ k ]
      if not p(v, x) then return false end
    end
    return true
  end
end

function table.find(t, x, cmp)
  cmp = cmp or function(x, y) return x == y end
  for k, v in pairs(t) do
    if cmp(v, x) then return k, v end
  end
  return nil
end


-- String operations
--
--   string.trim(STRING) -> STRING'
--
--     Removes whitespace on both sides from string.
--
--   string.explode(STRING) -> ARRAY
--
--     Convert string into array of characters (one-element strings).
--
--   string.split(STRING, PATTERN) -> ARRAY
--
--     Split string into elements matching PATTERN.

function string.trim(str)
  return string.match(str, "^%s*(.*%S)%s*$") or ""
end

function string.explode(str)
  local t = {}
  for i = 1, #str do
    table.insert(t, string.sub(str, i, i))
  end
  return t
end

function string.split(str, pat)
  local t = {}
  pat = pat or "%S+"
  for x in string.gmatch(str, pat) do
    table.insert(t, x)
  end
  return t
end
