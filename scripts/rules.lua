local profiles

local function register(name, level, rule)
  rule.name, rule.level = name, level
  profiles[name:lower()] = rule
end

local function spirit(name, level, prefix, creature, forms, ac, hp, growth)
  register(name, level, {
    mode="spirit", chooser="caster", prefix=prefix, creature=creature, forms=forms,
    ac=ac, hp=hp, growth=growth, concentration=60, initiative="after", scales=true,
  })
end

local function registerProfiles()
  local groups = {{1, 2}, {2, 1}, {4, 0.5}, {8, 0.25}}

  for _, spec in ipairs({
    {"Conjure Animals", 3, "Beast", {5, 7, 9}},
    {"Conjure Minor Elementals", 4, "Elemental", {6, 8}},
    {"Conjure Woodland Beings", 4, "Fey", {6, 8}},
  }) do
    register(spec[1], spec[2], {
      mode="catalog", chooser="gm", creature=spec[3], groups=groups,
      thresholds=spec[4], concentration=60, initiative="group",
      fey=spec[1]=="Conjure Animals",
    })
  end

  register("Conjure Elemental", 5, {
    mode="catalog", chooser="gm", creature="Elemental", cap=5, capStep=1,
    forms={"Air","Earth","Fire","Water"}, concentration=60, initiative="roll", breaksHostile=true,
    note="GM: choose an elemental appropriate to the selected terrain and confirm placement.",
  })
  register("Conjure Fey", 6, {
    mode="catalog", chooser="gm", creature="Fey/Beast", cap=6, capStep=1,
    concentration=60, initiative="roll", breaksHostile=true, fey=true,
  })
  register("Conjure Celestial", 7, {
    mode="catalog", chooser="gm", creature="Celestial", cap=4, capAt9=5,
    concentration=60, initiative="roll",
  })
  register("Summon Lesser Demons", 3, {
    mode="catalog", chooser="gm", creature="Fiend", subtype="demon",
    randomGroups={{2,1},{4,0.5},{8,0.25}}, thresholds={6,8},
    concentration=60, initiative="group", faction="foe",
  })
  register("Summon Greater Demon", 4, {
    mode="catalog", chooser="caster", creature="Fiend", subtype="demon", cap=5, capStep=1,
    concentration=60, initiative="roll", manualExpiration=true,
    note="GM: resolve control saves and any delayed disappearance if control breaks.",
  })
  register("Infernal Calling", 5, {
    mode="catalog", chooser="caster", creature="Fiend", subtype="devil", cap=6, capStep=1,
    forms={"Standard calling","Named talisman (+1 CR)"}, concentration=60,
    initiative="roll", faction="neutral", manualExpiration=true,
    note="GM: confirm the specific talisman bearer, bargaining and command checks.",
  })

  spirit("Summon Beast", 2, "Bestial Spirit", "Beast", {"Air","Land","Water"}, 11, {20,30,30}, 5)
  spirit("Summon Fey", 3, "Fey Spirit", "Fey", {"Fuming","Mirthful","Tricksy"}, 12, {30,30,30}, 10)
  spirit("Summon Shadowspawn", 3, "Shadow Spirit", "Monstrosity", {"Despair","Fear","Fury"}, 11, {35,35,35}, 15)
  spirit("Summon Undead", 3, "Undead Spirit", "Undead", {"Ghostly","Putrid","Skeletal"}, 11, {30,30,20}, 10)
  spirit("Summon Aberration", 4, "Aberrant Spirit", "Aberration", {"Beholderkin","Slaad","Star Spawn"}, 11, {40,40,40}, 10)
  spirit("Summon Construct", 4, "Construct Spirit", "Construct", {"Clay","Metal","Stone"}, 13, {40,40,40}, 15)
  spirit("Summon Elemental", 4, "Elemental Spirit", "Elemental", {"Air","Earth","Fire","Water"}, 11, {50,50,50,50}, 10)
  spirit("Summon Celestial", 5, "Celestial Spirit", "Celestial", {"Avenger","Defender"}, {11,13}, {40,40}, 10)
  spirit("Summon Draconic Spirit", 5, "Draconic Spirit", "Dragon", {"Chromatic","Gem","Metallic"}, 14, {50,50,50}, 10)
  spirit("Summon Fiend", 6, "Fiendish Spirit", "Fiend", {"Demon","Devil","Yugoloth"}, 12, {50,40,60}, 15)
  spirit("Spirit of Death", 4, "Reaper Spirit", "Undead", {""}, 11, {40}, 10)

  local familiar = {"Bat","Cat","Crab","Frog","Hawk","Lizard","Octopus","Owl",
    "Poisonous Snake","Quipper","Rat","Raven","Sea Horse","Spider","Weasel"}
  local spiritTypes = {"Celestial","Fey","Fiend"}
  register("Find Familiar", 1, {
    mode="fixed", names=familiar, forms=spiritTypes, chooser="caster", unique="familiar",
  })
  register("Flock of Familiars", 2, {
    mode="fixed", names=familiar, forms=spiritTypes, chooser="caster", count=3,
    countStep=1, concentration=60,
  })
  register("Find Steed", 2, {
    mode="fixed", names={"Warhorse","Pony","Camel","Elk","Mastiff"}, forms=spiritTypes,
    chooser="caster", unique="steed",
  })
  register("Find Greater Steed", 4, {
    mode="fixed", names={"Griffon","Pegasus","Peryton","Dire Wolf","Rhinoceros","Saber-Toothed Tiger"},
    forms=spiritTypes, chooser="caster", unique="steed",
  })
  register("Phantom Steed", 3, {
    mode="fixed", names={"Riding Horse"}, nameOverride="Phantom Steed", minutes=61,
    note="GM: end the spell on damage and allow one minute to dismount.",
  })
  register("Planar Ally", 6, {
    mode="catalog", creature="Celestial/Elemental/Fiend", chooser="gm", faction="neutral",
    note="GM: resolve agreement, payment, and service duration.",
  })
  register("Gate", 9, {
    mode="catalog", chooser="gm", faction="neutral", concentration=1, keepOnEnd=true,
    note="Named-creature use only. GM: select the record for the named creature on another plane.",
  })
  register("Animate Dead", 3, {
    mode="fixed", names={"Skeleton","Zombie"}, chooser="caster", countStep=2, controlHours=24,
    note="New undead only. Confirm the corpses or bones and chosen count with the GM.",
  })
  register("Create Undead", 6, {
    mode="undead", chooser="caster", upcast=true, controlHours=24,
    note="New undead only. Confirm the corpses and nighttime casting with the GM.",
  })
  register("Danse Macabre", 5, {
    mode="fixed", names={"Skeleton","Zombie"}, chooser="caster", count=5, countStep=2,
    concentration=60, statBonus=true, note="Select one record per corpse animated.",
  })
  register("Animate Objects", 5, {
    mode="objects", chooser="caster", budget=10, countStep=2, concentration=1,
    note="Choose one row per object. Size costs: Tiny/Small 1, Medium 2, Large 4, Huge 8.",
  })
  register("Tiny Servant", 3, {
    mode="fixed", names={"Tiny Servant"}, chooser="caster", countStep=2, minutes=480,
    note="Confirm there are enough eligible objects.",
  })
  register("Druid Grove", 6, {
    mode="fixed", names={"Awakened Tree"}, chooser="gm", count=4, manualExpiration=true,
    note="Grove Guardians option only. Confirm eligible trees and track the grove duration.",
  })
  register("Create Homunculus", 6, {
    mode="fixed", names={"Homunculus"}, unique="homunculus", noReplace=true,
  })
  register("Create Magen", 7, {
    mode="fixed", names={"Demos Magen","Galvan Magen","Hypnos Magen"}, chooser="caster",
    note="GM: apply the maximum HP cost to the caster, equal to the Magen CR, minimum 1.",
  })
  register("Spiritual Weapon", 2, {
    mode="weapon", upcast=true, initiative="share", unique="spiritualweapon", minutes=1,
    note="Place the token using the Combat Tracker. Use its Spiritual Weapon Strike bonus action to roll.",
  })
end

function normalize(value)
  return tostring(value or ""):lower():gsub("[^%w]+", " "):match("^%s*(.-)%s*$")
end

function match(name, level)
  if not profiles then
    profiles = {}
    registerProfiles()
  end
  local normalized = normalize(name):gsub(" legacy$", "")
  local profile = profiles[normalized]
  if profile and (not level or level == 0 or profile.level == level) then
    return profile
  end
end

function crValue(value)
  local numeric = tonumber(value)
  if numeric then return numeric end
  local a,b = tostring(value or ""):match("^%s*(%d+)%s*/%s*(%d+)")
  if a and tonumber(b) > 0 then return tonumber(a)/tonumber(b) end
  return tonumber(tostring(value or ""):match("^%s*(%d+)%s*%("))
end

function crText(value)
  return ({[0.125]="1/8",[0.25]="1/4",[0.5]="1/2"})[value] or tostring(value)
end

function canScale(p)
  return p.thresholds or p.capStep or p.capAt9 or p.scales or p.countStep or p.upcast
end

function spiritualWeaponDice(slot)
  return 1+math.floor(math.max(0,slot-2)/2)
end

function upcastNotice(p, slot)
  if p.mode=="weapon" then
    local bonus=spiritualWeaponDice(slot)-1
    if bonus>0 then
      if (slot-p.level)%2==1 then
        return string.format("Level %d gives the same +%dd8 damage as level %d.",slot,bonus,slot-1),true
      end
      return string.format("Upcast damage bonus: +%dd8.",bonus)
    end
    return "A 3rd-level slot adds no damage. Upcast adds 1d8 per two levels above 2nd.",slot>p.level
  end
  if p.level<9 and not canScale(p) then
    return "Casting with a higher-level slot grants no additional benefit.",slot>p.level
  end
  if slot>p.level and (p.thresholds or p.capAt9) then
    local previous=p.level
    for _,threshold in ipairs(p.thresholds or {9}) do
      if slot==threshold then return end
      if slot<threshold then
        return string.format("Level %d gives the same result as level %d. Next improvement: level %d.",
          slot,previous,threshold),true
      end
      previous=threshold
    end
    return string.format("Level %d gives the same result as level %d.",slot,previous),true
  end
end

function options(p, level, index, die, existingFamiliar)
  local group = p.groups and p.groups[index] or p.randomGroups and p.randomGroups[math.ceil((die or 1)/2)]
  local count, cap = (p.count or 1), p.cap
  if group then
    count, cap = group[1], group[2]
    local multiplier = 1
    for _,threshold in ipairs(p.thresholds) do
      if level >= threshold then multiplier = multiplier + 1 end
    end
    count = count * multiplier
  end
  local extra = level - p.level
  if cap then cap = cap + extra*(p.capStep or 0) end
  if p.capAt9 and level == 9 then cap = p.capAt9 end
  if p.name=="Infernal Calling" and index==2 then cap = cap+1 end
  if p.mode~="objects" then count = count+extra*(p.countStep or 0) end
  if p.name=="Flock of Familiars" and existingFamiliar then count = count-1 end
  return count, cap, p.budget and p.budget+extra*p.countStep
end

function eligibility(p, npc, cap)
  if npc.isTemplate or npc.isSwarm then return false end
  if cap and (not npc.cr or npc.cr > cap) then return false end
  if p.creature and not ("/"..p.creature:lower().."/"):find("/"..npc.creature:lower().."/",1,true) then
    return false
  end
  return not p.subtype or npc.fullType:lower():match("%f[%a]"..p.subtype.."%f[%A]") ~= nil
end

function randomBudgetSelection(options, budget)
  -- Each table records the totals attainable from this row through the end of the list.
  local reachable={[#options+1]={[0]=true}}
  for i=#options,1,-1 do
    local option=options[i]
    local totals={}
    for spent in pairs(reachable[i+1]) do
      local limit=math.min(option.limit,math.floor((budget-spent)/option.cost))
      for count=0,limit do
        totals[spent+count*option.cost]=true
      end
    end
    reachable[i]=totals
  end

  local remaining=budget
  while not reachable[1][remaining] do remaining=remaining-1 end
  local selected={}
  for i,option in ipairs(options) do
    local counts={}
    local limit=math.min(option.limit,math.floor(remaining/option.cost))
    for count=0,limit do
      if reachable[i+1][remaining-count*option.cost] then
        counts[#counts+1]=count
      end
    end
    local count=counts[math.random(#counts)]
    if count>0 then selected[option.index]=count end
    remaining=remaining-count*option.cost
  end
  return selected
end
