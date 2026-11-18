"""Regression check against the manager using Fantasy Grounds' Lua 5.1 runtime.

Run: python tests/test_auto_assign.py [path/to/lua5.1.dll]
The harness replaces FG services; it does not connect to a campaign or client.
"""

from pathlib import Path
from lua_runtime import run

ROOT = Path(__file__).resolve().parents[1]

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
local record,ct,character,pet={},{},{},{}
local deleted,petCalls,petMode,addFails,clone
local assignedRecord
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
  getPath=function(node) return node==record and "npc.clone" or node==pet and "charsheet.caster.cohorts.pet" or node==clone and "npc.detached" or "charsheet.caster" end,
  getValue=function(node,key,default)
    if node==ct then return values[key] or default end
    return default
  end,
  findNode=function(path)
    if path=="charsheet.caster.cohorts.pet" then return pet end
    if path=="npc.clone" then return record end
  end,
  deleteNode=function(node) deleted[#deleted+1]=node end,
  createNode=function(path) assert(path=="npc"); return {} end,
  createChild=function() return clone end,
  copyNode=function(src,dest) assert(src==pet and dest==clone) end,
  getOwner=function(node) assert(node==character); return user end,
  setValue=function(node,key,kind,value) assert(node==ct); values[key]=value end,
  addHolder=function(node,who,owns) holders[#holders+1]={node,who,owns} end,
}
CombatRecordManager={onRecordTypeEvent=function(kind,data)
  assert(kind=="npc" and data.nodeRecord==assignedRecord)
  if not addFails then data.nodeCT=ct end
end}
OptionsManager={isOption=function(key,value)
  assert(key=="QUICKSUMMON_AUTO_ASSIGN" and value=="on"); return option
end}
Interface={openWindow=function(class,node)
  assert(class=="npc" and node==(petMode and pet or ct),"Must share the live linked NPC record")
  assert(values.NPCowner==user and #holders==2,"Grant access before sharing")
  opens=opens+1
  if failWindow then return end
  return {share=function(who) shares[#shares+1]=who end}
end}
local function check(enabled,owner,faction,expected,failed,usePets)
  values,holders,shares,opens={},{},{},0
  option,user,failWindow=enabled,owner,failed
  deleted,petCalls,petMode={},0,usePets and enabled and faction=="friend"
  assignedRecord=petMode and pet or record
  if usePets then
    Pets={addCohort=function(caster,source)
      assert(caster==character and source==record)
      petCalls=petCalls+1
      return pet
    end}
  else Pets=nil end
  local result=add({character=character,id="cast",profile={faction=faction}}, {}, nil)
  assert(result==ct and values.locked==1)
  assert(opens==expected)
  assert(#shares==(failed and 0 or expected))
  if expected==1 then
    assert(values.qs_assigned_user==user and values.NPCowner==user)
    assert(holders[1][1]==ct and holders[1][2]==user and holders[1][3]==true)
    assert(holders[2][1]==assignedRecord and holders[2][2]==user and holders[2][3]==false)
    if not failed then assert(shares[1]==user) end
  else
    assert(#holders==0 and values.NPCowner==nil)
  end
  assert(petCalls==(petMode and 1 or 0))
  assert(values.qs_pet==(petMode and 1 or 0))
  assert(#deleted==(petMode and 1 or 0))
  if petMode then
    assert(deleted[1]==record and values.qs_record=="charsheet.caster.cohorts.pet")
  end
end
check(true,"Alice","friend",1)
check(false,"Alice","friend",0)
check(true,"Alice","foe",0)
check(true,"Alice","neutral",0)
check(true,"","friend",0)
check(true,"Alice","friend",1,true)
check(true,"Alice","friend",1,false,true)
check(false,"Alice","friend",0,false,true)
check(true,"Alice","foe",0,false,true)
check(true,"","friend",0,false,true)
-- Deleting a managed CT entry removes exactly its linked Pets record.
local cleanup=find(onInit,"onCombatantDeleted")
assert(cleanup)
check(true,"Alice","friend",1,false,true)
cleanup(ct)
assert(#deleted==2 and deleted[2]==pet)
-- Concentration hostility detaches the cohort into a private campaign NPC.
local detach=find(onInit,"detachPet")
assert(detach)
check(true,"Alice","friend",1,false,true)
clone={}
detach(ct)
assert(values.qs_pet==0 and values.qs_record=="npc.detached")
assert(#deleted==2 and deleted[2]==pet)
detach(ct)
assert(#deleted==2,"Repeated detachment must be harmless")
-- Failed CT insertion must not leak the cohort.
addFails=true
deleted,values,holders,shares,opens={},{},{},{},0
assert(add({character=character,id="cast",profile={faction="friend"}}, {}, nil)==nil)
assert(#deleted==2 and deleted[1]==record and deleted[2]==pet)
assert(opens==0 and #holders==0)
-- Newly created Spiritual Weapon keeps both non-threatening actor effects.
addFails=false
check(false,"Alice","friend",0)
local labels={}
EffectManager={addEffectByTable=function(node,data)
  assert(node==ct); labels[data.sName]=true
end}
assert(add({character=character,id="cast",profile={faction="friend"}}, {weapon=true}, nil)==ct)
assert(labels.Incapacitated and labels.NOREACTION and values.locked==1)
'''
source = (ROOT / "scripts/manager.lua").read_bytes() + b"\n" + harness.encode()
run(source, "auto_assign_regression")
print("PASS: auto assignment, optional Pets, removal, hostile detachment and failed insertion (FG Lua 5.1; mocked FG services)")
