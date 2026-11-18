local rules=QuickSummonRules
local p=rules.match("Conjure Elemental",5)
local function npc(name,cr,fullType)
  return {name=name,normalized=rules.normalize(name),cr=cr,creature="Elemental",fullType=fullType or "Elemental"}
end
assert(rules.eligibility(p,npc("Air Elemental",5),5,1))
assert(not rules.eligibility(p,npc("Water Elemental",5),5,1))
for option,element in ipairs(p.forms) do
  for other,name in ipairs(p.forms) do
    assert(rules.eligibility(p,npc(name.." Elemental",5),5,option)==(option==other))
  end
end
assert(not rules.eligibility(p,npc("Invisible Stalker",6),5,1))
assert(rules.eligibility(p,npc("Invisible Stalker",6),6,1))
assert(not rules.eligibility(p,npc("Invisible Stalker",6),6,4))
assert(rules.eligibility(p,npc("Galeb Duhr",6),6,2))
assert(rules.eligibility(p,npc("Azer",2),5,3))
assert(rules.eligibility(p,npc("Water Weird",3),5,4))
assert(rules.eligibility(p,npc("Gargoyle (Legacy)",2),5,2))
assert(not rules.eligibility(p,npc("Frost Salamander",9),9,3))
assert(not rules.eligibility(p,npc("Chwinga",0),5,1))
assert(rules.eligibility(p,npc("Custom Spirit",2,"Elemental (air)"),5,1))
assert(not rules.eligibility(p,npc("Air Impostor",2,"Elemental (water)"),5,1))
assert(not rules.eligibility(p,npc("Fairy Spirit",2),5,1))
assert(not rules.eligibility(p,npc("Wildfire Spirit",2),5,3))
for option=1,4 do
  assert(rules.eligibility(p,npc("Dust Mephit",0.5),5,option)==(option==1 or option==2))
  assert(rules.eligibility(p,npc("Steam Mephit",0.25),5,option)==(option==3 or option==4))
end
local swarm=npc("Air Elemental Swarm",2); swarm.isSwarm=true
assert(not rules.eligibility(p,swarm,5,1))
local template=npc("Air Elemental",2); template.isTemplate=true
assert(not rules.eligibility(p,template,5,1))
local demon=rules.match("Summon Greater Demon",4)
assert(rules.eligibility(demon,{creature="Fiend",fullType="Fiend (demon)",cr=5},5,1))
assert(not rules.eligibility(demon,{creature="Fiend",fullType="Fiend (devil)",cr=5},5,1))
-- Conjure Minor Elementals retains its broad elemental list (no element choice).
assert(rules.eligibility(rules.match("Conjure Minor Elementals",4),npc("Water Weird",3),5,1))

local function find(fn,name,seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i); if not key then break end
    if key==name then return value end
    if type(value)=="function" then local v=find(value,name,seen); if v then return v end end
  end
end
local candidates=find(QuickSummon.onInit,"getCandidates")
assert(candidates)
local records={}
local function add(id,name,cr,kind,version)
  records[id]={key="reference.npcdata."..id.."@TestModule",values={name=name,cr=cr,type=kind or "Elemental",version=version}}
end
add("air","Air Elemental","5")
add("water","Water Elemental","5")
add("stalker","Invisible Stalker","6")
add("dust","Dust Mephit","1/2")
add("custom","Unknown Spirit","2")
add("tagged","Custom Spirit","2","Elemental (air)")
add("new","Air Elemental 2024","5","Elemental","2024")
RecordDataManager={getDataPaths=function() return {"reference.npcdata"} end}
DB={
  getChildrenGlobal=function() return records end,
  getPath=function(n) return n.key end,
  getModule=function() return "TestModule" end,
  getValue=function(n,key,default) return n.values[key] or default end,
}
local function names(option,cap)
  local result={}
  for _,row in ipairs(candidates({profile=p,slot=cap,cap=cap,option=option})) do result[row.name]=true end
  return result
end
local air=names(1,5)
assert(air["Air Elemental"] and air["Dust Mephit"] and air["Custom Spirit"])
assert(not air["Water Elemental"] and not air["Invisible Stalker"] and not air["Unknown Spirit"])
assert(not air["Air Elemental 2024"])
assert(names(1,6)["Invisible Stalker"])
local water=names(4,5)
assert(water["Water Elemental"] and not water["Air Elemental"] and not water["Dust Mephit"])
