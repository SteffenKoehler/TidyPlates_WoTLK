-- TPProf: misst die CPU-Zeit pro Addon über WoWs eingebautes Profiling und schreibt
-- ein Kampf- und Fehlerprotokoll in die SavedVariables (TPProfDB), damit es außerhalb
-- des Spiels ausgewertet werden kann. WoW schreibt die Datei bei /reload und beim Ausloggen.
--
-- Das Profiling (CVar scriptProfile) kostet selbst etwas Leistung und wirkt erst nach /reload,
-- deshalb nur zum Messen einschalten und danach wieder aus. FPS, Plaketten und Fehler
-- werden immer protokolliert (kostet praktisch nichts).
--
-- /tpprof on      Profiling einschalten (danach /reload)
-- /tpprof off     Profiling ausschalten (danach /reload)
-- /tpprof start   Messung neu starten
-- /tpprof         Bericht seit dem letzten Start
-- /tpprof kampf   Bericht im Chat nach jedem Kampf an/aus (gespeichert wird immer)
-- /tpprof log     Zeigt, was gespeichert ist
-- /tpprof clear   Gespeicherte Kämpfe und Fehler löschen

local PREFIX = "|cff33ff99TPProf:|r "
local TOP = 10
local SAVE_TOP = 15
local MIN_FIGHT = 5 -- kürzere Kämpfe nicht berichten/speichern
local MAX_FIGHTS = 40
local MAX_ERRORS = 50
local SAMPLE_INTERVAL = 0.5

local startTime
local fightStart

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function IsProfiling()
	return GetCVar("scriptProfile") == "1"
end

local function StartMeasure()
	ResetCPUUsage()
	startTime = GetTime()
end

-- Einheit eichen: Je nach Client liefert GetAddOnCPUUsage nicht Millisekunden. TPProf
-- rechnet 5 ms lang (gemessen mit der Stoppuhr debugprofilestop) und vergleicht das mit
-- der Zeit, die WoW ihm dafür anrechnet. Ergebnis: Millisekunden pro gelieferter Einheit.
local msPerUnit
local function Calibrate()
	if msPerUnit or not debugprofilestop then
		return msPerUnit or 1
	end
	UpdateAddOnCPUUsage()
	local before = GetAddOnCPUUsage("TPProf")
	local t0 = debugprofilestop()
	local x = 0
	while debugprofilestop() - t0 < 5 do
		x = x + 1
	end
	local elapsed = debugprofilestop() - t0
	UpdateAddOnCPUUsage()
	local used = GetAddOnCPUUsage("TPProf") - before
	if used > 0 then
		msPerUnit = elapsed / used
		-- Nahe 1 = schon Millisekunden; sonst gefundenen Faktor nutzen
		if msPerUnit > 0.5 and msPerUnit < 2 then
			msPerUnit = 1
		end
	end
	return msPerUnit or 1
end

-- CPU pro Addon seit StartMeasure, absteigend sortiert. nil, wenn Profiling aus ist.
local function CollectCPU()
	if not (IsProfiling() and startTime) then
		return
	end
	UpdateAddOnCPUUsage()
	local scale = Calibrate()
	local list, total = {}, 0
	for i = 1, GetNumAddOns() do
		-- TPProf selbst nicht mitzählen (enthält die Eichung beim Bericht)
		if IsAddOnLoaded(i) and GetAddOnInfo(i) ~= "TPProf" then
			local cpu = GetAddOnCPUUsage(i) * scale
			if cpu > 0 then
				list[#list + 1] = {name = (GetAddOnInfo(i)), cpu = cpu}
				total = total + cpu
			end
		end
	end
	table.sort(list, function(a, b) return a.cpu > b.cpu end)
	return list, total, scale
end

local function Report(label)
	if not IsProfiling() then
		Print("Profiling ist aus. Erst |cffffff00/tpprof on|r und dann /reload.")
		return
	end
	if not startTime then
		StartMeasure()
		Print("Messung gestartet.")
		return
	end
	local duration = GetTime() - startTime
	if duration <= 0 then
		return
	end
	local list, total, scale = CollectCPU()

	Print(format("%s %.1f s, alle Addons zusammen %.0f ms (%.1f ms pro Sekunde)",
		label or "Messung über", duration, total, total / duration))
	for i = 1, math.min(TOP, #list) do
		local e = list[i]
		Print(format("%2d. %-28s %7.1f ms  %5.2f ms/s  %4.1f%%",
			i, e.name, e.cpu, e.cpu / duration, total > 0 and e.cpu / total * 100 or 0))
	end
	if scale ~= 1 then
		Print(format("(Einheit geeicht: 1 Wert = %.0f ms)", scale))
	end
	-- Mit echtem Profiling brauchen die Addons zusammen mehrere ms pro Sekunde
	if duration > 30 and total / duration < 0.1 then
		Print("|cffff6600Achtung:|r Fast keine CPU-Zeit gemessen - das Profiling ist vermutlich nicht aktiv. "
			.. "Nach /tpprof on ist ein /reload nötig (der Client schaltet es bei jedem Spielstart wieder aus).")
	end
end

-------------------------------------------------------------------------------
-- Gemeinsame Angaben für Protokolleinträge
-------------------------------------------------------------------------------
local function Where()
	local zone = GetRealZoneText() or ""
	local sub = GetSubZoneText()
	if sub and sub ~= "" and sub ~= zone then
		zone = zone .. " / " .. sub
	end
	return zone
end

local function GroupInfo()
	local raid = GetNumRaidMembers()
	if raid > 0 then
		return "raid" .. raid
	end
	local party = GetNumPartyMembers()
	if party > 0 then
		return "party" .. (party + 1)
	end
	return "solo"
end

local function Profile()
	local tpt = TidyPlatesThreat
	if tpt and tpt.db and tpt.db.GetCurrentProfile then
		local ok, name = pcall(tpt.db.GetCurrentProfile, tpt.db)
		if ok then
			return name
		end
	end
end

local function Push(list, entry, max)
	list[#list + 1] = entry
	while #list > max do
		table.remove(list, 1)
	end
end

-------------------------------------------------------------------------------
-- Kampfprotokoll: FPS (min/Durchschnitt), sichtbare Plaketten, Lua-Speicher, Ziele
-------------------------------------------------------------------------------
local fight
local sampler = CreateFrame("Frame")
local nextSample = 0

local function CountPlates()
	local n = 0
	local kids = {WorldFrame:GetChildren()}
	for i = 1, #kids do
		local f = kids[i]
		if f.extended and f:IsShown() then
			n = n + 1
		end
	end
	return n
end

local function Sample()
	local fps = GetFramerate()
	if not fight.fpsMin or fps < fight.fpsMin then
		fight.fpsMin = fps
	end
	fight.fpsSum = fight.fpsSum + fps
	fight.samples = fight.samples + 1
	local plates = CountPlates()
	if plates > fight.platesMax then
		fight.platesMax = plates
	end
	fight.platesSum = fight.platesSum + plates
end

local function SamplerOnUpdate()
	local now = GetTime()
	if now >= nextSample then
		nextSample = now + SAMPLE_INTERVAL
		Sample()
	end
end

local function AddTarget()
	if not fight or not UnitExists("target") or UnitIsFriend("player", "target") then
		return
	end
	local name = UnitName("target")
	if name and not fight.targetSet[name] and #fight.targets < 8 then
		fight.targetSet[name] = true
		fight.targets[#fight.targets + 1] = name
	end
end

local function FightStart()
	fight = {
		start = GetTime(),
		date = date("%Y-%m-%d %H:%M:%S"),
		zone = Where(),
		group = GroupInfo(),
		memStart = collectgarbage("count"),
		fpsSum = 0, samples = 0, platesMax = 0, platesSum = 0,
		targets = {}, targetSet = {}
	}
	if IsProfiling() then
		StartMeasure()
	end
	AddTarget()
	nextSample = 0
	sampler:SetScript("OnUpdate", SamplerOnUpdate)
end

local function FightEnd()
	sampler:SetScript("OnUpdate", nil)
	local f = fight
	fight = nil
	if not f then
		return
	end
	local duration = GetTime() - f.start
	if duration < MIN_FIGHT then
		return
	end
	local entry = {
		date = f.date,
		zone = f.zone,
		group = f.group,
		profile = Profile(),
		player = UnitName("player"),
		duration = floor(duration * 10 + 0.5) / 10,
		fpsMin = f.fpsMin and floor(f.fpsMin * 10 + 0.5) / 10,
		fpsAvg = f.samples > 0 and floor(f.fpsSum / f.samples * 10 + 0.5) / 10 or nil,
		platesMax = f.platesMax,
		platesAvg = f.samples > 0 and floor(f.platesSum / f.samples * 10 + 0.5) / 10 or nil,
		memStartKB = floor(f.memStart),
		memEndKB = floor(collectgarbage("count")),
		targets = table.concat(f.targets, ", "),
		profiling = IsProfiling()
	}
	local list, total = CollectCPU()
	if list then
		entry.cpuTotalMs = floor(total * 10 + 0.5) / 10
		entry.cpu = {}
		for i = 1, math.min(SAVE_TOP, #list) do
			local e = list[i]
			entry.cpu[i] = format("%s %.1f ms (%.2f ms/s)", e.name, e.cpu, e.cpu / duration)
		end
	end
	Push(TPProfDB.fights, entry, MAX_FIGHTS)

	if TPProfDB.fight then
		Print(format("Kampf %.0f s: FPS min %.0f / Schnitt %.0f, Plaketten max %d",
			duration, entry.fpsMin or 0, entry.fpsAvg or 0, entry.platesMax))
		if list then
			Report("Kampf:")
		end
	end
end

-------------------------------------------------------------------------------
-- Fehlerprotokoll mit Zeit und Ort (Swatter speichert keine Zeit und ist voll)
-------------------------------------------------------------------------------
local inHandler = false
local function RecordError(msg)
	if inHandler or not TPProfDB then
		return
	end
	inHandler = true
	msg = tostring(msg)
	local now = date("%Y-%m-%d %H:%M:%S")
	local errors = TPProfDB.errors
	local found
	for i = 1, #errors do
		if errors[i].message == msg then
			found = errors[i]
			break
		end
	end
	if found then
		found.count = found.count + 1
		found.last = now
		found.lastZone = Where()
	else
		Push(errors, {
			message = msg,
			count = 1,
			first = now,
			last = now,
			lastZone = Where(),
			player = UnitName("player"),
			inCombat = InCombatLockdown() and true or false,
			stack = debugstack and strsub(debugstack(4, 12, 0) or "", 1, 1500)
		}, MAX_ERRORS)
	end
	inHandler = false
end

-- Erst nach dem Laden aller Addons einhängen (Swatter setzt seinen Handler beim Laden)
-- und den vorherigen Handler immer weiter aufrufen
local function HookErrors()
	local previous = geterrorhandler()
	seterrorhandler(function(msg, ...)
		pcall(RecordError, msg)
		if previous then
			return previous(msg, ...)
		end
	end)
end

-------------------------------------------------------------------------------
-- Mausblick-Diagnose: Endet der Mausblick, obwohl die rechte Maustaste noch gedrückt
-- ist, wurde er unterbrochen (Kamera springt, Zeiger erscheint). Gespeichert wird, was
-- in dem Moment unter dem Zeiger lag - insbesondere, ob es eine Namensplakette war.
-------------------------------------------------------------------------------
local MAX_MOUSELOOK = 50
local MAX_MOUSELOOK_ALL = 150
local wasLooking = false
local lookStart

-- Rahmen unter dem Zeiger beschreiben; Plakette erkennen (TidyPlates: plate.extended
-- bzw. extended.parentPlate in der Elternkette)
local function DescribeFocus()
	local f = GetMouseFocus()
	if not f then
		return "nichts"
	end
	if f == WorldFrame then
		return "Spielwelt"
	end
	local desc = (f.GetName and f:GetName()) or (f.GetObjectType and f:GetObjectType()) or "?"
	local p = f
	for _ = 1, 5 do
		if not p then
			break
		end
		local ext = p.extended or (p.parentPlate and p)
		if ext then
			local unit = ext.unit
			return "Plakette " .. ((unit and unit.name) or "?"), true
		end
		p = p.GetParent and p:GetParent()
	end
	return desc
end

local function RecordMouselookBreak()
	local desc, onPlate = DescribeFocus()
	TPProfDB.mouselookAll[#TPProfDB.mouselookAll].focus = desc
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	local entry = {
		date = date("%Y-%m-%d %H:%M:%S"),
		zone = Where(),
		player = UnitName("player"),
		inCombat = InCombatLockdown() and true or false,
		focus = desc,
		onPlate = onPlate or false,
		plates = CountPlates(),
		cursor = format("%.0f / %.0f von %.0f / %.0f", x / scale, y / scale, GetScreenWidth(), GetScreenHeight()),
		profile = Profile()
	}
	Push(TPProfDB.mouselook, entry, MAX_MOUSELOOK)
	Print("Mausblick unterbrochen - unter dem Zeiger: " .. desc)
end

local mouselookWatcher = CreateFrame("Frame")
-- Zusätzlich jedes Ende des Mausblicks (auch normales Loslassen) mit Uhrzeit und
-- Tastenzustand, um einen gemeldeten Kamerasprung zeitlich zuordnen zu können
local function RecordMouselookEnd(rmbDown)
	local now = GetTime()
	Push(TPProfDB.mouselookAll, {
		time = date("%H:%M:%S"),
		duration = lookStart and floor((now - lookStart) * 10 + 0.5) / 10 or nil,
		rmbDown = rmbDown and true or false,
		lmbDown = IsMouseButtonDown("LeftButton") and true or false,
		inCombat = InCombatLockdown() and true or false,
		plates = CountPlates()
	}, MAX_MOUSELOOK_ALL)
end

mouselookWatcher:SetScript("OnUpdate", function()
	local looking = IsMouselooking()
	if looking and not wasLooking then
		lookStart = GetTime()
	elseif wasLooking and not looking and TPProfDB then
		local rmbDown = IsMouseButtonDown("RightButton")
		RecordMouselookEnd(rmbDown)
		if rmbDown then
			RecordMouselookBreak()
		end
	end
	wasLooking = looking
end)

-------------------------------------------------------------------------------
-- Events und Befehle
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "TPProf" then
			TPProfDB = TPProfDB or {}
			TPProfDB.fights = TPProfDB.fights or {}
			TPProfDB.errors = TPProfDB.errors or {}
			TPProfDB.mouselook = TPProfDB.mouselook or {}
			TPProfDB.mouselookAll = TPProfDB.mouselookAll or {}
			if IsProfiling() then
				Print("Profiling ist AN (kostet etwas Leistung). Ausschalten: /tpprof off")
				StartMeasure()
			end
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		HookErrors()
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PLAYER_REGEN_DISABLED" then
		FightStart()
		fightStart = startTime
	elseif event == "PLAYER_REGEN_ENABLED" then
		FightEnd()
		fightStart = nil
	elseif event == "PLAYER_TARGET_CHANGED" then
		AddTarget()
	end
end)

SLASH_TPPROF1 = "/tpprof"
SlashCmdList["TPPROF"] = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "on" then
		SetCVar("scriptProfile", "1")
		Print("Profiling eingeschaltet - wirkt nach |cffffff00/reload|r.")
	elseif msg == "off" then
		SetCVar("scriptProfile", "0")
		Print("Profiling ausgeschaltet - wirkt nach |cffffff00/reload|r.")
	elseif msg == "start" or msg == "reset" then
		StartMeasure()
		Print("Messung neu gestartet.")
	elseif msg == "kampf" or msg == "fight" then
		TPProfDB.fight = not TPProfDB.fight
		Print("Bericht im Chat nach jedem Kampf: " .. (TPProfDB.fight and "AN" or "AUS")
			.. " (gespeichert wird immer)")
	elseif msg == "log" then
		Print(format("Gespeichert: %d Kämpfe, %d Fehler, %d Mausblick-Abbrüche (%d Mausblick-Enden). In die Datei geschrieben wird bei /reload oder Ausloggen.",
			#TPProfDB.fights, #TPProfDB.errors, #TPProfDB.mouselook, #TPProfDB.mouselookAll))
	elseif msg == "clear" then
		wipe(TPProfDB.fights)
		wipe(TPProfDB.errors)
		wipe(TPProfDB.mouselook)
		wipe(TPProfDB.mouselookAll)
		Print("Kampf-, Fehler- und Mausblick-Protokoll gelöscht.")
	elseif msg == "" then
		Report()
	else
		Print("/tpprof on | off | start | kampf | log | clear | (leer = Bericht)")
	end
end
