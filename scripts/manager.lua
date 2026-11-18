local casts = {}
local pendingViews = {}
local nextCast = 0
local serial = 0
local commandField = "quicksummon_command"
local viewRoot = "quicksummon_views"
local notifyType = "quicksummon_view"
local autoAssignOption = "QUICKSUMMON_AUTO_ASSIGN"
local normalUse, normalAction, normalAddInitiative

local function spellIconKey(name)
  return QuickSummonRules.normalize(name):gsub(" ","_")
end

local function say(message, spell)
  local profile=spell and QuickSummonRules.match(spell)
  local icon=profile and "qs_spell_"..spellIconKey(profile.name)
  Comm.deliverChatMessage({font="narratorfont", text="Quick Summon: "..message, icon=icon})
end

local function owner(node)
  return DB.getOwner(node) or ""
end

local function profile(node)
  if not node or OptionsManager.isOption("GAVE","2024") then return end
  if tostring(DB.getValue(node,"version","")) == "2024" then return end
  local path = DB.getPath(node)
  if not path:match("^charsheet%.[^.]+%.powers%.[^.]+$") then return end
  return QuickSummonRules.match(DB.getValue(node,"name",""),tonumber(DB.getValue(node,"level",0)))
end

function isManagedSpell(node)
  return profile(node)~=nil
end

local function slotData(cast)
  local p = cast.profile
  local character = cast.character
  local highest, first, available = p.level, nil, {}
  for level=p.level,9 do
    local remaining, maximum = 0, 0
    for _,kind in ipairs({"spellslots","pactmagicslots"}) do
      local path = "powermeta."..kind..level
      local cap = DB.getValue(character,path..".max",0)
      maximum = maximum+cap
      remaining = remaining+math.max(0,cap-DB.getValue(character,path..".used",0))
    end
    if maximum > 0 then highest = level end
    available[level] = remaining
    if remaining > 0 and not first then first=level end
  end
  cast.available, cast.highest = available, highest
  cast.slot = cast.slot or first or p.level
end

local function actorRecord(cast)
  return ActorManager.resolveActor(cast.character)
end

local function casterCT(cast)
  return ActorManager.getCTNode(actorRecord(cast))
end

local function hasActiveInitiative(node)
  return node and DB.getChild(node,"initresult") and
    (DB.getValue(node,"initresult",0) ~= 0 or CombatManager.getActiveCT() ~= nil)
end

local function catalog()
  local result, seen = {}, {}
  for _,path in ipairs(RecordDataManager.getDataPaths("npc")) do
    for _,node in pairs(DB.getChildrenGlobal(path)) do
      local key = DB.getPath(node)
      local name = DB.getValue(node,"name","")
      if (DB.getModule(node) or "")~="" and not seen[key] and name~=""
          and tostring(DB.getValue(node,"version",""))~="2024" then
        seen[key]=true
        local fullType = DB.getValue(node,"type","")
        local creature = fullType:match("^%s*([%a]+)") or fullType
        local normalized = QuickSummonRules.normalize(name)
        local cr = QuickSummonRules.crValue(DB.getValue(node,"cr",""))
        result[#result+1] = {
          key=key, name=name, normalized=normalized, creature=creature, fullType=fullType,
          cr=cr, crLabel=cr and QuickSummonRules.crText(cr) or "-",
          isSwarm=fullType:lower():find("swarm",1,true) ~= nil or normalized:match("^swarm of ") ~= nil,
          isTemplate=DB.getValue(node,"summon",0)==1 or normalized:match(" spell lv[el]+ %d+$")~=nil
            or normalized:match(" scroll lv[el]+ %d+$")~=nil,
        }
      end
    end
  end
  table.sort(result,function(a,b)
    if a.normalized~=b.normalized then return a.normalized<b.normalized end
    return a.key<b.key
  end)
  return result
end

local function undeadOptions(slot)
  if slot==9 then return {Ghoul=6,Ghast=3,Wight=3,Mummy=2} end
  if slot==8 then return {Ghoul=5,Ghast=2,Wight=2} end
  return {Ghoul=slot-3}
end

local function objectCost(npc)
  local node = DB.findNode(npc.key)
  local size = DB.getValue(node,"size",""):lower()
  return ({tiny=1,small=1,medium=2,large=4,huge=8})[size]
end

local function getCandidates(cast)
  local p, rows, seen = cast.profile, {}, {}
  if p.mode=="weapon" then return {{name=p.name, creature="Spell effect", crLabel="-", weapon=true}} end
  local all = catalog()
  if p.mode=="spirit" then
    for form, label in ipairs(p.forms) do
      local prefix=QuickSummonRules.normalize(p.prefix.." "..label)
      local alternate=QuickSummonRules.normalize(p.prefix.." "..label:gsub("Star Spawn","Starspawn"))
      local best, priority
      for _,npc in ipairs(all) do
        local name=npc.normalized
        local exact=name==prefix or name==alternate
        local typed=label~="" and (name:find(prefix.." ",1,true)==1 or name:find(alternate.." ",1,true)==1)
        local generic=name==QuickSummonRules.normalize(p.prefix)
        local spellSlot=tonumber(name:match("spell lv[el]+ (%d+)$"))
        local score=(typed and spellSlot==cast.slot and 40)
          or (exact and 30) or (typed and spellSlot and 20- math.abs(cast.slot-spellSlot))
          or (typed and not name:find("scroll",1,true) and 10)
        if generic and #p.forms==1 then score=30 end
        if score and (not priority or score>priority) then
          best,priority=npc,score
        end
      end
      if best then
        rows[#rows+1]={key=best.key, name=label~="" and p.prefix.." ("..label..")" or p.prefix,
          creature=p.creature, crLabel="-", form=form,
          sourceSlot=tonumber(best.normalized:match("spell lv[el]+ (%d+)$"))}
      end
    end
    return rows
  end

  local names, undead = {}, p.mode=="undead" and undeadOptions(cast.slot)
  for _,name in ipairs(p.names or {}) do names[QuickSummonRules.normalize(name)]=true end
  if p.unique=="familiar" and cast.chain then
    for _,name in ipairs({"imp","pseudodragon","quasit","sprite"}) do names[name]=true end
  end
  for _,npc in ipairs(all) do
    local accepted = false
    if p.mode=="catalog" then
      accepted=QuickSummonRules.eligibility(p,npc,cast.cap)
    elseif p.mode=="fixed" then
      accepted=names[npc.normalized] and not npc.isTemplate
    elseif p.mode=="undead" then
      accepted=undead[npc.name] ~= nil
      npc.limit=undead[npc.name]
    elseif p.mode=="objects" then
      local cost=objectCost(npc)
      accepted=cost and (npc.normalized:find("animate objects",1,true)==1 or
        npc.normalized:find("animated object",1,true)==1)
      npc.cost=cost
    end
    local identifier=npc.normalized.."|"..npc.creature:lower().."|"..npc.crLabel
    if accepted and not seen[identifier] then
      rows[#rows+1]=npc
      seen[identifier]=true
    end
  end
  return rows
end

local function closeView(cast)
  if not cast.view then return end
  local previous=cast.view
  cast.view=nil
  DB.setValue(previous,"state","string","closed")
  DB.deleteNode(previous)
end

local function finish(cast)
  casts[DB.getPath(cast.character)]=nil
  closeView(cast)
end

local function notifyView(cast, node, role)
  local path=DB.getPath(node)
  if role=="gm" or cast.localCaster or cast.user=="" then
    Interface.openWindow("quicksummon_dialog",path)
  else
    DB.addHolder(node,cast.user,false)
    Comm.deliverOOBMessage({type=notifyType,path=path},cast.user)
  end
end

local function allowsPartialSelection(profile)
  return profile.countStep and profile.mode~="catalog" and profile.mode~="spirit"
    or profile.mode=="undead" or profile.name=="Druid Grove"
end

local function publish(cast, stage, role, rows, message)
  if cast.stage~=stage or cast.role~=role then
    say(cast.profile.name.." · "..(role=="gm" and "GM" or "Caster").." selection pending.",cast.profile.name)
  end
  local node=cast.role==role and cast.view or nil
  local existing=node~=nil
  local previousRevision=cast.revision
  if not node then
    closeView(cast)
    node=DB.createChild(DB.createNode(viewRoot))
    cast.view=node
  end
  cast.stage,cast.role,cast.rows=stage,role,rows
  cast.revision=(cast.revision or 0)+1
  DB.setValue(node,"castid","string",cast.id)
  DB.setValue(node,"character","string",DB.getPath(cast.character))
  DB.setValue(node,"title","string",cast.profile.name.." — "..DB.getValue(cast.character,"name",""))
  DB.setValue(node,"spellIcon","string","qs_window_"..spellIconKey(cast.profile.name))
  local upcastNotice=role=="caster" and QuickSummonRules.upcastNotice(cast.profile,cast.slot)
  DB.setValue(node,"upcastNotice","string",upcastNotice or "")
  DB.setValue(node,"message","string",message)
  DB.setValue(node,"note","string",cast.profile.note or "")
  DB.setValue(node,"role","string",role)
  DB.setValue(node,"stage","string",stage)
  DB.setValue(node,"slot","number",cast.slot)
  local showSlots=role=="caster" and (QuickSummonRules.canScale(cast.profile) or cast.slot~=cast.profile.level
    or (cast.available[cast.profile.level] or 0)==0 or cast.ritual)
  DB.setValue(node,"showSlots","number",showSlots and 1 or 0)
  DB.setValue(node,"ritual","number",(role=="caster" and cast.ritual) and 1 or 0)
  DB.setValue(node,"baseSlot","number",cast.profile.level)
  DB.setValue(node,"highestSlot","number",cast.highest)
  for level=cast.profile.level,cast.highest do
    DB.setValue(node,"slot"..level,"number",cast.available[level] or 0)
  end
  DB.setValue(node,"multiple","number",(stage=="pick" and (cast.quantity>1 or cast.profile.mode=="undead")) and 1 or 0)
  DB.setValue(node,"quantity","number",cast.quantity or 1)
  DB.setValue(node,"budget","number",cast.budget or 0)
  local minimum=stage=="pick" and not allowsPartialSelection(cast.profile) and cast.quantity or 1
  DB.setValue(node,"minimum","number",minimum)
  local hostView=role=="gm" or cast.localCaster or cast.user==""
  local list=DB.createChild(node,"rows"..cast.revision)
  for i,row in ipairs(rows) do
    local item=DB.createChild(list,string.format("r%05d",i))
    DB.setValue(item,"index","number",i)
    DB.setValue(item,"display","string",row.name)
    DB.setValue(item,"creature","string",row.creature or "-")
    DB.setValue(item,"rating","string",row.crLabel or "-")
    DB.setValue(item,"limit","number",row.limit or cast.quantity or 1)
    DB.setValue(item,"cost","number",row.cost or 1)
    if row.limit then DB.setValue(item,"exclusive","number",1) end
    if hostView and row.key then
      DB.setValue(item,"reference","string",row.key)
    end
  end
  -- Commit the revision after its rows and slot data are available to the dialog.
  DB.setValue(node,"revision","number",cast.revision)
  DB.setValue(node,"state","string","open")
  if existing then
    local previous=DB.getChild(node,"rows"..previousRevision)
    if previous then DB.deleteNode(previous) end
  else
    notifyView(cast,node,role)
  end
end

local function uniqueRecords(cast, key)
  local result={}
  if not key then return result end
  local path=DB.getPath(cast.character)
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if DB.getValue(node,"qs_owner","")==path and DB.getValue(node,"qs_unique","")==key then
      result[#result+1]=node
    end
  end
  return result
end

local function casterStats(cast)
  local actor = actorRecord(cast)
  local group = PowerManager.getPowerGroupRecord(actor,cast.power) or {}
  local function mod(stat)
    return ActorManager5E.getAbilityBonus(actor,stat or "") or 0
  end
  local pb = mod("prf")
  local ability = mod(group.sStat)
  local atk = mod(group.sAtkStat or group.sStat)+(group.nAtkProf or 1)*pb+(group.nAtkMod or 0)
  local dc = 8+mod(group.sSaveDCStat or group.sStat)+(group.nSaveDCProf or 1)*pb+(group.nSaveDCMod or 0)
  return atk,dc,ability,pb
end

local npcPowerFields = {"traits","actions","bonusactions","reactions","legendaryactions","lairactions"}

local function mentionsSpellStat(comment, stat)
  local text=comment:lower()
  if stat=="attack" then
    return text:find("spell attack modifier",1,true) or text:find("spell attack bonus",1,true)
  end
  return text:find("spell save dc",1,true)
end

local function replaceSpiritText(text, slot, sourceSlot, atk, dc, bonus, pb)
  local attack=string.format("%+d",atk)
  local attacks=math.floor(slot/2)
  local attackCount=attacks==1 and "1 attack" or attacks.." attacks"

  text=text:gsub("[+-]%s*%d+ to hit%.?%s*(%b())",function(comment)
    if mentionsSpellStat(comment,"attack") then return attack.." to hit" end
  end)
  text=text:gsub("DC %d+(%s+%a+%s+saving throw)%s*(%b())",function(save,comment)
    if mentionsSpellStat(comment,"dc") then return "DC "..dc..save end
  end)
  text=text:gsub("DC %d+%s*(%b())",function(comment)
    if mentionsSpellStat(comment,"dc") then return "DC "..dc end
  end)
  text=text:gsub("[Yy]our spell attack modifier to hit",attack.." to hit")
  text=text:gsub("[Yy]our spell attack bonus to hit",attack.." to hit")
  text=text:gsub("DC equal to [Yy]our spell save DC","DC "..dc)
  text=text:gsub("[Yy]our spell save DC","DC "..dc)
  local variables={summonatk=attack,summondc=dc,summonlvl=slot,summonmod=bonus,summonpb=pb}
  text=text:gsub("[+-]?%[([%a]+)%]",function(key) return variables[key:lower()] end)

  if text:lower():find("rounded down",1,true) then
    text=text:gsub("(makes )%d+ attacks?%.?%s*(%b())%.?",function(prefix,comment)
      local formula=comment:lower()
      if formula:find("half",1,true) and formula:find("spell",1,true) then
        return prefix..attackCount.."."
      end
    end)
    text=text:gsub("a number of attacks equal to half this spell.s level %(rounded down%)",attackCount)
    text=text:gsub("a number of attacks equal to half the spell.s level %(rounded down%)",attackCount)
    text=text:gsub("half the level of the spell %(rounded down%)",tostring(attacks))
    text=text:gsub("half the spell.s level %(rounded down%)",tostring(attacks))
  end

  if sourceSlot then
    if sourceSlot~=slot then
      local formula=text:lower():find("%(%d+d%d+%s*%+%s*%d+%s*%+%s*[^()]*spell[^()]*l[e]?v")
      if formula then
        local dice,base=text:sub(formula):match("^%((%d+d%d+)%s*%+%s*(%d+)")
        if dice then
          local original=tonumber(base)+sourceSlot
          local prefix=text:sub(1,formula-1):gsub("("..dice.."%s*%+%s*)"..original.."%f[%D]",function(leading)
            return leading..(tonumber(base)+slot)
          end,1)
          text=prefix..text:sub(formula)
        end
      end
    end
  else
    text=text:gsub("[Tt]his spell.s level",tostring(slot))
    text=text:gsub("[Tt]he spell.s level",tostring(slot))
    text=text:gsub("(%d+d%d+%s*%+%s*)(%d+)%s*%+%s*(%d+)",function(prefix,base,level)
      return prefix..(tonumber(base)+tonumber(level))
    end)
  end
  return text
end

local function syncCombatAction(entry, description)
  local original=DB.getValue(entry,"value","")
  if original=="" then return end

  local value=original
  local attack=description:match("([+-]%d+) to hit")
  if attack then
    value=value:gsub("(%[ATK:%s*)[+-]?%d+",function(prefix)
      return prefix..attack
    end,1)
  end

  local saves={}
  for dc,ability in description:gmatch("DC (%d+) (%a+) saving throw") do
    saves[ability:lower()]=dc
  end
  value=value:gsub("(%[SAVEVS:%s*)(%a+)(%s+)%d+",function(prefix,ability,space)
    local dc=saves[ability:lower()]
    if dc then return prefix..ability..space..dc end
  end)
  if value~=original then DB.setValue(entry,"value","string",value) end
end

local function isScaledSummon(node)
  return node and DB.getValue(node,"summon_level",0)>0 and DB.getValue(node,"qs_cast","")~=""
end

local function syncSummonActions(node)
  for _,field in ipairs(npcPowerFields) do
    for _,entry in ipairs(DB.getChildList(node,field)) do
      syncCombatAction(entry,DB.getValue(entry,"desc",""))
    end
  end
end

local function onCombatActionValueChanged(field)
  local entry=DB.getChild(field,"..")
  local node=entry and DB.getChild(entry,"...")
  if isScaledSummon(node) then
    syncCombatAction(entry,DB.getValue(entry,"desc",""))
  end
end

local function replaceScaledText(node, cast, npc, atk, dc, bonus, pb, actor)
  local slot=cast.slot>0 and cast.slot or cast.profile.level
  for _,field in ipairs(npcPowerFields) do
    for _,entry in ipairs(DB.getChildList(node,field)) do
      local original=DB.getValue(entry,"desc","")
      local text=original
      if cast.profile.scales then
        text=replaceSpiritText(text,slot,npc.sourceSlot,atk,dc,bonus,pb)
      end
      if cast.profile.statBonus then
        text=text:gsub("([+-]%d+) to hit",function(n) return string.format("%+d to hit",tonumber(n)+bonus) end)
        text=text:gsub("(%d+d%d+)%s*%+%s*(%d+)",function(d,n) return d.." + "..math.max(0,tonumber(n)+bonus) end)
      end
      if text~=original then
        DB.setValue(entry,"desc","string",text)
        if actor then CombatManager2.parseNPCPowerBuildValue(entry,actor) end
      end
      if actor and cast.profile.scales then syncCombatAction(entry,text) end
    end
  end
end

local function repairScaledSummons()
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    local slot=DB.getValue(node,"summon_level",0)
    if isScaledSummon(node) and DB.getValue(node,"qs_scaling_revision",0)<2 then
      local atk=DB.getValue(node,"summon_attack",0)
      local dc=DB.getValue(node,"summon_dc",0)
      local bonus=DB.getValue(node,"summon_mod",0)
      local pb=DB.getValue(node,"summon_pb",0)
      local cast={slot=slot,profile={scales=true}}
      local source={sourceSlot=slot}
      local sourcePath=DB.getValue(node,"qs_record","")
      local clone=sourcePath~="" and DB.findNode(sourcePath)
      if clone and DB.getValue(clone,"summon_level",0)==slot
          and DB.getValue(clone,"name","")==DB.getValue(node,"name","") then
        replaceScaledText(clone,cast,source,atk,dc,bonus,pb)
        DB.setValue(clone,"qs_scaling_revision","number",2)
      end
      replaceScaledText(node,cast,source,atk,dc,bonus,pb,ActorManager.resolveActor(node))
      DB.setValue(node,"qs_scaling_revision","number",2)
    end
  end
end

local function hookSummonProficiency()
  local getAbilityScore=ActorManager5E.getAbilityScore
  ActorManager5E.getAbilityScore=function(actor,ability,effect)
    if ability and ability:sub(1,3):lower()=="prf" then
      local node=ActorManager.getCreatureNode(actor)
      if node and DB.getValue(node,"qs_scaling_revision",0)>0 then
        return DB.getValue(node,"summon_pb",0)
      end
    end
    return getAbilityScore(actor,ability,effect)
  end
end

local function buildRecord(cast,npc)
  local clone=DB.createChild(DB.createNode("npc"))
  local p=cast.profile
  if npc.weapon then
    DB.setValue(clone,"name","string",p.name)
    DB.setValue(clone,"type","string","spell effect")
    DB.setValue(clone,"size","string","Tiny")
    DB.setValue(clone,"speed","string","fly 20 ft.")
    DB.setValue(clone,"token","token","tokens/QuickSummon/Spiritual_Weapon.png")
    DB.setValue(clone,"hp","number",1)
    local atk,_,ability=casterStats(cast)
    local dice=QuickSummonRules.spiritualWeaponDice(cast.slot)
    local damage=string.format("%dd8",dice)
    if ability~=0 then damage=damage..string.format("%+d",ability) end
    local average=math.max(1,math.floor(dice*4.5+ability))
    local action=DB.createChild(DB.createChild(clone,"bonusactions"))
    DB.setValue(action,"name","string","Spiritual Weapon Strike")
    DB.setValue(action,"desc","string",string.format(
      "Melee Spell Attack: %+d to hit, reach 5 ft., one target. Hit: %d (%s) force damage. "
        .."On the caster's turn, they can move the weapon up to 20 feet and repeat the attack as a bonus action.",
      atk,average,damage))
  else
    local source=DB.findNode(npc.key)
    if not source then DB.deleteNode(clone); return nil end
    DB.copyNode(source,clone)
  end
  DB.setValue(clone,"name","string",p.nameOverride or npc.name)
  DB.setValue(clone,"version","string","Legacy")
  if p.scales or p.statBonus then
    local atk, dc, ability, pb=casterStats(cast)
    if p.scales then
      local slot=cast.slot
      local ac=type(p.ac)=="table" and p.ac[npc.form] or p.ac
      DB.setValue(clone,"ac","number",ac+slot)
      DB.setValue(clone,"hp","number",p.hp[npc.form]+(slot-p.level)*p.growth)
      DB.setValue(clone,"hd","string","")
      DB.setValue(clone,"summon_level","number",slot)
      DB.setValue(clone,"summon_attack","number",atk)
      DB.setValue(clone,"summon_dc","number",dc)
      DB.setValue(clone,"summon_mod","number",ability)
      DB.setValue(clone,"summon_pb","number",pb)
      DB.setValue(clone,"summon","number",0)
      DB.setValue(clone,"qs_scaling_revision","number",2)
    end
    replaceScaledText(clone,cast,npc,atk,dc,ability,pb)
  end
  if p.unique=="familiar" or p.name=="Flock of Familiars" then
    DB.deleteChildren(clone,"actions")
  end
  if p.mode=="fixed" and p.forms then DB.setValue(clone,"type","string",p.forms[cast.option]) end
  if p.fey then
    local typeName=p.name=="Conjure Animals" and "beast (also fey)" or "fey"
    DB.setValue(clone,"type","string",typeName)
  end
  if p.name=="Phantom Steed" then DB.setValue(clone,"speed","string","100 ft.") end
  return clone
end

local function applyInitiative(cast,node,source)
  local mode=cast.profile.initiative or "roll"
  local linked=mode=="after" or mode=="share"
  if linked and source then
    local path=DB.getPath(source)
    local effect=EffectManager.addEffectByTable(node,{
      sName=mode=="share" and "SHARETURN" or "AFTERTURN", sSource=path, nDuration=0, bSkipAnnounce=true,
    })
    if effect and mode=="after" then EffectManager.addEffectTarget(effect,path) end
  end
  if not hasActiveInitiative(source) then
    local init=DB.getChild(node,"initresult")
    if init then DB.deleteNode(init) end
    return
  end
  local initiative
  if linked then
    initiative=DB.getValue(source,"initresult",0)
  elseif mode=="group" then
    cast.groupInit=cast.groupInit or CombatManager.helperRollRandomInit({nodeEntry=node,nMod=DB.getValue(node,"init",0)})
    initiative=cast.groupInit
  else
    initiative=CombatManager.helperRollRandomInit({nodeEntry=node,nMod=DB.getValue(node,"init",0)})
  end
  DB.setValue(node,"initresult","number",initiative)
end

local function addCombatant(cast,npc,source)
  local record=buildRecord(cast,npc)
  if not record then return end
  local p=cast.profile
  local faction=p.faction or (source and DB.getValue(source,"friendfoe","friend")) or "friend"
  local data={nodeRecord=record,sClass="npc",sRecordType="npc",sFaction=faction,bQuickSummon=true}
  CombatRecordManager.onRecordTypeEvent("npc",data)
  local node=data.nodeCT
  if not node then DB.deleteNode(record); return end
  DB.setValue(node,"qs_record","string",DB.getPath(record))
  DB.setValue(node,"qs_owner","string",DB.getPath(cast.character))
  DB.setValue(node,"qs_unique","string",p.unique or "")
  DB.setValue(node,"qs_cast","string",cast.id)
  if p.scales then syncSummonActions(node) end
  DB.setValue(node,"qs_break_hostile","number",p.breaksHostile and 1 or 0)
  DB.setValue(node,"qs_manual_expiration","number",p.manualExpiration and 1 or 0)
  DB.setValue(node,"tokenvis","number",1)
  DB.setValue(node,"friendfoe","string",faction)
  applyInitiative(cast,node,source)
  if npc.weapon then
    EffectManager.addEffectByTable(node,{sName="NOREACTION",nDuration=0,bSkipAnnounce=true})
  elseif p.unique=="familiar" then
    EffectManager.addEffectByTable(node,{sName="Familiar",nDuration=0,bSkipAnnounce=true})
  end
  local user=owner(cast.character)
  if user~="" and faction=="friend" and OptionsManager.isOption(autoAssignOption,"on") then
    DB.setValue(node,"qs_assigned_user","string",user)
    DB.setValue(node,"NPCowner","string",user)
    DB.addHolder(node,user,true)
    DB.addHolder(record,user,false)
    -- Share the live CT sheet, as when the GM drops its link onto a player portrait.
    local window=Interface.openWindow("npc",node)
    if window then window.share(user) end
  end
  return node
end

local function spend(cast)
  return cast.slot==0 or PowerManager5E.consumeSpellSlot(actorRecord(cast),cast.slot)
end

local function resolve(cast, selected)
  local p=cast.profile
  local source=casterCT(cast)
  if (p.concentration or p.initiative=="share") and not source then
    say("Put the caster on the Combat Tracker before casting "..p.name..".",p.name)
    finish(cast)
    return
  end
  for _,npc in ipairs(selected) do
    if not npc.weapon and not DB.findNode(npc.key) then
      say("A selected module record is no longer loaded. Cast cancelled.",p.name)
      finish(cast)
      return
    end
  end
  local prior=uniqueRecords(cast,p.unique)
  if p.noReplace and #prior>0 then
    say("The caster already has a homunculus on the Combat Tracker.",p.name)
    finish(cast)
    return
  end
  local added={}
  local function rollback(message)
    for _,node in ipairs(added) do CombatManager.deleteCombatant(node) end
    say(message,p.name)
    finish(cast)
  end
  for _,npc in ipairs(selected) do
    local node=addCombatant(cast,npc,source)
    if not node then
      rollback("NPC creation failed. Cast cancelled.")
      return
    end
    added[#added+1]=node
  end
  if not spend(cast) then
    rollback("The selected spell slot is no longer available.")
    return
  end
  local effect
  if p.concentration then
    ActionSave.expireConcentrationEffects(actorRecord(cast))
    effect=EffectManager.addEffectByTable(source,{
      sName=p.name.." (C)", nDuration=p.concentration, sUnits="minute", bSkipAnnounce=true,
    })
  elseif p.minutes and source then
    effect=EffectManager.addEffectByTable(source,{
      sName=p.name.." (Quick Summon)",nDuration=p.minutes,sUnits="minute",bSkipAnnounce=true,
    })
  end
  if effect and not p.keepOnEnd then
    local duration=DB.getPath(effect)
    for _,node in ipairs(added) do DB.setValue(node,"qs_duration","string",duration) end
  elseif not effect and (p.concentration or p.minutes) then
    say(p.name..": track duration manually.",p.name)
  end
  for _,node in ipairs(prior) do CombatManager.deleteCombatant(node) end
  PowerManager5E.setSpellUpcast(cast.power,cast.slot==0 and -1 or cast.slot-p.level)
  local slotMessage=cast.slot==0 and "Cast as a ritual. No spell slot spent."
    or string.format("Level %d spell slot automatically expended.",cast.slot)
  say(string.format("%s: %d added to the Combat Tracker. %s The GM can place the tokens.",
    p.name,#added,slotMessage),p.name)
  finish(cast)
end

local function pickStage(cast,force)
  local p=cast.profile
  local effective=cast.slot>0 and cast.slot or p.level
  cast.quantity,cast.cap,cast.budget=QuickSummonRules.options(p,effective,cast.option,cast.die,
    #uniqueRecords(cast,"familiar")>0)
  if p.mode=="undead" then cast.quantity=effective-3 end
  if p.mode=="objects" then cast.quantity=cast.budget end
  local rows=getCandidates(cast)
  if #rows==0 then
    publish(cast,"pick",p.chooser=="gm" and "gm" or "caster",{},
      "No eligible NPCs in the currently loaded modules. Load a matching module and use Refresh.")
    return
  end
  local variable=allowsPartialSelection(p)
  if #rows==1 and not variable and not force then
    local selection={}
    for _=1,cast.quantity do selection[#selection+1]=rows[1] end
    resolve(cast,selection)
    return
  end
  local message=""
  if (cast.slot~=0 or not cast.ritual) and (cast.available[cast.slot] or 0)<=0 then
    message="No usable spell slot is available."
  elseif cast.budget then
    message="Select objects up to size budget "..cast.budget.."."
  elseif variable or cast.quantity>1 then
    message="Choose "..(variable and "up to " or "")..cast.quantity..
      (cast.cap and " · CR ≤ "..QuickSummonRules.crText(cast.cap) or "").."."
  elseif cast.cap then
    message="CR ≤ "..QuickSummonRules.crText(cast.cap)
  end
  local role=p.chooser=="gm" and "gm" or "caster"
  publish(cast,"pick",role,rows,message)
end

local function setupStage(cast,force)
  local p, rows = cast.profile,{}
  cast.option=cast.option or 1
  local effective=cast.slot>0 and cast.slot or p.level
  if p.groups then
    for index=1,#p.groups do
      local count, cap=QuickSummonRules.options(p,effective,index)
      rows[index]={name=count.." creatures",creature=p.creature,crLabel="≤ "..QuickSummonRules.crText(cap)}
    end
  elseif p.mode~="spirit" then
    for index,form in ipairs(p.forms or {}) do rows[index]={name=form} end
  end
  local slots=0
  for _,count in pairs(cast.available) do if count>0 then slots=slots+1 end end
  local needsSlotChoice=slots>1 and (QuickSummonRules.canScale(p) or (cast.available[p.level] or 0)==0)
  local _,noUpcastBenefit=QuickSummonRules.upcastNotice(p,cast.slot)
  local slotSetup=slots==0 or needsSlotChoice or cast.ritual or noUpcastBenefit
  if #rows>1 or force or (p.chooser=="gm" and slotSetup) then
    local message=#rows>1 and "Select a casting option." or ""
    if slots==0 and not cast.ritual then message="No usable spell slot is available." end
    publish(cast,"setup","caster",rows,message)
  else
    pickStage(cast,slotSetup)
  end
end

local function begin(character,node,host)
  local p=profile(node)
  local parent=p and DB.getChild(node,"...")
  if not parent or DB.getPath(parent)~=DB.getPath(character) then return end
  local path=DB.getPath(character)
  if casts[path] then finish(casts[path]) end
  nextCast=nextCast+1
  local cast={id=tostring(os.time()).."-"..nextCast, character=character,
    power=node, profile=p, user=owner(character), option=1, localCaster=host}
  cast.ritual=DB.getValue(node,"ritual",0)==1
  cast.die=p.randomGroups and math.random(6)
  casts[path]=cast
  slotData(cast)
  say(DB.getValue(character,"name","Caster").." started "..p.name..".",p.name)
  if cast.die then say(p.name.." · demon group roll: "..cast.die..".",p.name) end
  setupStage(cast)
end

local function selectedRows(cast, indices)
  local selected,cost,limit={},0,cast.quantity
  local selectedLimit
  local indexCount=0
  for index in tostring(indices or ""):gmatch("%d+") do
    indexCount=indexCount+1
    if indexCount>40 then return end
    local row=cast.rows[tonumber(index)]
    if not row then return end
    if row.limit then
      if selectedLimit and selectedLimit~=row.name then return end
      selectedLimit=row.name
      limit=row.limit
    end
    cost=cost+(row.cost or 1)
    selected[#selected+1]=row
  end
  if #selected==0 or #selected>limit or (cast.budget and cost>cast.budget) then return end
  if not allowsPartialSelection(cast.profile) and #selected~=cast.quantity then return end
  return selected
end

local function dispatch(character,command,host)
  if not Session.IsHost or not character then return end
  local fields={}
  for value in (command.."|"):gmatch("(.-)|") do fields[#fields+1]=value end
  local op=fields[1]
  if op=="start" then
    if not host and owner(character)=="" then return end
    if fields[2] and fields[2]~="" then begin(character,DB.findNode(fields[2]),host) end
    return
  end
  local cast=casts[DB.getPath(character)]
  if not cast or cast.id~=fields[2] or cast.revision~=tonumber(fields[3]) then return end
  if not host and (cast.role~="caster" or cast.localCaster or owner(character)~=cast.user) then return end
  if not profile(cast.power) then finish(cast); return end
  if op=="cancel" then
    say(cast.profile.name.." cancelled.",cast.profile.name)
    finish(cast)
    return
  end
  slotData(cast)
  local requested=tonumber(fields[4])
  if op=="slot" and cast.role=="caster" then
    if (requested==0 and cast.ritual) or (requested and (cast.available[requested] or 0)>0) then
      cast.slot=requested
    end
    if cast.stage=="setup" then setupStage(cast,true) else pickStage(cast,true) end
    return
  end
  if op=="refresh" then
    if cast.stage=="setup" then setupStage(cast,true) else pickStage(cast,true) end
    return
  end
  if op~="submit" then return end
  if (cast.slot~=0 or not cast.ritual) and (cast.available[cast.slot] or 0)<=0 then
    publish(cast,cast.stage,cast.role,cast.rows,"No available slot selected. Choose a slot or cancel.")
    return
  end
  if cast.stage=="setup" then
    local index=tonumber(fields[5]) or 1
    if #cast.rows>0 and not cast.rows[index] then return end
    cast.option=index
    pickStage(cast)
  elseif cast.stage=="pick" then
    local rows=selectedRows(cast,fields[5])
    if not rows then
      publish(cast,"pick",cast.role,cast.rows,"Selection is outside the spell's count, size or type limits.")
      return
    end
    resolve(cast,rows)
  end
end

local function onCommand(node)
  local character=DB.getChild(node,"..")
  if not character or owner(character)=="" then return end
  local payload=DB.getValue(DB.getPath(node),"")
  local command=payload:match("^[^|]+%|(.*)$")
  if command then dispatch(character,command,false) end
end

local function send(character,command)
  if Session.IsHost then
    dispatch(character,command,true)
  else
    serial=serial+1
    DB.setValue(character,commandField,"string",os.time().."-"..serial.."|"..command)
  end
end

function submit(node,op,slot,indices)
  if not node or DB.getValue(node,"state","")~="open" then return end
  local character=DB.findNode(DB.getValue(node,"character",""))
  if character then
    send(character,table.concat({op,DB.getValue(node,"castid",""),DB.getValue(node,"revision",0),
      slot or DB.getValue(node,"slot",0),indices or ""},"|"))
  end
end

local function start(node)
  if not profile(node) then return false end
  local character=DB.getChild(node,"...")
  if not character then return false end
  send(character,"start|"..DB.getPath(node))
  return true
end

local function openPending()
  for path in pairs(pendingViews) do
    local node=DB.findNode(path)
    if node and DB.getValue(node,"state","")=="open" then
      pendingViews[path]=nil
      Interface.openWindow("quicksummon_dialog",path)
    end
  end
end

local function onView(msg)
  if Session.IsHost or type(msg.path)~="string" or not msg.path:match("^quicksummon_views%.[^.]+$") then return end
  pendingViews[msg.path]=true
  openPending()
end

local function onEffectDeleted(node)
  local path=DB.getPath(node)
  -- CoreRPG deletes a normally expiring effect with one round still stored.
  local early=EffectVarManager.getEffectVarFromNode(node,"nDuration",0)>1
  local spell=EffectVarManager.getEffectVarFromNode(node,"sName",""):match("^(.-) %(")
  local linked={}
  for _,entry in pairs(CombatManager.getCombatantNodes()) do
    if DB.getValue(entry,"qs_duration","")==path then linked[#linked+1]=entry end
  end
  for _,entry in ipairs(linked) do
    if early and DB.getValue(entry,"qs_manual_expiration",0)==1 then
      DB.setValue(entry,"qs_duration","string","")
      say("The GM resolves any delayed disappearance for "..DB.getValue(entry,"name","the summon")..".",spell)
    elseif early and DB.getValue(entry,"qs_break_hostile",0)==1 then
      DB.setValue(entry,"friendfoe","string","foe")
      DB.setValue(entry,"qs_duration","string","")
      local character=DB.findNode(DB.getValue(entry,"qs_owner",""))
      local user=DB.getValue(entry,"qs_assigned_user",character and owner(character) or "")
      if user~="" then
        DB.removeHolder(entry,user)
        local clone=DB.findNode(DB.getValue(entry,"qs_record",""))
        if clone then DB.removeHolder(clone,user) end
        if DB.getValue(entry,"NPCowner","")==user then DB.setValue(entry,"NPCowner","string","") end
        DB.setValue(entry,"qs_assigned_user","string","")
      end
      say("Concentration ended. The GM takes control of "..DB.getValue(entry,"name","the summon")
        .." and tracks its remaining duration.",spell)
    else
      CombatManager.deleteCombatant(entry)
    end
  end
end

local function onCombatantDeleted(node)
  local clone=DB.findNode(DB.getValue(node,"qs_record",""))
  if clone then DB.deleteNode(clone) end
end

local function initCommandField(_,character)
  if character and not DB.getChild(character,commandField) then
    DB.setValue(character,commandField,"string","")
  end
end

function onInit()
  OptionsManager.registerOption(autoAssignOption,false,"Quick Summon","Auto Assign Summoned NPC",
    "option_entry_cycler",{labels="On",values="on",baselabel="Off",baseval="off",default="on"})
  hookSummonProficiency()
  OOBManager.registerOOBMsgHandler(notifyType,onView)
  DB.addHandler("quicksummon_views.*","onChildUpdate",openPending)
  DB.addHandler("quicksummon_views.*","onChildAdded",openPending)
  if Session.IsHost then
    if DB.findNode(viewRoot) then DB.deleteChildren(viewRoot) end
    for _,character in ipairs(DB.getChildList("charsheet")) do initCommandField(nil,character) end
    DB.addHandler("charsheet","onChildAdded",initCommandField)
    DB.addHandler("charsheet.*."..commandField,"onUpdate",onCommand)
    normalAddInitiative=CombatRecordManager.handleCombatAddInitDnD
    CombatRecordManager.handleCombatAddInitDnD=function(data)
      if not data.bQuickSummon then return normalAddInitiative(data) end
    end
    DB.addHandler("combattracker.list.*.effects.*","onDelete",onEffectDeleted)
    DB.addHandler("combattracker.list.*","onDelete",onCombatantDeleted)
    for _,field in ipairs(npcPowerFields) do
      DB.addHandler("combattracker.list.*."..field..".*.value","onUpdate",onCombatActionValueChanged)
    end
    repairScaledSummons()
  end
  normalUse=PowerManagerCore.usePower
  PowerManagerCore.usePower=function(node)
    if not start(node) then return normalUse(node) end
  end
  normalAction=PowerManager5E.performPowerAction
  PowerManager5E.performPowerAction=function(node)
    if node and DB.getValue(node,"type","")=="cast" and start(DB.getChild(node,"...")) then return end
    return normalAction(node)
  end
end


function onTabletopInit()
  if not Session.IsHost then return end
  -- The ruleset and extensions can rebuild CT summaries during campaign startup.
  for _,node in pairs(CombatManager.getCombatantNodes()) do
    if isScaledSummon(node) then syncSummonActions(node) end
  end
end
