local deleting = {}
local restSeen
local deferredDeletes

function add(node, minutes, rounds, initiative)
  if not node or (not minutes and not rounds) then return end
  if DB.findNode(DB.getValue(node,"qs_timer","")) then return end
  if initiative==nil then
    initiative=DB.getValue(node,"qs_cast_init",0)
    if DB.getValue(node,"qs_expire_end",0)==1 then initiative=initiative-0.1 end
  end
  local effect=EffectManager.addEffectByTable(node,{
    sName="Summoned Creature", nDuration=rounds or minutes*10, nInit=initiative, bSkipAnnounce=true,
  })
  if effect then DB.setValue(node,"qs_timer","string",DB.getPath(effect)) end
end

function clear(node)
  local path=DB.getValue(node,"qs_timer","")
  -- Unlink before deleting: removing control must not dismiss a hostile creature.
  DB.setValue(node,"qs_timer","string","")
  local effect=DB.findNode(path)
  if effect then DB.deleteNode(effect) end
end

local function onTimerDeleted(effect)
  local node=DB.getChild(effect,"...")
  if not node or DB.getValue(node,"qs_cast","")=="" then return end
  local path=DB.getPath(node)
  if deleting[path] or DB.getValue(node,"qs_timer","")~=DB.getPath(effect) then return end
  DB.setValue(node,"qs_timer","string","")
  CombatManager.deleteCombatant(node)
end

local function restRounds(kind)
  if kind=="short" then return 600 end
  if kind=="long" or kind=="overnight" then return 4800 end
  return ActionCore.getRestDuration(kind)
end

local function advanceTimer(effect, actor, kind)
  local path=DB.getPath(effect)
  if restSeen and restSeen[path] then return end
  if restSeen then restSeen[path]=true end
  local remaining=EffectVarManager.getEffectVarFromNode(effect,"nDuration",0)
  if remaining<=0 then return end
  remaining=remaining-restRounds(kind)
  if remaining>0 then
    EffectVarManager.setEffectVarToNode(effect,"nDuration",remaining)
  else
    -- A rest can expire an effect while its pre-rest duration is still stored.
    -- The concentration handler must recognize this as natural expiration.
    EffectVarManager.setEffectVarToNode(effect,"nDuration",1)
    EffectManager.expireEffectByNode(actor,effect)
  end
end

local function isManagedEffect(effect)
  local path=DB.getPath(effect)
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if DB.getValue(node,"qs_timer","")==path or DB.getValue(node,"qs_duration","")==path then
      return true
    end
  end
  return false
end

local function advanceOwned(actor,kind,includeSource)
  local caster=ActorManager.getCreatureNode(ActorManager.resolveActor(actor))
  local ownerPath=caster and DB.getPath(caster) or ""
  local timers,sources={},{}
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if ownerPath~="" and DB.getValue(node,"qs_owner","")==ownerPath then
      local effect=DB.findNode(DB.getValue(node,"qs_timer",""))
      if effect then timers[#timers+1]={effect,ActorManager.resolveActor(node)} end
      if includeSource then
        local source=DB.findNode(DB.getValue(node,"qs_duration",""))
        if source then sources[DB.getPath(source)]=source end
      end
    end
  end
  for _,timer in ipairs(timers) do advanceTimer(timer[1],timer[2],kind) end
  for _,source in pairs(sources) do advanceTimer(source,actor,kind) end
end

local function breakRestConcentration(actor)
  local caster=ActorManager.getCreatureNode(ActorManager.resolveActor(actor))
  local ownerPath=caster and DB.getPath(caster) or ""
  local sources={}
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if ownerPath~="" and DB.getValue(node,"qs_owner","")==ownerPath
        and DB.getValue(node,"qs_break_hostile",0)==1 then
      local source=DB.findNode(DB.getValue(node,"qs_duration",""))
      if source then sources[DB.getPath(source)]=source end
    end
  end
  for _,source in pairs(sources) do
    -- Rest ends control before elapsed-time expiration. The creature stays hostile.
    DB.setValue(source,"qs_rest_break","number",1)
    EffectManager.expireEffectByNode(DB.getChild(source,"..."),source)
  end
end

function restCaster(character,kind)
  if not Session.IsHost then return end
  local outer=restSeen
  restSeen=restSeen or {}
  breakRestConcentration(character)
  advanceOwned(character,kind,true)
  restSeen=outer
end

function onInit()
  if not Session.IsHost then
    -- Player-sheet rest runs on the client. Ask the host to advance managed
    -- effects, including summons the player does not control, exactly once.
    local normalEffectRest=EffectManagerD20.clearRestExpiringEffect
    EffectManagerD20.clearRestExpiringEffect=function(effect,actor,kind)
      if isManagedEffect(effect) then return end
      return normalEffectRest(effect,actor,kind)
    end
    local normalActorRest=EffectManagerD20.clearRestExpiringEffectsByActor
    EffectManagerD20.clearRestExpiringEffectsByActor=function(actor,kind)
      local character=ActorManager.getCreatureNode(ActorManager.resolveActor(actor))
      QuickSummon.notifySummonRest(character,kind)
      return normalActorRest(actor,kind)
    end
    return
  end
  DB.addHandler("combattracker.list.*.effects.*","onDelete",onTimerDeleted)

  local normalDelete=CombatManager.deleteCombatant
  CombatManager.deleteCombatant=function(node)
    local path=DB.getPath(node)
    if deleting[path] then return end
    if deferredDeletes then deferredDeletes[path]=node; return end
    deleting[path]=true
    local ok,result=pcall(normalDelete,node)
    deleting[path]=nil
    if not ok then error(result) end
    return result
  end

  local normalEffectRest=EffectManagerD20.clearRestExpiringEffect
  EffectManagerD20.clearRestExpiringEffect=function(effect,actor,kind)
    local node=DB.getChild(effect,"...")
    if node and DB.getValue(node,"qs_timer","")==DB.getPath(effect) then
      -- A party rest can visit the summon before its caster. Let the caster's
      -- rest break concentration before this timer can dismiss the creature.
      if deferredDeletes and DB.getValue(node,"qs_break_hostile",0)==1
          and DB.findNode(DB.getValue(node,"qs_duration","")) then return end
      return advanceTimer(effect,actor,kind)
    end
    -- Keep the caster's linked concentration timer on the same rest clock.
    local path=DB.getPath(effect)
    for _,summon in pairs(CombatManager.getCombatantNodes()) do
      if DB.getValue(summon,"qs_duration","")==path then
        return advanceTimer(effect,actor,kind)
      end
    end
    return normalEffectRest(effect,actor,kind)
  end

  local normalActorRest=EffectManagerD20.clearRestExpiringEffectsByActor
  EffectManagerD20.clearRestExpiringEffectsByActor=function(actor,kind)
    local outer=restSeen
    restSeen=restSeen or {}
    -- Apply the same elapsed time to owned summons when only their caster rests.
    -- Process first: caster concentration expiry can delete summons during rest.
    breakRestConcentration(actor)
    advanceOwned(actor,kind,false)
    local ok,result=pcall(normalActorRest,actor,kind)
    restSeen=outer
    if not ok then error(result) end
    return result
  end

  local normalPartyRest=CombatManager.rest
  CombatManager.rest=function(...)
    local outer=restSeen
    local outerDeletes=deferredDeletes
    restSeen=restSeen or {}
    deferredDeletes=deferredDeletes or {}
    local ok,result=pcall(normalPartyRest,...)
    local pending=deferredDeletes
    deferredDeletes=outerDeletes
    restSeen=outer
    -- The ruleset iterates a snapshot during party rest. Remove NPCs afterwards.
    if not outerDeletes then
      for _,node in pairs(pending) do CombatManager.deleteCombatant(node) end
    end
    if not ok then error(result) end
    return result
  end
end

function onTabletopInit()
  if not Session.IsHost then return end
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if DB.getValue(node,"qs_cast","")~="" then
      DB.setValue(node,"locked","number",1)
      local record=DB.findNode(DB.getValue(node,"qs_record",""))
      if record then DB.setValue(record,"locked","number",1) end
      if DB.getValue(node,"qs_unique","")=="spiritualweapon" then
        local found=false
        for _,effect in ipairs(DB.getChildList(node,"effects")) do
          local label=EffectVarManager.getEffectVarFromNode(effect,"sName","")
          for component in label:gmatch("[^;]+") do
            if component:lower():match("^%s*incapacitated%s*$") then found=true end
          end
        end
        if not found then
          EffectManager.addEffectByTable(node,{sName="Incapacitated",nDuration=0,bSkipAnnounce=true})
        end
      end
      -- Migrate existing summons using the remaining rounds, never a fresh duration.
      if DB.getValue(node,"qs_timer","")=="" then
        local source=DB.findNode(DB.getValue(node,"qs_duration",""))
        if source then
          local rounds=EffectVarManager.getEffectVarFromNode(source,"nDuration",0)
          if rounds>0 then
            QuickSummonLifetime.add(node,nil,rounds,EffectVarManager.getEffectVarFromNode(source,"nInit",0))
          end
        end
      end
    end
  end
end
