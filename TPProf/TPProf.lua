-- TPProf: misst die CPU-Zeit pro Addon über WoWs eingebautes Profiling.
-- Das Profiling (CVar scriptProfile) kostet selbst etwas Leistung und wirkt erst nach /reload,
-- deshalb nur zum Messen einschalten und danach wieder aus.
--
-- /tpprof on      Profiling einschalten (danach /reload)
-- /tpprof off     Profiling ausschalten (danach /reload)
-- /tpprof start   Messung neu starten
-- /tpprof         Bericht seit dem letzten Start
-- /tpprof kampf   Automatisch: Messung bei Kampfbeginn starten, Bericht bei Kampfende

local PREFIX = "|cff33ff99TPProf:|r "
local TOP = 10
local MIN_FIGHT = 5 -- kürzere Kämpfe nicht berichten

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
	UpdateAddOnCPUUsage()

	local list, total = {}, 0
	for i = 1, GetNumAddOns() do
		if IsAddOnLoaded(i) then
			local cpu = GetAddOnCPUUsage(i)
			if cpu > 0 then
				list[#list + 1] = {name = (GetAddOnInfo(i)), cpu = cpu}
				total = total + cpu
			end
		end
	end
	table.sort(list, function(a, b) return a.cpu > b.cpu end)

	Print(format("%s %.1f s, alle Addons zusammen %.0f ms (%.1f ms pro Sekunde)",
		label or "Messung über", duration, total, total / duration))
	for i = 1, math.min(TOP, #list) do
		local e = list[i]
		Print(format("%2d. %-28s %7.1f ms  %5.2f ms/s  %4.1f%%",
			i, e.name, e.cpu, e.cpu / duration, total > 0 and e.cpu / total * 100 or 0))
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "TPProf" then
			TPProfDB = TPProfDB or {}
			if IsProfiling() then
				Print("Profiling ist AN (kostet etwas Leistung). Ausschalten: /tpprof off")
				StartMeasure()
			end
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif not (TPProfDB and TPProfDB.fight and IsProfiling()) then
		return
	elseif event == "PLAYER_REGEN_DISABLED" then
		StartMeasure()
		fightStart = startTime
	elseif event == "PLAYER_REGEN_ENABLED" and fightStart then
		if GetTime() - fightStart >= MIN_FIGHT then
			Report("Kampf:")
		end
		fightStart = nil
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
		Print("Automatischer Bericht nach jedem Kampf: " .. (TPProfDB.fight and "AN" or "AUS"))
	elseif msg == "" then
		Report()
	else
		Print("/tpprof on | off | start | kampf | (leer = Bericht)")
	end
end
