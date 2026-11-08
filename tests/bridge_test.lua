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
local cur
ShortestPathForever={API={
 NavigateRoute=function(o,s) calls[#calls+1]=s[1] cur=1 return true end,
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
ZGV.Pointer.DestinationWaypoint.title="Kill wolves"
tickers[1].f()
assert(calls[2]=="rename:Kill wolves", tostring(calls[2]))
ZGV.Pointer:ClearWaypoints() flush()
assert(calls[3]=="cancel")
SlashCmdList.ZYGORSHORTESTPATH("off")
assert(prof.arrowshow==true and prof.maplines_enabled==true, "restore")
print("ALL OK")
