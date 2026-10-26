-- Every weapon module with a setup is in the loader's ORDER: the loader runs
-- setup only for the paths listed there, so a missing one installs no hooks.
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
local function read(path)
  local f=assert(io.open(root..path,"rb"));local s=f:read("a");f:close();return s
end
local order=read("components/loader.lua"):match("local ORDER = (%b{})")
assert(order,"the loader's ORDER")
local listed={}
for path in order:gmatch('"([^"]+)"') do listed[path]=true end
local missing={}
for path in read("weapons/index.lua"):gmatch('= "([^"]+)"') do
  local ok,source=pcall(read,path..".lua")
  if ok and (source:find("function [%w_]+%.setup%s*%(") or source:find("%.setup%s*=%s*function"))
    and not listed[path] then
    missing[#missing+1]=path
  end
end
table.sort(missing)
assert(#missing==0,"setup never runs, not in ORDER: "..table.concat(missing,", "))
print("  ok   every weapon module with a setup is in ORDER")
