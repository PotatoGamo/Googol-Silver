local c="{[\"addons\"]={},[\"apis\"]={[\"goroutine\"]=\"--[[  goroutine API\\\
\\\
Simple interface for multitasking with coroutines. \\\
--]]\\\
\\\
local gotTerminate=false\\\
local active\\\
local loaded=false\\\
\\\
local termNative={\\\
  restore=term.restore,\\\
  redirect=term.redirect,\\\
}\\\
\\\
function isActive()\\\
  return active\\\
end\\\
\\\
local activeRoutines = { }\\\
local eventAssignments = { }\\\
local entryRoutine\\\
local rootRoutine\\\
local passEventTo=nil\\\
local numActiveCoroutines=0\\\
local isRunning=false\\\
\\\
function getInternalState()\\\
  return active, activeRoutines,eventAssignments,entryRoutine,\\\
    rootRoutine,passEventTo,numActiveCoroutines,isRunning\\\
end\\\
\\\
if goroutine then\\\
  active, activeRoutines,eventAssignments,entryRoutine,\\\
  rootRoutine,passEventTo,numActiveCoroutines,isRunning=goroutine.getInternalState()\\\
  \\\
else\\\
  active=false\\\
  activeRoutines = { }\\\
  eventAssignments = { }\\\
  entryRoutine=nil\\\
  rootRoutine=nil\\\
  passEventTo=nil\\\
  numActiveCoroutines=0\\\
  isRunning=false\\\
end\\\
\\\
loaded=true\\\
\\\
local function findCoroutine(co)\\\
  for _,routine in pairs(activeRoutines) do\\\
    if routine.co==co then\\\
      return routine\\\
    end\\\
  end\\\
  return nil\\\
end\\\
\\\
function findNamedCoroutine(name)\\\
  return activeRoutines[name]\\\
end\\\
\\\
function running()\\\
  return findCoroutine(coroutine.running())\\\
end\\\
\\\
local function validateCaller(funcName)\\\
  local callingRoutine=running()  \\\
  if callingRoutine==nil then\\\
    error(funcName..\\\" can only be called by a coroutine running under goroutine!\\\")\\\
  end\\\
  return callingRoutine\\\
end\\\
\\\
function assignEvent(assignTo,event,...)  \\\
  --get the routine calling this funciton\\\
  local callingRoutine=validateCaller(\\\"assignEvent\\\")\\\
  if callingRoutine~=entryRoutine then\\\
    return false, \\\"assignEvent: only main routine, passed to run(..), can assign events!\\\"\\\
  end\\\
  --get the assignee\\\
  local assignee=callingRoutine\\\
  if assignTo~=nil and assignTo~=callingRoutine.name then\\\
    assignee=findNamedCoroutine(assignTo)\\\
    if assignee==nil then\\\
      return false, \\\"assignEvent: named coroutine not found!\\\"\\\
    end\\\
  end\\\
    \\\
  --is this event already assigned elsewhere?\\\
  if eventAssignments[event]~=nil then  \\\
    return false,\\\"This event assignment conflicts with an existing assignment!\\\"\\\
  end    \\\
  --still here? good, no conflict then\\\
  eventAssignments[event]={co=assignee,assignedBy=callingRoutine}\\\
  return true\\\
end\\\
\\\
function passEvent(passTo)\\\
  if passTo==nil then\\\
    passEventTo=\\\"\\\"\\\
  else\\\
    passEventTo=passTo\\\
  end\\\
end\\\
\\\
  \\\
function releaseEvent(event)\\\
  local callingRoutine=validateCaller(\\\"releaseEvent\\\")  \\\
  local ass=eventAssignments[event]\\\
  \\\
  if ass~=nil then\\\
    if caller.co~=entryRoutine and caller~=ass.assignedBy and caller~=ass.routine then\\\
      return false, \\\"Event can only be released by the assigner, assignee, or the entry routine!\\\"\\\
    end\\\
    table.remove(eventAssignments,i)\\\
    return true\\\
  end\\\
  return false\\\
end\\\
  \\\
--called by goroutines to wait for an event to occur with some \\\
--set of optional event parameter filters\\\
function waitForEvent(event,...)  \\\
  co=validateCaller(\\\"waitForEvent\\\")\\\
  co.filters={event,...}\\\
  return coroutine.yield(\\\"goroutine_listening\\\")\\\
  \\\
end\\\
\\\
\\\
local function matchFilters(params,routine)\\\
  if params[1]==\\\"terminate\\\" then\\\
    return true\\\
  end\\\
  for j=1,#params do\\\
    if routine==nil or (routine.filters and routine.filters[j]~=nil and routine.filters[j]~=params[j]) then\\\
      return false\\\
    end\\\
  end\\\
  return true\\\
end\\\
\\\
\\\
local function sendEventTo(routine, params)\\\
  if routine.dead then\\\
    return\\\
  end\\\
  \\\
  termNative.redirect(routine.redirect[#routine.redirect])\\\
  local succ,r1=coroutine.resume(routine.co,unpack(params))\\\
  termNative.restore()\\\
  \\\
  --did it die or terminate?\\\
  if succ==false or coroutine.status(routine.co)==\\\"dead\\\" then\\\
    --it's dead, remove it from active\\\
    --if there's an error, send coroutine_error\\\
    if r1~=nil then\\\
      os.queueEvent(\\\"coroutine_error\\\",routine.name,r1)\\\
    end    \\\
    --send coroutine_end\\\
    routine.dead=true\\\
  --not dead, is it waiting for an event?\\\
  else\\\
    --\\\"goroutine_listening\\\" indicates it yielded via coroutine.waitForEvent\\\
    --which has had filters set already\\\
    if r1~=\\\"goroutine_listening\\\" then\\\
      --Add to eventListeners\\\
      routine.filters={r1}\\\
    end\\\
  end\\\
end\\\
\\\
local function _spawn(name,method,redirect,parent,args)\\\
    if activeRoutines[name] then\\\
      return nil, \\\"Couldn't spawn; a coroutine with that name already exists!\\\"\\\
    end\\\
    \\\
    local routine={name=name,co=coroutine.create(method),redirect={redirect}, parent=parent,children={}}\\\
    if routine.co==nil then\\\
      error(\\\"Failed to create coroutine '\\\"..name..\\\"'!\\\")\\\
    end\\\
    parent.children[#parent.children+1]=routine\\\
    activeRoutines[name]=routine\\\
    os.queueEvent(\\\"coroutine_start\\\",name)\\\
\\\
\\\
    numActiveCoroutines=numActiveCoroutines+1\\\
    --run it a bit..\\\
    sendEventTo(routine,args)\\\
        \\\
    return routine\\\
end\\\
\\\
function spawnWithRedirect(name,method,redirect,...)\\\
  return _spawn(name,method,redirect,running(),{...})\\\
end\\\
\\\
local mon=peripheral.wrap(\\\"right\\\")\\\
\\\
function spawn(name,method,...)\\\
  local cur=running()\\\
  \\\
  return _spawn(name,method,cur.redirect[1],cur,{...})\\\
end\\\
\\\
local nilRedir = {\\\
  write = function() end,\\\
  getCursorPos = function() return 1,1 end,\\\
  setCursorPos = function() end,\\\
  isColor = function() return false end,\\\
  scroll = function() end,\\\
  setCursorBlink = function() end,\\\
  setTextColor = function() end,\\\
  getTextColor = function() end,\\\
  getTextSize = function() end,\\\
  setTextScale = function() end,\\\
  clear = function() end,\\\
  clearLine = function() end,\\\
  getSize = function() return 51,19 end,\\\
}\\\
\\\
function spawnBackground(name,method,...)\\\
  return _spawn(name,method,nilRedir,rootRoutine,{...})\\\
end\\\
\\\
function spawnPeer(name,method,...)\\\
  local cur=running()\\\
  return _spawn(name,method,cur.redirect[1],cur.parent,{...})\\\
end\\\
\\\
function spawnPeerWithRedirect(name,method,redirect,...)\\\
  local cur=running()\\\
  return _spawn(name,method,redirect,cur.parent,{...})\\\
end\\\
\\\
function spawnProgram(name,progName,...)\\\
  local cur=running()\\\
  return _spawn(name, function(...) os.run({}, ...) end,cur.redirect[1],cur,{...})\\\
end\\\
\\\
\\\
function list()\\\
  local l={}\\\
  local i=1\\\
  for name,_ in pairs(activeRoutines) do\\\
    l[i]=name\\\
    i=i+1\\\
  end\\\
  return l\\\
end\\\
\\\
function kill(name)\\\
  local routine=validateCaller(\\\"killCoroutine\\\")\\\
  if not routine then\\\
    return false, \\\"Must be called from a coroutine. How'd you even manage this?\\\"\\\
  end\\\
  local target=findNamedCoroutine(name)\\\
  if target then\\\
    if routine==target then\\\
      return false,\\\"You can't commit suicide!\\\"\\\
    end\\\
    --mark it dead\\\
    target.dead=true\\\
    return true\\\
  end\\\
  return false, \\\"coroutine not found\\\"\\\
end\\\
\\\
\\\
local function logCoroutineErrors()\\\
  while true do\\\
    local _, name, err=os.pullEventRaw(\\\"coroutine_error\\\")\\\
    if _~=\\\"terminate\\\" then\\\
      local file=fs.open(\\\"go.log\\\",\\\"a\\\")\\\
      file.write(\\\"coroutine '\\\"..tostring(name)..\\\"' crashed with the following error: \\\"..tostring(err)..\\\"\\\\n\\\")\\\
      file.close()\\\
    end\\\
  end\\\
end\\\
\\\
function run(main,modify,terminable,...)\\\
  if isRunning then\\\
    --spawn it\\\
    local cur=running()\\\
    local name=\\\"main\\\"\\\
    local i=1\\\
    while activeRoutines[name] do\\\
      i=i+1\\\
      name=\\\"main\\\"..i\\\
    end\\\
    if _spawn(name,main,cur.redirect[1],cur,{...}) then\\\
      --wait for it to die\\\
      while true do \\\
        local e={os.pullEventRaw()}\\\
        if modify then e = modify(e) end\\\
        if e[1]==\\\"coroutine_end\\\" and e[2]==name then\\\
          return\\\
        elseif e[1]==\\\"coroutine_error\\\" and e[2]==name then\\\
          error(e[3])\\\
          return  \\\
        end\\\
      end\\\
    else\\\
      error(\\\"Couldn't spawn main coroutine \\\"..name..\\\"!\\\")\\\
    end\\\
    \\\
  end\\\
  \\\
  --hook term.redirect and term.restore\\\
  local function term_redirect(target)\\\
    --push redirect to current term's stack\\\
    local co=running()\\\
    co.redirect[#co.redirect+1]=target\\\
    --undo the current redirection then redirect\\\
    termNative.restore()\\\
    termNative.redirect(target)\\\
  end\\\
\\\
  local function term_restore()\\\
    local co=running()\\\
    --do nothing unless they've got more than 1 redirect in their stack\\\
    if #co.redirect>1 then\\\
      table.remove(co.redirect,#co.redirect)\\\
      --undo current redirection and restore to new end of stack\\\
      termNative.restore()\\\
      termNative.redirect(co.redirect[#co.redirect])\\\
    end\\\
  end\\\
\\\
  termNative.redirect=term.redirect\\\
  termNative.restore=term.restore\\\
  term.redirect=term_redirect\\\
  term.restore=term_restore\\\
  \\\
    \\\
  --make the object for the root coroutine (this one)\\\
  rootRoutine={\\\
    co=coroutine.running(),\\\
    name=\\\"root\\\",\\\
    redirect={term.native},\\\
    parent=nil,   \\\
    children={}\\\
  }\\\
  \\\
  isRunning=true\\\
  --default terminable to true\\\
  if terminable==nil then \\\
    terminable=true \\\
  end\\\
  \\\
  --start the main coroutine for the process\\\
  entryRoutine=_spawn(\\\"main\\\",main,term.native,rootRoutine,{...})\\\
  --begin with routine 1\\\
  --gooo!\\\
  local params={}\\\
  while numActiveCoroutines>0 do      \\\
    --grab an event\\\
    params={os.pullEventRaw()}\\\
    if modify then params = modify(params) end\\\
    if terminable and params[1]==\\\"terminate\\\" then  \\\
      gotTerminate=true\\\
    end\\\
    local assigned=eventAssignments[params[1]]~=nil\\\
    local assignedTo=assigned and eventAssignments[params[1]].co or nil\\\
    local alreadyHandledBy={}\\\
    --set passTo to empty string, meaning anyone listening\\\
    passEventTo=\\\"\\\"\\\
    while assignedTo~=nil do\\\
      --set this to nil first\\\
      passEventTo=nil\\\
      --send to assigned guy, if he matches, else break\\\
      if matchFilters(params,assignedTo) then\\\
        sendEventTo(assignedTo,params)\\\
      else\\\
        passEventTo=\\\"\\\"\\\
        break\\\
      end\\\
      --add him to the list of guys who've handled this already\\\
      alreadyHandledBy[assignedTo]=true\\\
      --set assignedTo to whatever passTo was\\\
      if passEventTo==\\\"\\\" then\\\
        assignedTo=nil\\\
      elseif passEventTo~=nil then\\\
        assignedTo=findNamedCoroutine(passEventTo)\\\
      else\\\
        assignedTo=nil\\\
      end\\\
    end\\\
    --if it was assigned to nobody, or they passed to everybody..\\\
    if passEventTo==\\\"\\\" then\\\
      for _,routine in pairs(activeRoutines) do\\\
        --if they haven't handled it already via assignments above..\\\
        if not alreadyHandledBy[routine] and not routine.dead then\\\
          local match=matchFilters(params,routine)\\\
          --if it matched, or this routine has never run...\\\
          if match then\\\
            sendEventTo(routine,params)\\\
          end        \\\
        end\\\
      end\\\
    end\\\
    --clean up any dead coroutines\\\
    local dead={}\\\
    local function listChildren(routine,list)\\\
      for i=1,#routine.children do\\\
        if not routine.children[i].dead then\\\
          list[routine.children[i].name]=routine.children[i]\\\
          listChildren(routine.children[i],list)\\\
        end\\\
      end\\\
    end\\\
    for name,routine in pairs(activeRoutines) do\\\
      if routine.dead then\\\
        dead[name]=routine\\\
        listChildren(routine,dead)\\\
      end\\\
    end\\\
    for name,routine in pairs(dead) do\\\
      os.queueEvent(\\\"coroutine_end\\\",routine.name)\\\
      activeRoutines[name]=nil\\\
      numActiveCoroutines=numActiveCoroutines-1\\\
      local parent=routine.parent\\\
      if not parent.dead then\\\
        --find and remove from children\\\
        for i=1,#parent.children do\\\
          if parent.children[i]==routine then\\\
            table.remove(parent.children,i)\\\
            break\\\
          end\\\
        end\\\
      end\\\
    end\\\
    \\\
    --release all events assigned to dead coroutines\\\
    local remove={}\\\
    for k,v in pairs(eventAssignments) do      \\\
      if dead[eventAssignments[k].co.name] then\\\
        table.insert(remove,k)\\\
      end\\\
    end\\\
    \\\
    for i=1,#remove do\\\
      eventAssignments[remove[i]]=nil\\\
    end\\\
  end\\\
  \\\
  --Should I send every remaining process a terminate event, regardless \\\
  --of what they were waiting on, so they can do cleanup? Could cause\\\
  --errors in some cases...\\\
  --[[\\\
  for k,v in activeRoutines do\\\
    coroutine.resume(v.co,\\\"terminate\\\")\\\
  end\\\
  --]]\\\
  \\\
  activeRoutines={}\\\
  eventAssignments = { }\\\
  passEventTo=nil\\\
  entryRoutine=nil  \\\
  rootRoutine=nil\\\
  isRunning=false\\\
\\\
  --remove hooks from term.redirect and .restore\\\
  term.redirect=termNative.redirect\\\
  term.restore=termNative.restore\\\
  \\\
end\\\
\\\
function launch(sh)\\\
  if not active then\\\
    active=true\\\
    sh=sh or \\\"rom/programs/shell\\\"\\\
    term.clear()\\\
    term.setCursorPos(1,1)\\\
    run(\\\
      function() \\\
        spawnBackground(\\\"errLogger\\\",logCoroutineErrors)\\\
        os.run({},sh)\\\
      end\\\
    )\\\
    os.shutdown()\\\
  end\\\
end\",[\"redirect\"]=\"local trueCursor={term.getCursorPos()}\\\
\\\
local redirectBufferBase = {\\\
    write=\\\
      function(buffer,...)\\\
        local cy=buffer.curY\\\
        if cy>0 and cy<=buffer.height then\\\
          local text=table.concat({...},\\\" \\\")\\\
          local cx=buffer.curX\\\
          local px, py\\\
          if buffer.isActive and not buffer.cursorBlink then\\\
            term.native.setCursorPos(cx+buffer.scrX, cy+buffer.scrY)\\\
          end\\\
          for i=1,#text do\\\
            if cx>0 and cx<=buffer.width then\\\
              local curCell=buffer[cy][cx]\\\
              local char,textColor,backgroundColor=string.char(text:byte(i)),buffer.textColor,buffer.backgroundColor\\\
              if buffer[cy].isDirty or curCell.char~=char or curCell.textColor~=textColor or curCell.backgroundColor~=backgroundColor then\\\
                buffer[cy][cx].char=char\\\
                buffer[cy][cx].textColor=textColor\\\
                buffer[cy][cx].backgroundColor=backgroundColor\\\
                buffer[cy].isDirty=true\\\
              end\\\
            end\\\
            cx=cx+1\\\
          end\\\
          buffer.curX=cx\\\
          if buffer.isActive then\\\
            buffer.drawDirty()\\\
            if not buffer.cursorBlink then\\\
              trueCursor={cx+buffer.scrX-1,cy+buffer.scrY-1}\\\
              term.native.setCursorPos(unpack(trueCursor))\\\
            end\\\
          end\\\
        end\\\
      end,\\\
      \\\
    setCursorPos=\\\
      function(buffer,x,y)\\\
        buffer.curX=math.floor(x)\\\
        buffer.curY=math.floor(y)\\\
        if buffer.isActive and buffer.cursorBlink then\\\
          term.native.setCursorPos(x+buffer.scrX-1,y+buffer.scrY-1)\\\
          trueCursor={x+buffer.scrX-1,y+buffer.scrY-1}\\\
        end\\\
      end,\\\
      \\\
    getCursorPos=\\\
      function(buffer)\\\
        return buffer.curX,buffer.curY\\\
      end,\\\
      \\\
    scroll=\\\
      function(buffer,offset)\\\
        for j=1,offset do\\\
          local temp=table.remove(buffer,1)\\\
          table.insert(buffer,temp)\\\
          for i=1,#temp do\\\
            temp[i].char=\\\" \\\"\\\
            temp[i].textColor=buffer.textColor\\\
            temp[i].backgroundColor=buffer.backgroundColor\\\
          end\\\
        end\\\
        if buffer.isActive then\\\
          term.redirect(term.native)\\\
          buffer.blit()\\\
          term.restore()\\\
        end\\\
      end,\\\
      \\\
    isColor=\\\
      function(buffer)\\\
        return buffer._isColor\\\
      end,\\\
      \\\
    isColour=\\\
      function(buffer)\\\
        return buffer._isColor\\\
      end,\\\
      \\\
    clear=\\\
      function(buffer)\\\
        for y=1,buffer.height do\\\
          for x=1,buffer.width do\\\
            buffer[y][x]={char=\\\" \\\",textColor=buffer.textColor,backgroundColor=buffer.backgroundColor}\\\
          end\\\
        end\\\
        if buffer.isActive then\\\
          term.redirect(term.native)\\\
          buffer.blit()\\\
          term.restore()\\\
        end\\\
      end,\\\
      \\\
    clearLine=\\\
      function(buffer)\\\
        local line=buffer[buffer.curY]\\\
        local fg,bg = buffer.textColor, buffer.backgroundColor\\\
        for x=1,buffer.width do\\\
          line[x]={char=\\\" \\\",textColor=fg,backgroundColor=bg}\\\
        end\\\
        buffer[buffer.curY].isDirty=true\\\
        if buffer.isActive then\\\
          buffer.drawDirty()\\\
        end\\\
      end,\\\
      \\\
    setCursorBlink=\\\
      function(buffer,onoff)\\\
        buffer.cursorBlink=onoff\\\
        if buffer.isActive then\\\
          term.native.setCursorBlink(onoff)\\\
          if onoff then\\\
            term.native.setCursorPos(buffer.curX,buffer.curY)\\\
            trueCursor={buffer.curX,buffer.curY}\\\
          end\\\
        end\\\
      end,\\\
      \\\
    getSize=\\\
      function(buffer)\\\
        return buffer.width, buffer.height\\\
      end,\\\
      \\\
    setTextColor=\\\
      function(buffer,color)\\\
        buffer.textColor=color\\\
        if buffer.isActive then\\\
          if term.native.isColor() or color==colors.black or color==colors.white then\\\
            term.native.setTextColor(color)\\\
          end\\\
        end\\\
      end,\\\
      \\\
    setTextColour=\\\
      function(buffer,color)\\\
        buffer.textColor=color\\\
        if buffer.isActive then\\\
          if term.native.isColor() or color==colors.black or color==colors.white then\\\
            term.native.setTextColor(color)\\\
          end\\\
        end\\\
      end,\\\
      \\\
    setBackgroundColor=\\\
      function(buffer,color)\\\
        buffer.backgroundColor=color\\\
        if buffer.isActive then\\\
          if term.native.isColor() or color==colors.black or color==colors.white then\\\
        term.native.setBackgroundColor(color)\\\
          end\\\
        end\\\
      end,\\\
      \\\
    setBackgroundColour=\\\
      function(buffer,color)\\\
        buffer.backgroundColor=color\\\
        if buffer.isActive then\\\
          if term.native.isColor() or color==colors.black or color==colors.white then\\\
        term.native.setBackgroundColor(color)\\\
          end\\\
        end\\\
      end,\\\
    \\\
    resize=\\\
      function(buffer,width,height)\\\
        if buffer.width~=width or buffer.height~=height then\\\
          local fg, bg=buffer.textColor, buffer.backgroundColor\\\
          if width>buffer.width then\\\
            for y=1,buffer.height do\\\
              for x=#buffer[y]+1,width do\\\
                buffer[y][x]={char=\\\" \\\",textColor=fg,backgroundColor=bg}\\\
              end\\\
            end\\\
          end\\\
\\\
          if height>buffer.height then\\\
            local w=width>buffer.width and width or buffer.width\\\
            for y=#buffer+1,height do\\\
              local row={}           \\\
              for x=1,width do\\\
                row[x]={char=\\\" \\\",textColor=fg,backgroundColor=bg}\\\
              end\\\
              buffer[y]=row\\\
            end\\\
          end\\\
          buffer.width=width\\\
          buffer.height=height\\\
        end\\\
      end,\\\
      \\\
    blit=\\\
      function(buffer,sx,sy,dx, dy, width,height)\\\
        sx=sx or 1\\\
        sy=sy or 1\\\
        dx=dx or buffer.scrX\\\
        dy=dy or buffer.scrY\\\
        width=width or buffer.width\\\
        height=height or buffer.height\\\
        \\\
        local h=sy+height>buffer.height and buffer.height-sy or height-1\\\
        for y=0,h do\\\
          local row=buffer[sy+y]\\\
          local x=0\\\
          local cell=row[sx]\\\
          local fg,bg=cell.textColor,cell.backgroundColor\\\
          local str=\\\"\\\"\\\
          local tx=x\\\
          while true do\\\
            str=str..cell.char\\\
            x=x+1\\\
            if x==width or sx+x>buffer.width then\\\
              break\\\
            end\\\
            cell=row[sx+x]\\\
            if cell.textColor~=fg or cell.backgroundColor~=bg then\\\
              --write\\\
              term.setCursorPos(dx+tx,dy+y)\\\
              term.setTextColor(fg)\\\
              term.setBackgroundColor(bg)\\\
              term.write(str)\\\
              str=\\\"\\\"\\\
              tx=x\\\
              fg=cell.textColor\\\
              bg=cell.backgroundColor              \\\
            end\\\
          end \\\
          term.setCursorPos(dx+tx,dy+y)\\\
          term.setTextColor(fg)\\\
          term.setBackgroundColor(bg)\\\
          term.write(str)\\\
        end\\\
      end,\\\
      \\\
    drawDirty =\\\
      function(buffer)\\\
        term.redirect(term.native)\\\
        for y=1,buffer.height do\\\
          if buffer[y].isDirty then\\\
            term.redirect(term.native)\\\
            buffer.blit(1,y,buffer.scrX,buffer.scrY+y-1,buffer.width,buffer.height)\\\
            term.restore()\\\
            buffer[y].isDirty=false\\\
          end\\\
        end\\\
        term.restore()\\\
      end,\\\
      \\\
    makeActive =\\\
      function(buffer,posX, posY)\\\
        posX=posX or 1\\\
        posY=posY or 1\\\
        buffer.scrX=posX\\\
        buffer.scrY=posY\\\
        term.redirect(term.native)\\\
        buffer.blit(1,1,posX,posY,buffer.width,buffer.height)\\\
        term.setCursorPos(buffer.curX,buffer.curY)\\\
        term.setCursorBlink(buffer.cursorBlink)\\\
        term.setTextColor(buffer.textColor)\\\
        term.setBackgroundColor(buffer.backgroundColor)\\\
        buffer.isActive=true\\\
        term.restore()\\\
      end,\\\
      \\\
    isBuffer = true,\\\
    \\\
  }\\\
    \\\
\\\
function createRedirectBuffer(width,height,fg,bg,isColor)\\\
   bg=bg or colors.black\\\
   fg=fg or colors.white\\\
   if isColor==nil then\\\
     isColor=term.isColor()\\\
   end\\\
   local buffer={}\\\
   \\\
   do \\\
     local w,h=term.getSize()\\\
     width,height=width or w,height or h\\\
   end\\\
   \\\
   for y=1,height do\\\
     local row={}\\\
     for x=1,width do\\\
       row[x]={char=\\\" \\\",textColor=fg,backgroundColor=bg}\\\
     end\\\
     buffer[y]=row\\\
   end\\\
   buffer.scrX=1\\\
   buffer.scrY=1\\\
   buffer.width=width\\\
   buffer.height=height\\\
   buffer.cursorBlink=false\\\
   buffer.textColor=fg\\\
   buffer.backgroundColor=bg\\\
   buffer._isColor=isColor\\\
   buffer.curX=1\\\
   buffer.curY=1\\\
   \\\
   local meta={}\\\
   local function wrap(f,o)\\\
     return function(...)\\\
         return f(o,...)\\\
       end\\\
   end\\\
   for k,v in pairs(redirectBufferBase) do\\\
     if type(v)==\\\"function\\\" then\\\
       meta[k]=wrap(v,buffer)\\\
     else\\\
       meta[k]=v\\\
     end\\\
   end\\\
   setmetatable(buffer,{__index=meta})\\\
   return buffer\\\
end\",},[\"pages\"]={[\"blank\"]=\"term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.clear()\",[\"error\"]={[\"page\"]=\"term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.setTextColor(theme.get(\\\"text-color\\\"))\\\
term.clear()\\\
local w, h = term.getSize()\\\
if address.url and address.search then\\\
	print(\\\"\\\")\\\
	cPrint(unescape(address.search:match(\\\"name=([^&]+)\\\"))..\\\" crashed!\\\\n\\\")\\\
	local msg = unescape(address.search:match(\\\"[%?&]msg=([^&]+)\\\"))\\\
	for i = 1, msg:len(), w-5 do\\\
		cPrint(msg:sub(i, i+w-5))\\\
	end\\\
else\\\
	cPrint(\\\"Error\\\")\\\
end\",[\"invalid\"]=\"cPrint(\\\"Invalid URL\\\")\",[\"timeout\"]=\"cPrint(\\\"Request Timeout\\\")\",[\"unknown\"]=\"cPrint(\\\"Unknown Host\\\")\",},[\"help\"]=\"term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.clear()\",[\"logo.nfp\"]=\"bbbbbb                          e                \\\
b                               e                \\\
b                               e                \\\
b  bbb  eeeee 44444 bbbbb 55555 e                \\\
b    b  e   e 4   4 b   b 5   5 e                \\\
b    b  e   e 4   4 b   b 5   5 e                \\\
bbbbbb  eeeee 44444 bbbbb 55555 eee              \\\
                        b                        \\\
                    bbbbb\",[\"home\"]=\"local w, h = term.getSize()\\\
local draw_logo = loadImage(about.get(\\\"logo.nfp\\\"))\\\
term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.clear()\\\
draw_logo(w/2-34/2, 3)\\\
\\\
term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.setTextColor(theme.get(\\\"text-color\\\"))\\\
term.setCursorPos(w-21, h)\\\
term.write(\\\"Need help? Click \\\") term.setTextColor(theme.get(\\\"link-color\\\")) term.write(\\\"here\\\")\\\
\\\
term.setCursorPos(2, 14)\\\
term.setBackgroundColor(theme.get(\\\"search-bar-color\\\"))\\\
term.setTextColor(theme.get(\\\"search-bar-text\\\"))\\\
print(string.rep(\\\" \\\", w-2))\\\
\\\
function events()\\\
	while true do\\\
		local evt = {os.pullEvent()}\\\
		if evt[1] == \\\"mouse_click\\\" and evt[3] < w and evt[3] > w-5 and evt[4] == h then\\\
			navigate(\\\"about:help\\\")\\\
		end\\\
	end\\\
end\\\
function input()\\\
	term.setCursorPos(3, 14)\\\
	input = read()\\\
	navigate(\\\"about:search?q=\\\"..escape(input))\\\
end\\\
parallel.waitForAny(input, events)\",[\"search\"]=\"term.setBackgroundColor(theme.get(\\\"background-color\\\"))\\\
term.setTextColor(theme.get(\\\"text-color\\\"))\\\
term.clear()\\\
\\\
print(address.search)\",},[\"themes\"]={[\"default\"]=\"{\\\
	[\\\"background-color\\\"] = colors.white,\\\
	[\\\"text-color\\\"] = colors.black,\\\
	\\\
	[\\\"address-bar-text\\\"] = colors.black,\\\
	[\\\"address-bar-background\\\"] = colors.lightGray,\\\
	[\\\"address-bar-cursor\\\"] = colors.gray,\\\
	\\\
	[\\\"exit-button-color\\\"] = colors.red,\\\
	\\\
	[\\\"search-bar-color\\\"] = colors.lightGray,\\\
	[\\\"search-bar-text\\\"] = colors.black,\\\
	[\\\"link-color\\\"] = colors.blue,\\\
}\",},}"function makeDir(table,dir) if not fs.exists(dir) then fs.makeDir(dir) end for k, v in pairs(table) do if type(v)=='table' then makeDir(v,dir..'/'..k) else local fileH=fs.open(dir..'/'..k,'w') fileH.write(v) fileH.close() end end end tArgs={...} if #tArgs<1 then print('Usage: unpackager <destination>') else makeDir(textutils.unserialize(c),shell.resolve(tArgs[1])) print('Succ: Successfully extracted package') end