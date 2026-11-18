"""Regression check against the manager using Fantasy Grounds' Lua 5.1 runtime.

Run: python tests/test_auto_assign.py [path/to/lua5.1.dll]
The harness replaces FG services; it does not connect to a campaign or client.
"""

import ctypes
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
DLL = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    r"C:\Program Files\SmiteWorks\Fantasy Grounds\FantasyGrounds_Data\Plugins\x86_64\lua5.1.dll"
)
lua = ctypes.CDLL(str(DLL))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

harness = r'''
local function find(fn, name, seen)
  seen=seen or {}
  if seen[fn] then return end
  seen[fn]=true
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i)
    if not key then break end
    if key==name then return value end
    if type(value)=="function" then
      local result=find(value,name,seen)
      if result then return result end
    end
  end
end
local add=find(onCommand,"addCombatant")
assert(add,"Could not locate actual addCombatant")
local record,ct,character={},{},{}
local function replace(name,value)
  for i=1,100 do
    local key=debug.getupvalue(add,i)
    if not key then break end
    if key==name then debug.setupvalue(add,i,value); return end
  end
  error("Missing upvalue "..name)
end
replace("buildRecord",function() return record end)
replace("applyInitiative",function() end)
local values,holders,shares,opens,user,option,failWindow
DB={
  getPath=function(node) return node==record and "npc.clone" or "charsheet.caster" end,
  getOwner=function(node) assert(node==character); return user end,
  setValue=function(node,key,kind,value) assert(node==ct); values[key]=value end,
  addHolder=function(node,who,owns) holders[#holders+1]={node,who,owns} end,
}
CombatRecordManager={onRecordTypeEvent=function(kind,data)
  assert(kind=="npc" and data.nodeRecord==record); data.nodeCT=ct
end}
OptionsManager={isOption=function(key,value)
  assert(key=="QUICKSUMMON_AUTO_ASSIGN" and value=="on"); return option
end}
Interface={openWindow=function(class,node)
  assert(class=="npc" and node==ct,"Must share live CT record, not source clone")
  assert(values.NPCowner==user and #holders==2,"Grant access before sharing")
  opens=opens+1
  if failWindow then return end
  return {share=function(who) shares[#shares+1]=who end}
end}
local function check(enabled,owner,faction,expected,failed)
  values,holders,shares,opens={},{},{},0
  option,user,failWindow=enabled,owner,failed
  local result=add({character=character,id="cast",profile={faction=faction}}, {}, nil)
  assert(result==ct)
  assert(opens==expected)
  assert(#shares==(failed and 0 or expected))
  if expected==1 then
    assert(values.qs_assigned_user==user and values.NPCowner==user)
    assert(holders[1][1]==ct and holders[1][2]==user and holders[1][3]==true)
    assert(holders[2][1]==record and holders[2][2]==user and holders[2][3]==false)
    if not failed then assert(shares[1]==user) end
  else
    assert(#holders==0 and values.NPCowner==nil)
  end
end
check(true,"Alice","friend",1)
check(false,"Alice","friend",0)
check(true,"Alice","foe",0)
check(true,"Alice","neutral",0)
check(true,"","friend",0)
check(true,"Alice","friend",1,true)
'''
source = (ROOT / "scripts/manager.lua").read_bytes() + b"\n" + harness.encode()
state = lua.luaL_newstate()
try:
    lua.luaL_openlibs(state)
    status = lua.luaL_loadbuffer(state, source, len(source), b"auto_assign_regression")
    if not status:
        status = lua.lua_pcall(state, 0, 0, 0)
    if status:
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
print("PASS: 6 auto-assignment/share cases (FG Lua 5.1; mocked FG services)")
