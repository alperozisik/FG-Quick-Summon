local node
local selected = {}
local busy = false
local choice = 0
local multiple = false
local baseSlot = 0
local level = 0
local rowSource
local displayedRows = {}
local randomOptions = {}
local randomCount = 1
local canAdd = {}

function onInit()
  node=getDatabaseNode()
  DB.addHandler(node,"onChildUpdate",stateChanged)
  DB.addHandler(DB.getPath(node,"revision"),"onUpdate",loadRevision)
  loadRevision()
end

function loadRevision()
  if rowSource then DB.removeHandler(rowSource,"onChildAdded",populateRows) end
  rows.closeAll()
  displayedRows={}
  selected={}
  randomOptions={}
  canAdd={}
  choice=0
  busy=false
  multiple=DB.getValue(node,"multiple",0)==1
  spellicon.setIcon(DB.getValue(node,"spellIcon",""))
  message.setValue(DB.getValue(node,"message",""))
  local warning=DB.getValue(node,"upcastNotice","")
  upcastnotice.setValue(warning)
  upcastnotice.setVisible(warning~="")
  note.setValue(DB.getValue(node,"note",""))
  level=DB.getValue(node,"slot",0)
  baseSlot=DB.getValue(node,"baseSlot",1)
  local highestSlot=DB.getValue(node,"highestSlot",baseSlot)
  local show=DB.getValue(node,"showSlots",0)==1
  slotslabel.setVisible(show)
  for i=1,9 do
    local button=self["slot"..i]
    local slot=baseSlot+i-1
    local remaining=DB.getValue(node,"slot"..slot,0)
    local suffix=({"st","nd","rd"})[slot] or "th"
    local label=slot..suffix.." level"
    button.setStateText(0,label,label)
    button.setStateText(1,label,label)
    button.setVisible(show and slot<=highestSlot)
    button.setEnabled(remaining>0)
    button.setColor(remaining>0 and "FFFFFFFF" or "FF8F8F8F")
    button.setValue(slot==level and 1 or 0)
  end
  ritual.setVisible(DB.getValue(node,"ritual",0)==1)
  ritual.setStateText(0,"Ritual","Ritual")
  ritual.setStateText(1,"Ritual","Ritual")
  ritual.setValue(level==0 and 1 or 0)
  randomCount=DB.getValue(node,"minimum",1)
  rowSource=DB.getChild(node,"rows"..DB.getValue(node,"revision",0))
  if rowSource then
    DB.addHandler(rowSource,"onChildAdded",populateRows)
    populateRows()
  end
  refreshSelection()
end

function populateRows()
  randomOptions={}
  local quantity=DB.getValue(node,"quantity",1)
  local budget=DB.getValue(node,"budget",0)
  for _,entry in ipairs(DB.getChildList(rowSource)) do
    local path=DB.getPath(entry)
    if not displayedRows[path] then
      displayedRows[path]=rows.createWindow(entry)
    end
    if not multiple or (randomCount<=math.min(40,quantity,DB.getValue(entry,"limit",quantity))
      and (budget==0 or randomCount*DB.getValue(entry,"cost",1)<=budget)) then
      randomOptions[#randomOptions+1]=DB.getValue(entry,"index",0)
    end
  end
  refreshSelection()
end

function stateChanged()
  if node and DB.getValue(node,"state","")=="closed" then
    busy=true
    close()
  end
end

function onClose()
  if not node then return end
  DB.removeHandler(node,"onChildUpdate",stateChanged)
  DB.removeHandler(DB.getPath(node,"revision"),"onUpdate",loadRevision)
  if rowSource then DB.removeHandler(rowSource,"onChildAdded",populateRows) end
  if not busy and DB.getValue(node,"state","")=="open" then
    QuickSummon.submit(node,"cancel")
  end
end

function refreshSelection()
  if not node then return end
  local entries=rows.getWindows()
  local setup=DB.getValue(node,"stage","")=="setup"
  if choice==0 and entries[1] and (setup or (not multiple and #entries==1)) then
    choice=DB.getValue(entries[1].getDatabaseNode(),"index",1)
  end
  nameheading.setVisible(#entries>0)
  typeheading.setVisible(#entries>0)
  crheading.setVisible(#entries>0)
  countheading.setVisible(#entries>0)
  randomize.setVisible(#entries>1 and #randomOptions>1)
  selectionTotal.setVisible(multiple and #entries>0)
  local count,spent=0,0
  local quantity=math.min(40,DB.getValue(node,"quantity",1))
  local budget=DB.getValue(node,"budget",0)
  local exclusiveName
  for _,row in ipairs(entries) do
    local rowNode=row.getDatabaseNode()
    local index=DB.getValue(rowNode,"index",0)
    local chosen=multiple and (selected[index] or 0) or (choice==index and 1 or 0)
    count=count+chosen
    spent=spent+chosen*DB.getValue(rowNode,"cost",1)
    if chosen>0 and DB.getValue(rowNode,"exclusive",0)==1 then
      exclusiveName=DB.getValue(rowNode,"display","")
    end
  end
  local maxTotal=0
  for _,row in ipairs(entries) do
    local rowNode=row.getDatabaseNode()
    local index=DB.getValue(rowNode,"index",0)
    local chosen=multiple and (selected[index] or 0) or (choice==index and 1 or 0)
    local maximum
    if multiple then
      local cost=DB.getValue(rowNode,"cost",1)
      local limit=DB.getValue(rowNode,"limit",quantity)
      local remaining=quantity-count
      if budget>0 then remaining=math.min(remaining,math.floor((budget-spent)/cost)) end
      maximum=math.min(limit,chosen+remaining)
      if exclusiveName and exclusiveName~=DB.getValue(rowNode,"display","") then maximum=0 end
      canAdd[index]=chosen<maximum
      maxTotal=math.max(maxTotal,count-chosen+maximum)
    end
    row.showCount(chosen,maximum)
  end
  if multiple then
    selectionTotal.setValue(budget>0 and string.format("Size budget: %d / %d",spent,budget)
      or string.format("Total selected: %d / %d",count,maxTotal))
  end
  local hasSlot=(level==0 and DB.getValue(node,"ritual",0)==1) or DB.getValue(node,"slot"..level,0)>0
  confirm.setEnabled(hasSlot and (setup or count>0))
end

function selectRandomly()
  if busy or #randomOptions<2 then return end
  local budget=DB.getValue(node,"budget",0)
  if multiple and budget>0 then
    local options={}
    for _,row in ipairs(rows.getWindows()) do
      local entry=row.getDatabaseNode()
      options[#options+1]={
        index=DB.getValue(entry,"index",0),
        cost=DB.getValue(entry,"cost",1),
        limit=DB.getValue(entry,"limit",budget),
      }
    end
    selected=QuickSummonRules.randomBudgetSelection(options,budget)
  else
    local index=randomOptions[math.random(#randomOptions)]
    if multiple then
      selected={[index]=randomCount}
    else
      choice=index
    end
  end
  refreshSelection()
end

function toggle(index, delta)
  if busy then return end
  if multiple then
    local current=selected[index] or 0
    if delta<0 or canAdd[index] then selected[index]=math.max(0,current+delta) end
  else
    choice=index
  end
  refreshSelection()
end

function pickSlot(index)
  if busy then return end
  local requested=index>0 and baseSlot+index-1 or 0
  if requested==level then
    local button=index==0 and ritual or self["slot"..index]
    button.setValue(1)
    return
  end
  busy=true
  QuickSummon.submit(node,"slot",requested)
end

function send(op)
  if busy then return end
  local indices={}
  if multiple then
    for index,count in pairs(selected) do
      for _=1,count do indices[#indices+1]=index end
    end
    table.sort(indices)
  elseif choice>0 then
    indices[1]=choice
  end
  busy=true
  QuickSummon.submit(node,op,nil,table.concat(indices,","))
end
