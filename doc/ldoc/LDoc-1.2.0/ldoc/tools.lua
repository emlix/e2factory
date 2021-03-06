---------
-- General utility functions for ldoc
-- @module tools

require 'pl'
local tools = {}
local M = tools
local append = table.insert
local lexer = require 'ldoc.lexer'
local quit = utils.quit

-- this constructs an iterator over a list of objects which returns only
-- those objects where a field has a certain value. It's used to iterate
-- only over functions or tables, etc.
-- (something rather similar exists in LuaDoc)
function M.type_iterator (list,field,value)
   return function()
      local i = 1
      return function()
         local val = list[i]
         while val and val[field] ~= value do
            i = i + 1
            val = list[i]
         end
         i = i + 1
         if val then return val end
      end
   end
end

-- KindMap is used to iterate over a set of categories, called _kinds_,
-- and the associated iterator over all items in that category.
-- For instance, a module contains functions, tables, etc and we will
-- want to iterate over these categories in a specified order:
--
--  for kind, items in module.kinds() do
--    print('kind',kind)
--    for item in items() do print(item.name) end
--  end
--
-- The kind is typically used as a label or a Title, so for type 'function' the
-- kind is 'Functions' and so on.

local KindMap = class()
M.KindMap = KindMap

-- calling a KindMap returns an iterator. This returns the kind, the iterator
-- over the items of that type, and the actual type tag value.
function KindMap:__call ()
   local i = 1
   local klass = self.klass
   return function()
      local kind = klass.kinds[i]
      if not kind then return nil end -- no more kinds
      while not self[kind] do
         i = i + 1
         kind = klass.kinds[i]
         if not kind then return nil end
      end
      i = i + 1
      local type = klass.types_by_kind [kind].type
      return kind, self[kind], type
   end
end

function KindMap:put_kind_first (kind)
   -- find this kind in our kind list
   local kinds = self.klass.kinds,kind
   local idx = tablex.find(kinds,kind)
   -- and swop with the start!
   if idx then
      kinds[1],kinds[idx] = kinds[idx],kinds[1]
   end
end

function KindMap:type_of (item)
   local klass = self.klass
   local kind = klass.types_by_tag[item.type]
   return klass.types_by_kind [kind]
end

function KindMap:get_section_description (kind)
   return self.klass.descriptions[kind]
end

-- called for each new item. It does not actually create separate lists,
-- (although that would not break the interface) but creates iterators
-- for that item type if not already created.
function KindMap:add (item,items,description)
   local group = item[self.fieldname] -- which wd be item's type or section
   local kname = self.klass.types_by_tag[group] -- the kind name
   if not self[kname] then
      self[kname] = M.type_iterator (items,self.fieldname,group)
      self.klass.descriptions[kname] = description
   end
   item.kind = kname:lower()
end

-- KindMap has a 'class constructor' which is used to modify
-- any new base class.
function KindMap._class_init (klass)
   klass.kinds = {} -- list in correct order of kinds
   klass.types_by_tag = {} -- indexed by tag
   klass.types_by_kind = {} -- indexed by kind
   klass.descriptions = {} -- optional description for each kind
end


function KindMap.add_kind (klass,tag,kind,subnames)
   klass.types_by_tag[tag] = kind
   klass.types_by_kind[kind] = {type=tag,subnames=subnames}
   append(klass.kinds,kind)
end


----- some useful utility functions ------

function M.module_basepath()
   local lpath = List.split(package.path,';')
   for p in lpath:iter() do
      local p = path.dirname(p)
      if path.isabs(p) then
         return p
      end
   end
end

-- split a qualified name into the module part and the name part,
-- e.g 'pl.utils.split' becomes 'pl.utils' and 'split'
function M.split_dotted_name (s)
   local s1,s2 = path.splitext(s)
   if s2=='' then return nil
   else  return s1,s2:sub(2)
   end
end

-- expand lists of possibly qualified identifiers
-- given something like {'one , two.2','three.drei.drie)'}
-- it will output {"one","two.2","three.drei.drie"}
function M.expand_comma_list (ls)
   local new_ls = List()
   for s in ls:iter() do
      s = s:gsub('[^%.:%-%w_]*$','')
      if s:find ',' then
         new_ls:extend(List.split(s,'%s*,%s*'))
      else
         new_ls:append(s)
      end
   end
   return new_ls
end

-- grab lines from a line iterator `iter` until the line matches the pattern.
-- Returns the joined lines and the line, which may be nil if we run out of
-- lines.
function M.grab_while_not(iter,pattern)
   local line = iter()
   local res = {}
   while line and not line:match(pattern) do
      append(res,line)
      line = iter()
   end
   res = table.concat(res,'\n')
   return res,line
end


function M.extract_identifier (value)
   return value:match('([%.:%-_%w]+)')
end

function M.strip (s)
   return s:gsub('^%s+',''):gsub('%s+$','')
end

function M.check_directory(d)
   if not path.isdir(d) then
      lfs.mkdir(d)
   end
end

function M.check_file (f,original)
   if not path.exists(f) or path.getmtime(original) > path.getmtime(f) then
      local text,err = utils.readfile(original)
      if text then
         text,err = utils.writefile(f,text)
      end
      if err then
         quit("Could not copy "..original.." to "..f)
      end
   end
end

function M.writefile(name,text)
   local ok,err = utils.writefile(name,text)
   if err then quit(err) end
end

function M.name_of (lpath)
   lpath,ext = path.splitext(lpath)
   return lpath
end

function M.this_module_name (basename,fname)
   local ext
   if basename == '' then
      return M.name_of(fname)
   end
   basename = path.abspath(basename)
   if basename:sub(-1,-1) ~= path.sep then
      basename = basename..path.sep
   end
   local lpath,cnt = fname:gsub('^'..utils.escape(basename),'')
   --print('deduce',lpath,cnt,basename)
   if cnt ~= 1 then quit("module(...) name deduction failed: base "..basename.." "..fname) end
   lpath = lpath:gsub(path.sep,'.')
   return M.name_of(lpath):gsub('%.init$','')
end

function M.find_existing_module (name, dname, searchfn)
   local fullpath,lua = searchfn(name)
   local mod = true
   if not fullpath then -- maybe it's a function reference?
      -- try again with the module part
      local  mpath,fname = M.split_dotted_name(name)
      if mpath then
         fullpath,lua = searchfn(mpath)
      else
         fullpath = nil
      end
      if not fullpath then
         return nil, "module or function '"..dname.."' not found on module path"
      else
         mod = fname
      end
   end
   if not lua then return nil, "module '"..name.."' is a binary extension" end
   return fullpath, mod
end

function M.lookup_existing_module_or_function (name, docpath)
   -- first look up on the Lua module path
   local fullpath, mod = M.find_existing_module(name,name,path.package_path)
   -- no go; but see if we can find it on the doc path
   if not fullpath then
      fullpath, mod = M.find_existing_module("ldoc.builtin." .. name,name,path.package_path)
--~       fullpath, mod = M.find_existing_module(name, function(name)
--~          local fpath = package.searchpath(name,docpath)
--~          return fpath,true  -- result must always be 'lua'!
--~       end)
   end
   return fullpath, mod -- `mod` can be the error message
end


--------- lexer tools -----

local tnext = lexer.skipws

local function type_of (tok) return tok[1] end
local function value_of (tok) return tok[2] end

-- This parses Lua formal argument lists. It will return a list of argument
-- names, which also has a comments field, which will contain any commments
-- following the arguments. ldoc will use these in addition to explicit
-- param tags.

function M.get_parameters (tok,endtoken,delim)
   tok = M.space_skip_getter(tok)
   local args = List()
   args.comments = {}
   local ltl = lexer.get_separated_list(tok,endtoken,delim)

   if not ltl or #ltl[1] == 0 then return args end -- no arguments

   local function set_comment (idx,tok)
      local text = value_of(tok):gsub('%s*$','')
      args.comments[args[idx]] = text
   end

   for i = 1,#ltl do
      --print('check',i,ltl[i],#ltl[i])
      local tl = ltl[i]
      if #tl > 0 then
      if type_of(tl[1]) == 'comment' then
         if i > 1 then set_comment(i-1,tl[1]) end
         if #tl > 1 then
            args:append(value_of(tl[2]))
         end
      else
         args:append(value_of(tl[1]))
      end
      if i == #ltl then
         local last_tok = tl[#tl]
         if #tl > 1 and type_of(last_tok) == 'comment' then
            set_comment(i,last_tok)
         end
      end
      end
   end

   return args
end

-- parse a Lua identifier - contains names separated by . and :.
function M.get_fun_name (tok,first)
   local res = {}
   local t,name
   if not first then
      t,name = tnext(tok)
   else
      t,name = 'iden',first
   end
   t,sep = tnext(tok)
   while sep == '.' or sep == ':' do
      append(res,name)
      append(res,sep)
      t,name = tnext(tok)
      t,sep = tnext(tok)
   end
   append(res,name)
   return table.concat(res),t,sep
end

-- space-skipping version of token iterator
function M.space_skip_getter(tok)
   return function ()
      local t,v = tok()
      while t and t == 'space' do
         t,v = tok()
      end
      return t,v
   end
end

function M.quote (s)
   return "'"..s.."'"
end

-- The PL Lua lexer does not do block comments
-- when used in line-grabbing mode, so this function grabs each line
-- until we meet the end of the comment
function M.grab_block_comment (v,tok,patt)
   local res = {v}
   repeat
      v = lexer.getline(tok)
      if v:match (patt) then break end
      append(res,v)
      append(res,'\n')
   until false
   res = table.concat(res)
   --print(res)
   return 'comment',res
end

local prel = path.normcase('/[^/]-/%.%.')


function M.abspath (f)
   local count
   local res = path.normcase(path.abspath(f))
   while true do
      res,count = res:gsub(prel,'')
      if count == 0 then break end
   end
   return res
end

function M.process_file_list (list, mask, operation, ...)
   local exclude_list = list.exclude and M.files_from_list(list.exclude, mask)
   local function process (f,...)
      f = M.abspath(f)
      if not exclude_list or exclude_list and exclude_list:index(f) == nil then
         operation(f, ...)
      end
   end
   for _,f in ipairs(list) do
      if path.isdir(f) then
         local files = List(dir.getallfiles(f,mask))
         for f in files:iter() do
            process(f,...)
         end
      elseif path.isfile(f) then
         process(f,...)
      else
         quit("file or directory does not exist: "..M.quote(f))
      end
   end
end

function M.files_from_list (list, mask)
   local excl = List()
   M.process_file_list (list, mask, function(f)
      excl:append(f)
   end)
   return excl
end



return tools
