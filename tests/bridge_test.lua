local timers, tickers = {}, {}
C_Timer = { After=function(_,f) timers[#timers+1]=f end, NewTicker=function(_,f) local t={f=f,Cancel=function(s) s.dead=true end} tickers[#tickers+1]=t return t end }
local function flush() local t=timers timers={} for _,f in ipairs(t) do f() end end
function InCombatLockdown() return false end
function GetTime() return 0 end
SlashCmdList = {}
function hooksecurefunc(t,n,h) local o=t[n] t[n]=function(...) local r=o(...) h(...) return r end end
local frameScript
function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_,_,f) frameScript=f end} end
local calls={}
lastStops={}
local cur
ShortestPathForever={API={
 NavigateRoute=function(o,s) calls[#calls+1]=s[1] lastStops=s cur=1 return true end,
 CurrentStop=function(o) return cur end, Cancel=function() cur=nil calls[#calls+1]="cancel" end,
 RenameStop=function(o,i,t) calls[#calls+1]="rename:"..t end, Ended=function() end }}
local prof = setmetatable({}, {__index={arrowshow=true, maplines_enabled=true}})
ZGV={db={profile=prof}, Pointer={ FindTravelPath=function(self,w) self.DestinationWaypoint=w end, ClearWaypoints=function(self) self.DestinationWaypoint=nil end, RemoveWaypoint=function() end, ShowArrow=function() end, UpdateArrowVisibility=function() end, ClearAntsAndLines=function() end}, ShowWaypoints=function() end}
dofile(arg[1])
frameScript(nil,"ADDON_LOADED","ZygorShortestPath")
frameScript(nil,"PLAYER_ENTERING_WORLD")
assert(prof.arrowshow==false and prof.maplines_enabled==false, "options not hidden")
ZGV.Pointer:FindTravelPath({m=1429,x=0.4,y=0.6,title="|cffffffffTalk to Bob|r\n(in Goldshire)"})
flush()
assert(calls[1].map==1429 and calls[1].title=="Talk to Bob" and calls[1].hold, "nav")
assert(#lastStops==1, "single stop without guide")

-- Next steps: Zygor shows 4 steps -> current + 3 later; one is wrong-faction, one is at the same place as before it.
local function goal(map,x,y,text,extra) local g={map=map,x=x,y=y,GetText=function() return "|cffffffff"..text.."|r" end,IsVisible=function() return true end,IsInlineTravel=function() return extra=="inline" end} return g end
local function step(goals,ok) return {goals=goals,AreRequirementsMet=function() return ok~=false end} end
prof.showcountsteps = 5
ZGV.CurrentStepNum = 1
ZGV.CurrentGuide = {steps={
  step({goal(1429,0.4,0.6,"Bob")}),
  step({goal(1429,0.1,0.1,"road","inline"), goal(1429,0.5,0.5,"Kill wolves")}),
  step({goal(1429,0.9,0.9,"Horde only")},false),
  step({goal(1429,0.501,0.501,"Loot")}),
  step({{text="no coords"}}),
  {goals={goal(nil,nil,nil,"Kadrell")}, waypath={coords={{map=1432,x=0.3267,y=0.4972}}}, AreRequirementsMet=function() return true end},
  step({goal(1432,0.37,0.47,"Accept Honor")}),
  step({goal(1432,0.33,0.50,"Turn in Honor")}),
  step({goal(1455,0.65,0.88,"Warrior trainer")},false),
  step({goal(1455,0.10,0.10,"Too far")}),
}}
calls = {}
SlashCmdList.ZYGORSHORTESTPATH("on")
-- Fills to 5 stops past skipped steps; the patrolling NPC's path start is a stop; step 10 is not needed.
assert(#lastStops==5, "expected 5 stops, got "..#lastStops)
assert(lastStops[2].x==0.5 and lastStops[2].title=="Étape 2 : Kill wolves", lastStops[2].title)
assert(lastStops[3].map==1432 and lastStops[3].x==0.3267 and lastStops[3].title=="Étape 6 : Kadrell", lastStops[3].title)
assert(lastStops[4].title=="Étape 7 : Accept Honor" and lastStops[5].title=="Étape 8 : Turn in Honor", lastStops[5].title)
prof.showcountsteps = 2
SlashCmdList.ZYGORSHORTESTPATH("on")
assert(#lastStops==2, "follows Zygor's count")
prof.showcountsteps = 5
SlashCmdList.ZYGORSHORTESTPATH("etapes")
assert(#lastStops==1, "ahead off")
SlashCmdList.ZYGORSHORTESTPATH("etapes")
calls = {}
ZGV.Pointer.DestinationWaypoint.title="Talk to Bob again"
tickers[1].f()
assert(calls[1]=="rename:Talk to Bob again", tostring(calls[1]))
ZGV.Pointer:ClearWaypoints() flush()
assert(calls[2]=="cancel")
SlashCmdList.ZYGORSHORTESTPATH("off")
assert(prof.arrowshow==true and prof.maplines_enabled==true, "restore")
print("ALL OK")
