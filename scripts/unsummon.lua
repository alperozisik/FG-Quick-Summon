local option = "QUICKSUMMON_WARN_UNSUMMON"
local pending, requests, last = {}, {}, nil
local nesting = 0
local window
local causes = {}
local context

function reason(effect)
  return causes[DB.getPath(effect)]
end

function mark(effect, why)
  if DB.getValue(effect,"qs_concentration_cast","")~=""
      or DB.getValue(effect,"qs_lifetime_timer",0)==1 then
    causes[DB.getPath(effect)] = why
  end
end

local function capture(node, excluded)
  local children = {}
  for name, child in pairs(DB.getChildren(node)) do
    if not (excluded and excluded[name]) then
      local kind = DB.getType(child)
      if kind == "node" or kind == nil then
        children[name] = {children=capture(child)}
      else
        children[name] = {kind=kind, values={DB.getValue(child)}}
      end
    end
  end
  return children
end

local function write(node, children, links)
  for name, field in pairs(children) do
    if field.children then
      write(DB.createChild(node, name), field.children, links)
    else
      local first, second = unpack(field.values)
      if type(first) == "string" then first = links[first] or first end
      if type(second) == "string" then second = links[second] or second end
      if field.kind == "windowreference" then
        DB.setValue(node, name, field.kind, first or "", second or "")
      elseif first ~= nil then
        DB.setValue(node, name, field.kind, first)
      end
    end
  end
end

local function snapshot(node)
  local path = DB.getPath(node)
  local sourcePath = DB.getValue(node, "qs_record", "")
  local record = DB.findNode(sourcePath)
  local entry = {
    path=path, sourcePath=sourcePath,
    caster=DB.getValue(node, "qs_owner", ""),
    pet=DB.getValue(node, "qs_pet", 0)==1,
    user=DB.getValue(node, "qs_assigned_user", ""),
    ct=capture(node, {active=true, tokenrefid=true, tokenrefnode=true, undodamage=true,
      qs_duration=true, qs_timer=true}),
    record=record and capture(record),
  }
  local token = CombatManager.getTokenFromCT(node)
  local map = token and token.getContainerNode()
  if map then
    local x,y = token.getPosition()
    entry.token = {map=DB.getPath(map), x=x, y=y, facing=token.getOrientation()}
  end
  return entry
end

local function remove(group)
  local saved = {}
  for _, item in ipairs(group) do
    local node = DB.findNode(item.path)
    if node and DB.getValue(node, "qs_cast", "") == item.cast then
      saved[#saved+1] = snapshot(node)
    end
  end
  if #saved == 0 then return end
  for _, entry in ipairs(saved) do
    local node = DB.findNode(entry.path)
    if node then CombatManager.deleteCombatant(node) end
  end
  last = saved
end

function undo()
  if not Session.IsHost then return end
  if not last then ChatManager.SystemMessage("Quick Summon: Nothing to restore."); return end
  local links, created = {}, {}
  for _, entry in ipairs(last) do
    local caster = DB.findNode(entry.caster)
    local owner = caster and DB.getOwner(caster) or ""
    local pet = entry.pet and caster and Pets and type(Pets.addCohort) == "function"
    local record
    if entry.record then
      local root = pet and DB.createChild(caster, "cohorts") or DB.createNode("npc")
      if root then record = DB.createChild(root) end
    end
    local node = (not entry.record or record) and CombatManager.createCombatantNode()
    if not node then
      if record then DB.deleteNode(record) end
      for _, item in ipairs(created) do
        DB.deleteNode(item.node)
        if item.record then DB.deleteNode(item.record) end
      end
      ChatManager.SystemMessage("Quick Summon: Could not restore the group. Undo is still available.")
      return
    end
    links[entry.path] = DB.getPath(node)
    if record and entry.sourcePath ~= "" then links[entry.sourcePath] = DB.getPath(record) end
    created[#created+1] = {node=node, record=record, entry=entry, pet=pet,
      user=(owner == entry.user and owner) or ""}
  end
  for _, item in ipairs(created) do
    local node, entry = item.node, item.entry
    if item.record then write(item.record, entry.record, links) end
    write(node, entry.ct, links)
    DB.setValue(node,"qs_pet","number",item.pet and 1 or 0)
    if not item.pet then
      local class, path=DB.getValue(node,"link","","")
      path=path or ""
      if path:find(".cohorts.",1,true) or (entry.pet and path~="") then
        DB.setValue(node,"link","windowreference",class,"")
      end
    end
    DB.setValue(node,"NPCowner","string",item.user)
    DB.setValue(node,"qs_assigned_user","string",item.user)
    if item.user ~= "" then
      DB.addHolder(node,item.user,true)
      if item.record then DB.addHolder(item.record,item.user,item.pet and true or false) end
    end
    local placement = entry.token
    local map = placement and DB.findNode(placement.map)
    if map then
      local token = CombatManager.addTokenFromCT(map,node,placement.x,placement.y)
      if token then
        token.setOrientation(placement.facing)
        TokenManager.linkToken(node,token)
        TokenManager.updateVisibility(node)
      end
    end
  end
  last = nil
  ChatManager.SystemMessage("Quick Summon: Restored "..#created.." summon(s).")
end

function describe()
  local group = requests[1]
  if not group then return "" end
  local lines = {}
  for _, item in ipairs(group) do lines[#lines+1] = item.name.." — "..item.reason end
  return table.concat(lines, "\n")
end

local function show()
  if #requests > 0 and not window then window = Interface.openWindow("quicksummon_unsummon", "") end
  if window then window.refresh() end
end

function decide(confirm)
  local group = table.remove(requests,1)
  if confirm and group then remove(group) end
  if #requests == 0 and window then
    local closing = window
    window = nil
    closing.close()
  else show() end
end

function closed()
  if not window then return end
  window = nil
  table.remove(requests,1)
  show()
end

local function flush()
  if nesting ~= 0 or #pending == 0 then return end
  local group = pending
  pending = {}
  if OptionsManager.isOption(option,"no") then remove(group)
  else requests[#requests+1] = group; show() end
end

function dismiss(node, why)
  local path = DB.getPath(node)
  local cast = DB.getValue(node,"qs_cast","")
  if cast == "" then return end
  for _, item in ipairs(pending) do
    if item.path == path and item.cast == cast then return end
  end
  for _, group in ipairs(requests) do
    for _, item in ipairs(group) do
      if item.path == path and item.cast == cast then return end
    end
  end
  DB.setValue(node,"qs_duration","string","")
  QuickSummonLifetime.clear(node)
  pending[#pending+1] = {path=path,cast=cast,name=DB.getValue(node,"name","Summon"),reason=why}
  flush()
end

function batch(fn,...)
  nesting = nesting+1
  local ok,result = pcall(fn,...)
  nesting = nesting-1
  flush()
  if not ok then error(result) end
  return result
end

function withReason(why,fn,...)
  local previous = context
  context = why
  local ok,result = pcall(batch,fn,...)
  context = previous
  if not ok then error(result) end
  return result
end

function onInit()
  if not Session.IsHost then return end
  OptionsManager.registerOption2(option,false,"Quick Summon","Warn before auto unsummon",
    "option_entry_cycler",{labels="No",values="no",baselabel="Yes",baseval="yes",default="yes"})
  Comm.registerSlashHandler("undounsummon",undo)
end

function onTabletopInit()
  if not Session.IsHost then return end
  local expire = ActionSave.expireConcentrationEffects
  ActionSave.expireConcentrationEffects = function(actor)
    if context then
      for _, info in ipairs(ActionSave.getConcentrationEffects(actor)) do
        mark(info.nodeEffect,context)
      end
    end
    return batch(expire,actor)
  end
  local save = ActionSave.applyConcentrationRoll
  ActionSave.applyConcentrationRoll = function(...)
    return withReason("Failed concentration save",save,...)
  end
  local cast = PowerManager5E.handlePowerConcOverride
  PowerManager5E.handlePowerConcOverride = function(...)
    return withReason("Started another concentration spell",cast,...)
  end
  local damage = ActionDamage.handleConcentrationOnDamage
  ActionDamage.handleConcentrationOnDamage = function(source,target,roll,data)
    local health = data and data.tHealth
    if health and ActorHealthManager.isDyingOrDeadStatus(health.sNewStatus) then
      return withReason("Caster fell to 0 HP or died",damage,source,target,roll,data)
    end
    return damage(source,target,roll,data)
  end
  local decrement = EffectManager.processEffectDecrementDuration
  EffectManager.processEffectDecrementDuration = function(data)
    local effect = data.nodeEffect
    if effect and EffectVarManager.getEffectVarFromNode(effect,"nDuration",0)==1 then
      mark(effect,"Duration expired")
    end
    return decrement(data)
  end
  local effects = EffectManager.processEffects
  EffectManager.processEffects = function(...) return batch(effects,...) end
end

function forget(path)
  causes[path] = nil
end
