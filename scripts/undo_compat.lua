-- 5e Undo clears the whole effect list before restoring it. For a transformed
-- actor that transient deletion can cause Polymorphism to replace the CT node.
local function shapeEffect(node)
  local label=DB.getValue(node,"label",""):lower()
  return label=="wild shape" or label:match("^wild shape%s*;")~=nil
end

local function isShaped(node)
  for _,effect in pairs(DB.getChildren(node,"effects")) do
    if shapeEffect(effect) then return true end
  end
  return false
end

local function restoreShapeDamage(path)
  local node=DB.findNode(path)
  local saved=node and DB.getChild(node,"undodamage")
  if not saved then
    ChatManager.SystemMessage("5e Undo: No damage snapshot on the current form.")
    return
  end
  local name=DB.getValue(node,"name","")
  -- Store paths, not databasenode handles that effect handlers could invalidate.
  local snapshotPath=DB.getPath(saved)
  local function stillCurrent()
    return DB.findNode(path) and DB.findNode(snapshotPath)
  end
  for _,field in ipairs({"hptotal","hptemp","wounds","deathsavefail","deathsavesuccess","status","arcanewardhp"}) do
    if not stillCurrent() then return end
    local fieldPath=snapshotPath.."."..field
    if DB.findNode(fieldPath) then DB.copyNode(fieldPath,path.."."..field) end
  end
  if not stillCurrent() then return end
  local current, baseline={},{}
  for id,effect in pairs(DB.getChildren(path..".effects")) do
    current[id]={path=DB.getPath(effect),keep=shapeEffect(effect) or
      DB.getValue(effect,"qs_concentration_cast","")~=""}
  end
  for id,effect in pairs(DB.getChildren(snapshotPath..".effects")) do
    baseline[id]={path=DB.getPath(effect),shape=shapeEffect(effect)}
  end
  for id,item in pairs(current) do
    if not stillCurrent() then return end
    if not item.keep and not baseline[id] and DB.findNode(item.path) then DB.deleteNode(item.path) end
  end
  for id,item in pairs(baseline) do
    if not stillCurrent() then return end
    if not item.shape and not (current[id] and current[id].keep) then
      DB.copyNode(item.path,path..".effects."..id)
    end
  end
  if not stillCurrent() then return end
  -- The legacy extension stores effects on other combatants separately.
  for id,effect in pairs(DB.getChildren(snapshotPath..".othereffects")) do
    local effectId,actorId=id:match("^(id%-%d%d%d%d%d)(id%-%d%d%d%d%d)$")
    local target=actorId and DB.findNode("combattracker.list."..actorId)
    if target and not shapeEffect(effect) then
      local targetPath=DB.getPath(target)..".effects."..effectId
      if not DB.findNode(targetPath) then DB.copyNode(effect,targetPath) end
    end
  end
  if not stillCurrent() then return end
  DB.deleteNode(snapshotPath)
  if OptionsManager.getOption("UNDO")=="yes" then
    Comm.deliverChatMessage({mode="system",text="Undo completed on "..name,icon="stv"})
  else
    ChatManager.SystemMessage("Undo completed on "..name)
  end
end

function onTabletopInit()
  if not Session.IsHost or not undodamage or type(undodamage.undo)~="function" then return end
  local original=undodamage.undo
  undodamage.undo=function(path)
    local node=DB.findNode(path)
    if not node then
      ChatManager.SystemMessage("5e Undo: The original Combat Tracker entry no longer exists.")
      return
    end
    if isShaped(node) then return restoreShapeDamage(path) end
    return original(path)
  end
end
