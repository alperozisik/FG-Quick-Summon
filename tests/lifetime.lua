local nodes,combatants,handlers={},{},{}
local serial,removed,baseRests=0,0,0
local warn=false
local shown
OptionsManager={isOption=function(_,choice) return choice=="no" and not warn end}
ChatManager={SystemMessage=function() end}
Interface={openWindow=function()
  shown={refresh=function() end,close=function() QuickSummonUnsummon.closed() end}
  return shown
end}
local function make(path,parent)
  local node={path=path,parent=parent,values={},effects={}}
  nodes[path]=node
  return node
end
DB={
  getPath=function(node) return node.path end,
  getValue=function(node,key,default) if not key then return node.value end; return node.values[key] or default end,
  setValue=function(node,key,kind,value) node.values[key]=value end,
  findNode=function(path) return nodes[path] end,
  getType=function(n) return n.kind or "node" end,
  getChildren=function(n,key)
    if type(n)=="string" then n=nodes[n] end
    local fields={}
    if not n then return fields end
    if key=="effects" then
      for _,e in ipairs(n.effects) do fields[e.path:match("[^.]+$")]=e end
      return fields
    end
    for k,v in pairs(n.values) do
      fields[k]={kind=type(v),values={},value=v}
    end
    if #n.effects>0 then
      -- Branch values are represented as child nodes in this fake DB.
      fields.effects={kind="node",values={},effects=n.effects,isEffectList=true}
    end
    if n.isEffectList then
      for _,e in ipairs(n.effects) do fields[e.path:match("[^.]+$")]=e end
      fields.effects=nil
    end
    return fields
  end,
  createChild=function(n,key)
    if key=="effects" then return {path=n.path..".effects",owner=n} end
    local child=make(n.path.."."..key,n.owner)
    if n.owner then n.owner.effects[#n.owner.effects+1]=child end
    return child
  end,
  getChild=function(node,key) assert(key=="..."); return node.parent end,
  getChildList=function(node,key) assert(key=="effects"); return node.effects end,
  addHandler=function(path,event,fn)
    handlers[#handlers+1]={path,event,fn}
  end,
}
local function delete(node)
  if not nodes[node.path] then return end
  if node.parent then
    for _,h in ipairs(handlers) do
      if h[1]=="combattracker.list.*.effects.*" and h[2]=="onDelete" then h[3](node) end
    end
    for i,v in ipairs(node.parent.effects) do
      if v==node then table.remove(node.parent.effects,i); break end
    end
  end
  nodes[node.path]=nil
end
DB.deleteNode=delete
Session={IsHost=true}
ActorManager={resolveActor=function(n) return n end,getCreatureNode=function(n) return n.creature or n end}
ActionCore={getRestDuration=function(kind) return kind=="short" and 600 or 14400 end}
EffectVarManager={
  getEffectVarFromNode=function(n,key,default) return n.values[key] or default end,
  setEffectVarToNode=function(n,key,value) n.values[key]=value end,
}
EffectManager={
  addEffectByTable=function(node,data)
    serial=serial+1
    local e=make(node.path..".effects.e"..serial,node)
    e.values.nInit=data.nInit or 0
    e.values.sName=data.sName
    e.values.nDuration=data.nDuration*(data.sUnits=="minute" and 10 or 1)
    node.effects[#node.effects+1]=e
    return e
  end,
  expireEffectByNode=function(actor,e) delete(e) end,
}
CombatManager={
  getCombatantNodes=function() return combatants end,
  getTokenFromCT=function() end,
  createCombatantNode=function()
    serial=serial+1
    local node=make("combattracker.list.restored"..serial)
    combatants[node.path]=node
    return node
  end,
  deleteCombatant=function(node)
    removed=removed+1
    local effects={unpack(node.effects)}
    for _,e in ipairs(effects) do delete(e) end
    nodes[node.path]=nil
    combatants[node.path]=nil
    local record=nodes[node.values.qs_record]
    if record then delete(record) end
  end,
}
EffectManagerD20={
  clearRestExpiringEffect=function(e,actor,kind)
    baseRests=baseRests+1
    local remaining=e.values.nDuration
    if remaining and remaining>0 then
      remaining=remaining-ActionCore.getRestDuration(kind)
      if remaining<=0 then delete(e) else e.values.nDuration=remaining end
    end
  end,
}
EffectManagerD20.clearRestExpiringEffectsByActor=function(actor,kind)
  local effects={unpack(actor.effects)}
  for _,e in ipairs(effects) do
    if nodes[e.path] then EffectManagerD20.clearRestExpiringEffect(e,actor,kind) end
  end
end
CombatManager.rest=function(kind)
  local snapshot={}
  for _,n in pairs(combatants) do snapshot[#snapshot+1]=n end
  table.sort(snapshot,function(a,b) return (a.values.qs_cast or "")>(b.values.qs_cast or "") end)
  for _,n in ipairs(snapshot) do
    assert(nodes[n.path],"Party rest must not iterate deleted combatants")
    EffectManagerD20.clearRestExpiringEffectsByActor(n,kind)
  end
end
local baseActorRest=EffectManagerD20.clearRestExpiringEffectsByActor
local baseEffectRest=EffectManagerD20.clearRestExpiringEffect
QuickSummonLifetime.onInit()
local function reset()
  nodes,combatants={},{}
  removed,baseRests=0,0
end
local function caster()
  local char=make("charsheet.caster")
  local ct=make("combattracker.list.caster")
  ct.creature=char
  combatants[ct.path]=ct
  return char,ct
end
local function summon(minutes,name)
  local n=make("combattracker.list."..(name or "summon"))
  n.values.qs_cast="cast"
  n.values.qs_owner="charsheet.caster"
  combatants[n.path]=n
  QuickSummonLifetime.add(n,minutes)
  return n,nodes[n.values.qs_timer]
end

-- Timer expiration and explicit timer removal both dismiss exactly one summon.
reset()
local n,e=summon(1)
assert(e.values.sName=="Summoned Creature" and e.values.nDuration==10)
QuickSummonLifetime.add(n,1)
assert(#n.effects==1,"Do not duplicate timers")
delete(e)
assert(removed==1 and not nodes[n.path])
reset(); n,e=summon(1)
CombatManager.deleteCombatant(n)
assert(removed==1,"CT removal must not recursively remove itself")

-- Unlinking for hostility removes the timer without dismissing the creature.
reset(); n,e=summon(60)
QuickSummonLifetime.clear(n)
assert(removed==0 and nodes[n.path] and not nodes[e.path] and n.values.qs_timer=="")

-- Individual caster rest advances the summon by one hour.
reset(); local char,pc=caster(); n,e=summon(120)
EffectManagerD20.clearRestExpiringEffectsByActor(pc,"short")
assert(e.values.nDuration==600 and removed==0)
EffectManagerD20.clearRestExpiringEffectsByActor(pc,"short")
assert(removed==1 and not nodes[n.path])

-- Party rest includes PC and summon, but advances a given timer just once.
reset(); char,pc=caster(); n,e=summon(120)
CombatManager.rest("short")
assert(e.values.nDuration==600)
CombatManager.rest("short")
assert(removed==1)

-- Long rest is eight hours, not CoreRPG's default 24 hours.
reset(); char,pc=caster(); n,e=summon(1440)
CombatManager.rest("long")
assert(e.values.nDuration==9600 and removed==0)
CombatManager.rest("long")
assert(e.values.nDuration==4800)
CombatManager.rest("long")
assert(removed==1)

-- Exact eight-hour duration expires, and a one-hour-one-minute steed retains a minute.
reset(); char,pc=caster(); n,e=summon(480)
CombatManager.rest("long"); assert(removed==1)
reset(); char,pc=caster(); n,e=summon(61)
CombatManager.rest("short"); assert(e.values.nDuration==10 and removed==0)

-- Summons without a duration get no timer; unrelated effects use the native handler.
reset(); char,pc=caster(); n,e=summon(nil)
assert(not e)
e=EffectManager.addEffectByTable(pc,{sName="Unrelated",nDuration=20000})
CombatManager.rest("long")
assert(e.values.nDuration==5600 and baseRests==1)

-- Migrate the actual remaining duration; lock CT and Pets sheets and repair SW.
reset(); char,pc=caster(); n,e=summon(nil)
n.values.qs_unique="spiritualweapon"
local pet=make("charsheet.caster.cohorts.pet")
n.values.qs_record=pet.path
local source=EffectManager.addEffectByTable(pc,{sName="Spiritual Weapon (Quick Summon)",nDuration=4})
n.values.qs_duration=source.path
source.values.qs_concentration_cast=n.values.qs_cast
QuickSummonLifetime.onTabletopInit()
e=nodes[n.values.qs_timer]
assert(e.values.nDuration==4 and n.values.locked==1 and pet.values.locked==1)
local function conditions()
  local count=0
  for _,fx in ipairs(n.effects) do if fx.values.sName=="Incapacitated" then count=count+1 end end
  return count
end
assert(conditions()==1)
QuickSummonLifetime.onTabletopInit()
assert(conditions()==1 and e.values.nDuration==4,"Reload must not reset time or duplicate conditions")

-- Rest-expired linked concentration is marked natural before its delete handler runs.
reset(); char,pc=caster(); n,e=summon(60)
source=EffectManager.addEffectByTable(pc,{sName="Conjure Elemental (C)",nDuration=600})
n.values.qs_duration=source.path
source.values.qs_concentration_cast=n.values.qs_cast
local observed
handlers[#handlers+1]={"combattracker.list.*.effects.*","onDelete",function(fx)
  if fx==source then observed=fx.values.nDuration end
end}
CombatManager.rest("short")
assert(observed and not nodes[source.path] and removed==1)

-- Exercise the real manager's concentration-loss branch with an existing timer.
local function find(fn,name,seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i); if not key then break end
    if key==name then return value end
    if type(value)=="function" then local v=find(value,name,seen); if v then return v end end
  end
end
local concentrationDeleted=find(QuickSummon.onInit,"onEffectDeleted")
assert(concentrationDeleted)
reset(); char,pc=caster(); n,e=summon(60)
n.values.qs_break_hostile=1
n.values.qs_assigned_user=""
source=EffectManager.addEffectByTable(pc,{sName="Conjure Elemental (C)",nDuration=600})
n.values.qs_duration=source.path
source.values.qs_concentration_cast=n.values.qs_cast
DB.getOwner=function() return "" end
Comm={deliverChatMessage=function() end}
QuickSummonRules={match=function() end}
concentrationDeleted(source)
assert(n.values.friendfoe=="foe" and n.values.qs_timer=="" and n.values.qs_duration=="")
assert(nodes[n.path] and not nodes[e.path] and removed==0)

-- The host command advances a player's summons even without NPC ownership.
reset(); char,pc=caster(); n,e=summon(120)
QuickSummonLifetime.restCaster(char,"short")
assert(e.values.nDuration==600)
QuickSummon.notifySummonRest(char,"short")
assert(removed==1,"Manager rest command must reach the host lifetime handler")

-- Rest must break Conjure Elemental/Fey control before expiring their timers,
-- including the worst-case party iteration order: summon before caster.
handlers[#handlers+1]={"combattracker.list.*.effects.*","onDelete",concentrationDeleted}
for _,kind in ipairs({"short","long"}) do
  for _,mode in ipairs({"party","caster","player"}) do
    reset(); char,pc=caster(); n,e=summon(60)
    n.values.qs_break_hostile=1
    source=EffectManager.addEffectByTable(pc,{sName="Conjure Elemental (C)",nDuration=600})
    n.values.qs_duration=source.path
source.values.qs_concentration_cast=n.values.qs_cast
    if mode=="party" then CombatManager.rest(kind)
    elseif mode=="caster" then EffectManagerD20.clearRestExpiringEffectsByActor(pc,kind)
    else QuickSummonLifetime.restCaster(char,kind) end
    assert(nodes[n.path] and removed==0,"Rest must retain the hostile summon")
    assert(n.values.friendfoe=="foe" and n.values.qs_timer=="" and n.values.qs_duration=="")
    assert(not nodes[e.path] and not nodes[source.path])
  end
end

-- Wild Shape copies the cast identity to a new CT effect before deleting the old one.
reset(); char,pc=caster(); n,e=summon(60)
source=EffectManager.addEffectByTable(pc,{sName="Summon Elemental (C)",nDuration=580})
source.values.qs_concentration_cast="cast"
n.values.qs_duration=source.path
local form=make("combattracker.list.form")
combatants[form.path]=form
form.values.polymorphism_originator=char.path
local moved=EffectManager.addEffectByTable(form,{sName="Summon Elemental (C)",nDuration=580})
moved.values.qs_concentration_cast="cast"
delete(source)
assert(n.values.qs_duration==moved.path and removed==0 and e.values.nDuration==600)
local normal=make("combattracker.list.normal")
combatants[normal.path]=normal
normal.values.link=char.path
local getValue=DB.getValue
DB.getValue=function(node,key,...)
  if key=="link" and node==normal then return "charsheet",char.path end
  return getValue(node,key,...)
end
local returned=EffectManager.addEffectByTable(normal,{sName="Summon Elemental (C)",nDuration=570})
returned.values.qs_concentration_cast="cast"
delete(moved)
assert(n.values.qs_duration==returned.path and removed==0)
QuickSummonUnsummon.mark(returned,"Failed concentration save")
warn=true
delete(returned)
DB.getValue=getValue
assert(QuickSummonUnsummon.describe():find("Failed concentration save",1,true))
assert(nodes[n.path] and n.values.qs_timer=="")
QuickSummonUnsummon.decide(false)
assert(nodes[n.path] and removed==0)

-- Explicit bulk confirmation, then one undo restores HP, initiative and effects.
reset(); char,pc=caster(); n,e=summon(60,"wolf")
local other=summon(60,"hawk")
n.values.wounds=7
n.values.initresult=13
EffectManager.addEffectByTable(n,{sName="Prone",nDuration=0})
QuickSummonUnsummon.batch(function()
  QuickSummonUnsummon.dismiss(n,"Duration expired")
  QuickSummonUnsummon.dismiss(other,"Duration expired")
end)
assert(nodes[n.path] and nodes[other.path] and removed==0)
assert(QuickSummonUnsummon.describe():match("\n"))
QuickSummonUnsummon.decide(true)
assert(removed==2)
QuickSummonUnsummon.undo()
local restored=0
for _,node in pairs(combatants) do
  if node.values.qs_cast=="cast" then
    restored=restored+1
    assert(not node.values.qs_duration and not node.values.qs_timer)
    if node.values.wounds==7 then
      assert(node.values.initresult==13 and #node.effects==1 and node.effects[1].values.sName=="Prone")
    end
  end
end
assert(restored==2)
QuickSummonUnsummon.undo()
local total=0
for _ in pairs(combatants) do total=total+1 end
assert(total==3,"The group is restored only once")
warn=false

-- Player-side rest forwards once; managed effects are not also decremented locally.
reset(); char,pc=caster(); n,e=summon(120)
source=EffectManager.addEffectByTable(pc,{sName="Summon Fey (C)",nDuration=1200})
n.values.qs_duration=source.path
source.values.qs_concentration_cast=n.values.qs_cast
local unrelated=EffectManager.addEffectByTable(pc,{sName="Unrelated",nDuration=2000})
EffectManagerD20.clearRestExpiringEffectsByActor=baseActorRest
EffectManagerD20.clearRestExpiringEffect=baseEffectRest
Session.IsHost=false
local forwarded=0
QuickSummon.notifySummonRest=function(character,kind)
  assert(character==char and kind=="short"); forwarded=forwarded+1
end
QuickSummonLifetime.onInit()
EffectManagerD20.clearRestExpiringEffectsByActor(pc,"short")
assert(forwarded==1 and e.values.nDuration==1200 and source.values.nDuration==1200)
assert(unrelated.values.nDuration==1400)

-- 5e Undo: restore damage without deleting the Wild Shape control effect.
Session.IsHost=true
local path="combattracker.list.id-00021"
local snap=path..".undodamage"
local tracker,shape,condition={}, {label="Wild Shape"}, {label="Prone"}
local legacyCalls=0
local entries={[path]=tracker,[snap]={},[snap..".wounds"]={value=0},
  [path..".effects.id-00001"]=shape,[path..".effects.id-00002"]=condition}
local copiedWounds=false
DB={
  findNode=function(key) return entries[key] end,
  getChild=function(node,key) if node==tracker and key=="undodamage" then return entries[snap] end end,
  getPath=function(node)
    for key,val in pairs(entries) do if val==node then return key end end
  end,
  getValue=function(node,key,default) return node[key] or default end,
  getChildren=function(node,field)
    if (node==tracker and field=="effects") or node==path..".effects" then
      return {["id-00001"]=shape,["id-00002"]=entries[path..".effects.id-00002"]}
    elseif node==snap..".effects" then
      return {["id-00001"]={label="Wild Shape"}}
    end
    return {}
  end,
  copyNode=function(src,dst)
    assert(src==snap..".wounds" and dst==path..".wounds"); copiedWounds=true
  end,
  deleteNode=function(key)
    assert(key~=path..".effects.id-00001","Wild Shape effect must survive the entire undo")
    entries[key]=nil
  end,
}
OptionsManager.getOption=function() return "no" end
undodamage={undo=function() legacyCalls=legacyCalls+1 end}
QuickSummonUndoCompat.onTabletopInit()
undodamage.undo(path)
assert(copiedWounds and entries[path..".effects.id-00001"]==shape)
assert(not entries[snap] and not entries[path..".effects.id-00002"] and legacyCalls==0)
undodamage.undo("combattracker.list.deleted")
assert(legacyCalls==0,"Do not pass a stale CT link to the original undo handler")
entries[path..".effects.id-00001"]=nil
DB.getChildren=function() return {} end
undodamage.undo(path)
assert(legacyCalls==1,"Leave ordinary undo on its normal path")
