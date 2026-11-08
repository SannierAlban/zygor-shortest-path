-- Zygor + Shortest Path: hands Zygor's current destination to Shortest Path Forever.
--
-- Neither addon is modified. Zygor is only observed (hooksecurefunc on its Pointer, plus a slow poll as a safety
-- net) and Shortest Path is driven through its public API, ShortestPathForever.API, the same way its own RestedXP
-- integration does it. If either addon changes its internals, the bridge stops quietly instead of breaking them.

local OWNER = "Zygor"
local POLL_SECONDS = 1

local defaults = {
	enabled = true, -- send Zygor's destinations to Shortest Path
	hideZygorArrow = true, -- one arrow on screen: Shortest Path's
	hideZygorLines = true, -- one route on the map: Shortest Path's
	ahead = true, -- also send the next steps Zygor shows (its "steps to show" setting), drawn on the world map
}

-- Zygor shows at most this many steps; "all" (0) is capped here too.
local MAX_STEPS = 5
-- How far past the current step to look for places when steps are skipped (no coordinates, other class...).
local LOOKAHEAD = 15
-- Two stops closer than this on one map (a fraction of the map, about half a percent) are one place.
local SAME_PLACE = 0.005

---@type table
local db
-- Zygor settings as they were before the bridge changed them, restored on /zsp off or when an option is turned off.
---@type table
local saved

-- The route last handed to Shortest Path: every stop's "map:x:y", rounded to a tenth of a map percent, joined.
local sentKey
local sentTitle
local hooked = false
local pending = false
-- A destination Shortest Path could not plan, and when: retried after RETRY_SECONDS rather than every poll.
local failedKey, failedAt
local RETRY_SECONDS = 10

local function Print(message)
	print("|cff33ff99Zygor+SP|r " .. message)
end

local function API()
	return ShortestPathForever and ShortestPathForever.API
end

local function Zygor()
	local zgv = _G.ZGV
	return zgv and zgv.db and zgv.db.profile and zgv.Pointer and zgv
end

local function Key(map, x, y)
	return string.format("%d:%d:%d", map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
end

-- Zygor titles carry colour codes and a "(in Zone)" second line; Shortest Path wants one plain line.
local function CleanTitle(title)
	if type(title) ~= "string" or title == "" then
		return "Zygor"
	end
	title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	title = title:match("^[^\n]*") or title
	title = title:gsub("^%s+", ""):gsub("%s+$", "")
	return title ~= "" and title or "Zygor"
end

-- Zygor's own options, switched through its own settings so it hides its arrow and lines itself.
local function ApplyZygorOption(option, hide)
	local zgv = Zygor()
	if not zgv then
		return
	end
	local profile = zgv.db.profile
	if hide then
		if saved[option] == nil then
			saved[option] = profile[option]
		end
		profile[option] = false
	elseif saved[option] ~= nil then
		profile[option] = saved[option]
		saved[option] = nil
	else
		return
	end
	local pointer = zgv.Pointer
	if option == "arrowshow" and pointer.UpdateArrowVisibility and not InCombatLockdown() then
		pcall(pointer.UpdateArrowVisibility, pointer)
	elseif option == "maplines_enabled" and pointer.ClearAntsAndLines then
		pcall(pointer.ClearAntsAndLines, pointer)
	end
end

local function ApplyZygorOptions()
	ApplyZygorOption("arrowshow", db.enabled and db.hideZygorArrow)
	ApplyZygorOption("maplines_enabled", db.enabled and db.hideZygorLines)
end

local function Cancel()
	local api = API()
	if api and sentKey and api.CurrentStop(OWNER) then
		api.Cancel(OWNER)
	end
	sentKey, sentTitle = nil, nil
end

-- Zygor's destination, or nil when it has none worth following.
local function Destination()
	local zgv = Zygor()
	local way = zgv and zgv.Pointer.DestinationWaypoint
	if type(way) ~= "table" or way.type == "corpse" then
		return nil -- Shortest Path guides you back to your corpse on its own.
	end
	local map, x, y = tonumber(way.m), tonumber(way.x), tonumber(way.y)
	if not (map and x and y) or map <= 0 or x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return map, x, y, CleanTitle(way.title or (way.goal and way.goal.GetText and way.goal:GetText()))
end

local function Try(method, object, ...)
	if type(method) ~= "function" then
		return nil
	end
	local ok, result = pcall(method, object, ...)
	if ok then
		return result
	end
	return nil
end

local function ValidPoint(map, x, y)
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if map and x and y and map > 0 and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		return map, x, y
	end
end

-- Where a step sends you: its first visible goto that is not inline travel, as Zygor's ShowWaypoints picks it,
-- else its last visible goto, else the start of its path (an NPC who walks a patrol has no fixed goto).
local function StepPlace(step)
	local last
	for _, goal in ipairs(step.goals or {}) do
		local map, x, y = tonumber(goal.map), tonumber(goal.x), tonumber(goal.y)
		if
			map and x and y and map > 0 and x >= 0 and x <= 1 and y >= 0 and y <= 1
			and goal.action ~= "mapmarker"
			and not goal.force_noway
			and Try(goal.IsVisible, goal) ~= false
		then
			last = { map = map, x = x, y = y, goal = goal }
			if not Try(goal.IsInlineTravel, goal) then
				return last
			end
		end
	end
	if last then
		return last
	end
	local path = type(step.waypath) == "table" and step.waypath.coords
	local first = type(path) == "table" and path[1]
	if type(first) == "table" then
		local map, x, y = ValidPoint(first.map or step.map, first.x, first.y)
		if map then
			-- Name the place after the step's first goal with text, such as "talk Mountaineer Kadrell".
			local goal = step.goals and step.goals[1]
			return { map = map, x = x, y = y, goal = goal }
		end
	end
end

local function StepTitle(num, goal)
	local text = goal and CleanTitle(Try(goal.GetText, goal)) or "Zygor"
	return text ~= "Zygor" and ("Étape %d : %s"):format(num, text) or ("Étape %d"):format(num)
end

-- How many stops to send: as many steps as Zygor's window shows ("steps to show", capped at MAX_STEPS).
local function StopCount()
	local count = tonumber(Zygor().db.profile.showcountsteps) or 1
	if count <= 0 or count > MAX_STEPS then
		count = MAX_STEPS
	end
	return count
end

-- The places of the steps after the current one, in guide order, up to LOOKAHEAD steps ahead: steps Zygor would hide
-- (wrong faction, class...) and steps without any place are left out, so the route can still fill its stops.
-- Titles are read only for the places a route uses (see Route).
local function Upcoming()
	local zgv = Zygor()
	local guide, current = zgv and zgv.CurrentGuide, zgv and tonumber(zgv.CurrentStepNum)
	if not (db.ahead and guide and type(guide.steps) == "table" and current) then
		return {}
	end
	local places = {}
	for num = current + 1, math.min(current + LOOKAHEAD, #guide.steps) do
		local step = guide.steps[num]
		if
			type(step) == "table"
			and (zgv.db.profile.showwrongsteps or Try(step.AreRequirementsMet, step) ~= false)
		then
			local place = StepPlace(step)
			if place then
				place.num = num
				places[#places + 1] = place
			end
		end
	end
	return places
end

local function SamePlace(a, b)
	return a.map == b.map and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= SAME_PLACE ^ 2
end

-- The current destination, then the next steps' places; a step at the place before it adds no stop.
local function Route()
	local map, x, y, title = Destination()
	if not map then
		return nil
	end
	local stops = { { map = map, x = x, y = y, title = title, hold = true } }
	local way = Zygor().Pointer.DestinationWaypoint
	-- A waypoint you set by hand in Zygor is not part of the guide: no guide steps after it.
	if way.type ~= "manual" then
		local count = StopCount()
		for _, place in ipairs(Upcoming()) do
			if #stops >= count then
				break
			end
			if not SamePlace(place, stops[#stops]) then
				local title = StepTitle(place.num, place.goal)
				stops[#stops + 1] = { map = place.map, x = place.x, y = place.y, title = title, hold = true }
			end
		end
	end
	local keys = {}
	for index, stop in ipairs(stops) do
		keys[index] = Key(stop.map, stop.x, stop.y)
	end
	return stops, table.concat(keys, "|")
end

local function Sync(force)
	pending = false
	local api = API()
	if not (db and db.enabled and api and Zygor()) then
		return
	end
	local stops, key = Route()
	if not stops then
		Cancel()
		return
	end
	local title = stops[1].title
	if key == sentKey and not force then
		-- Same place, new label: rename the stop without replanning.
		if title ~= sentTitle and api.CurrentStop(OWNER) and api.RenameStop then
			api.RenameStop(OWNER, api.CurrentStop(OWNER), title)
			sentTitle = title
		end
		return
	end
	-- Shortest Path refuses new journeys in combat; the poll retries once combat ends.
	if InCombatLockdown() then
		return
	end
	if key == failedKey and not force and GetTime() - failedAt < RETRY_SECONDS then
		return
	end
	-- hold: Zygor, not Shortest Path, decides when a step is done; the route is sent again as Zygor moves on.
	-- Shortest Path guides to the first stop (minimap and world map) and draws the later hops on the world map.
	local started = api.NavigateRoute(OWNER, stops)
	if started then
		sentKey, sentTitle, failedKey = key, title, nil
	else
		failedKey, failedAt = key, GetTime()
	end
end

-- Zygor calls these several times in a burst; one sync on the next frame is enough.
local function Schedule()
	if not pending then
		pending = true
		C_Timer.After(0, function()
			Sync(false)
		end)
	end
end

local function Hook()
	local zgv = Zygor()
	if hooked or not zgv then
		return
	end
	local pointer = zgv.Pointer
	for _, name in ipairs({ "FindTravelPath", "ClearWaypoints", "RemoveWaypoint", "ShowArrow" }) do
		if type(pointer[name]) == "function" then
			hooksecurefunc(pointer, name, Schedule)
		end
	end
	if type(zgv.ShowWaypoints) == "function" then
		hooksecurefunc(zgv, "ShowWaypoints", Schedule)
	end
	hooked = true
	ApplyZygorOptions()
	C_Timer.NewTicker(POLL_SECONDS, function()
		Sync(false)
	end)
	Schedule()
end

local function OnOff(value)
	return value and "|cff00ff00activé|r" or "|cffff5555désactivé|r"
end

local function Status()
	local api = API()
	Print(("liaison %s · étapes suivantes %s · flèche Zygor %s · tracé Zygor %s"):format(
		OnOff(db.enabled),
		db.ahead and "affichées" or "masquées",
		db.hideZygorArrow and "masquée" or "visible",
		db.hideZygorLines and "masqué" or "visible"
	))
	local stops = Route()
	if stops and #stops > 1 then
		for index = 2, #stops do
			Print(("  puis %s"):format(stops[index].title))
		end
	end
	local map, x, y, title = Destination()
	if map then
		Print(("destination Zygor : %s (carte %d, %.1f, %.1f)"):format(title, map, x * 100, y * 100))
	else
		Print("aucune destination Zygor en cours")
	end
	if api then
		local reason = api.Ended(OWNER)
		Print(("Shortest Path : %s%s"):format(
			api.CurrentStop(OWNER) and "suit Zygor" or "ne suit pas Zygor",
			reason and (" (dernier arrêt : " .. reason .. ")") or ""
		))
	end
end

SLASH_ZYGORSHORTESTPATH1 = "/zsp"
SlashCmdList.ZYGORSHORTESTPATH = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "on" then
		db.enabled = true
		ApplyZygorOptions()
		Sync(true)
	elseif command == "off" then
		db.enabled = false
		Cancel()
		ApplyZygorOptions()
	elseif command == "fleche" or command == "flèche" or command == "arrow" then
		db.hideZygorArrow = not db.hideZygorArrow
		ApplyZygorOptions()
	elseif command == "trace" or command == "tracé" or command == "lines" then
		db.hideZygorLines = not db.hideZygorLines
		ApplyZygorOptions()
	elseif command == "etapes" or command == "étapes" or command == "ahead" then
		db.ahead = not db.ahead
		Sync(true)
	elseif command == "go" or command == "resume" then
		-- Back to Zygor's destination after planning another journey in Shortest Path.
		Sync(true)
	elseif command ~= "" and command ~= "status" then
		Print("/zsp on|off — activer/couper la liaison")
		Print("/zsp go — reprendre la destination Zygor (après un autre trajet)")
		Print("/zsp etapes — afficher/masquer les étapes suivantes sur la grande carte")
		Print("/zsp fleche — afficher/masquer la flèche Zygor")
		Print("/zsp trace — afficher/masquer le tracé Zygor sur la carte")
		return
	end
	Status()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name ~= "ZygorShortestPath" then
			return
		end
		ZygorShortestPathDB = ZygorShortestPathDB or {}
		db = ZygorShortestPathDB
		for key, value in pairs(defaults) do
			if db[key] == nil then
				db[key] = value
			end
		end
		db.saved = db.saved or {}
		saved = db.saved
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Zygor builds its Pointer during its own startup; hook once it exists.
		if not hooked then
			Hook()
			local tries = 0
			local ticker
			ticker = C_Timer.NewTicker(2, function()
				tries = tries + 1
				Hook()
				if hooked or tries >= 30 then
					ticker:Cancel()
				end
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Schedule()
	end
end)
