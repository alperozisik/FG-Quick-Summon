function onInit()
  chosen.setValue("")
  if Session.IsHost then
    local path=DB.getValue(getDatabaseNode(),"reference","")
    if path~="" then
      npcshortcut.setValue("npc",path)
      npcshortcut.setVisible(true)
    end
  end
end

function add(delta)
  windowlist.window.toggle(DB.getValue(getDatabaseNode(),"index",0),delta)
end

function showCount(count,maximum)
  less.setVisible(maximum~=nil)
  less.setEnabled(count>0)
  more.setEnabled(maximum==nil or count<maximum)
  chosen.setValue(maximum and string.format("%d / %d",count,maximum)
    or (count>0 and tostring(count) or ""))
end
