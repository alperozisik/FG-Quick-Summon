local function find(fn,name,seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i); if not key then break end
    if key==name then return value end
    if type(value)=="function" then local v=find(value,name,seen); if v then return v end end
  end
end
local function replace(fn,name,value)
  for i=1,100 do
    local key=debug.getupvalue(fn,i); if not key then break end
    if key==name then debug.setupvalue(fn,i,value); return end
  end
  error("Missing upvalue "..name)
end
local pc={path="charsheet.pc",values={initresult=21}}
local power={path="charsheet.pc.powers.spell",values={}}
local active={values={initresult=13}}
local captured
DB={
  getPath=function(n) return n.path end,
  getChild=function(n,key) assert(n==power and key=="..."); return pc end,
  getValue=function(n,key,default) return n.values[key] or default end,
  getOwner=function() return "Player" end,
  findNode=function() end,
  setValue=function(n,key,kind,value) n.values[key]=value end,
}
CombatManager={getActiveCT=function() return active end}
local begin=find(QuickSummon.onInit,"begin")
assert(begin)
replace(begin,"profile",function() return {name="Summon Fey"} end)
replace(begin,"slotData",function() end)
replace(begin,"say",function() end)
replace(begin,"setupStage",function(cast) captured=cast end)
begin(pc,power,true)
assert(captured.durationInit==13,"Reaction must use active actor, not caster's 21")
active.values.initresult=7
assert(captured.durationInit==13,"Chooser must retain cast-time initiative")

-- Exact initiative is used for normal expiration; turn-end uses a 0.1 offset.
local function timer(endsTurn)
  local node={values={qs_cast_init=captured.durationInit,qs_expire_end=endsTurn and 1 or 0}}
  local result
  EffectManager={addEffectByTable=function(n,effect)
    assert(n==node); result=effect; return {path="effect"}
  end}
  QuickSummonLifetime.add(node,1)
  assert(result.nDuration==10 and result.sName=="Summoned Creature")
  return result
end
local startTimer=timer(false)
local endTimer=timer(true)
assert(startTimer.nInit==13)
assert(math.abs(endTimer.nInit-12.9)<0.000001)

-- Run CoreRPG's real initiative-crossing predicate (not a duplicate of it).
local decrements=0
EffectVarManager={getEffectVarFromNode=function(e,key,default) return e[key] or default end}
DB.getValue=function(e,key,default) if key=="isactive" then return 1 end; return default end
EffectManager={
  hasDuration=function() return true end,
  getInitDirection=function() return -1 end,
  processEffectDecrementDuration=function() decrements=decrements+1 end,
}
NativeTiming.processEffectExpire({nodeEffect=endTimer,nCurrentInit=14,nNewInit=13},false)
assert(decrements==0,"SW must survive entry into initiative 13")
NativeTiming.processEffectExpire({nodeEffect=endTimer,nCurrentInit=13,nNewInit=13},false)
assert(decrements==0,"SW must survive shared-turn entries at initiative 13")
NativeTiming.processEffectExpire({nodeEffect=endTimer,nCurrentInit=13,nNewInit=12},false)
assert(decrements==1,"SW decrements when leaving initiative 13")
NativeTiming.processEffectExpire({nodeEffect=startTimer,nCurrentInit=14,nNewInit=13},false)
assert(decrements==2,"Normal timers decrement when entering initiative 13")

local sw=QuickSummonRules.match("Spiritual Weapon",2)
assert(sw.expireEnd==true)
local notice,warn=QuickSummonRules.upcastNotice(sw,2)
assert(notice:find("Level 2: 1d8",1,true) and not warn)
notice,warn=QuickSummonRules.upcastNotice(sw,3)
assert(notice:find("same as level 2",1,true) and notice:find("Next increase: level 4",1,true) and warn)
for slot=2,9 do
  assert(QuickSummonRules.spiritualWeaponDice(slot)==({1,1,2,2,3,3,4,4})[slot-1])
end
