------------------------------
-- Target Tracker
------------------------------
-- Merkt sich für bekannte Gegner (per GUID), wen sie gerade im Ziel haben.
-- Quellen: eigenes Ziel, Fokus, Pet und die Ziele aller Gruppen-/Raidmitglieder.

local TrackedUnitTargets = {} -- [guid] = Name des Ziels des Gegners
local NewTrackedUnitTargets = {}
local TargetWatcher
local TargetsDirty = false

local partyTargets, raidTargets = {}, {}
for i = 1, 4 do partyTargets[i] = "party" .. i .. "target" end
for i = 1, 40 do raidTargets[i] = "raid" .. i .. "target" end

local function TrackUnit(unitid)
	local guid = UnitGUID(unitid)
	if guid and not NewTrackedUnitTargets[guid] then
		NewTrackedUnitTargets[guid] = UnitName(unitid .. "target") or false
	end
end

local function RequestPlateUpdate(guid)
	local plate = TidyPlates.NameplatesByGUID and TidyPlates.NameplatesByGUID[guid]
	if plate and TidyPlates.RequestDelegateUpdateForPlate then
		TidyPlates:RequestDelegateUpdateForPlate(plate)
	end
end

local function RebuildTrackedTargets()
	TargetsDirty = false
	wipe(NewTrackedUnitTargets)

	TrackUnit("target")
	TrackUnit("focus")
	TrackUnit("pettarget")

	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do -- alle Raidmitglieder (vorher fehlte das letzte)
			TrackUnit(raidTargets[i])
		end
	else
		for i = 1, GetNumPartyMembers() do -- 5er-Gruppen wurden vorher gar nicht ausgewertet
			TrackUnit(partyTargets[i])
		end
	end

	-- Nur Plaketten aktualisieren, deren Gegner das Ziel gewechselt hat
	-- (vorher: Komplett-Update aller Plaketten bei jeder Änderung)
	for guid, targetName in pairs(NewTrackedUnitTargets) do
		if TrackedUnitTargets[guid] ~= targetName then
			RequestPlateUpdate(guid)
		end
	end
	for guid in pairs(TrackedUnitTargets) do
		if NewTrackedUnitTargets[guid] == nil then
			RequestPlateUpdate(guid)
		end
	end

	TrackedUnitTargets, NewTrackedUnitTargets = NewTrackedUnitTargets, TrackedUnitTargets
end

-- UNIT_TARGET/UNIT_THREAT_SITUATION_UPDATE feuern im Raid praktisch jeden Frame:
-- höchstens 4x pro Sekunde neu aufbauen. Eigenes Ziel/Fokus sofort (nächster Frame).
local TARGET_REBUILD_INTERVAL = 0.25
local nextTargetRebuild = 0
local function TargetWatcherOnUpdate(self)
	local now = GetTime()
	if now < nextTargetRebuild then
		return
	end
	nextTargetRebuild = now + TARGET_REBUILD_INTERVAL
	self:SetScript("OnUpdate", nil)
	RebuildTrackedTargets()
end

local function TargetWatcherEvents(self, event)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		nextTargetRebuild = 0
	end
	if not TargetsDirty then
		TargetsDirty = true
		self:SetScript("OnUpdate", TargetWatcherOnUpdate)
	end
end

---------------
-- Tank Monitor
---------------
local TankNames = {}
local TankWatcher
local PlayerName

local function IsTankedByAnotherTank(unit)
	local targetOf
	PlayerName = PlayerName or UnitName("player")
	if unit.guid then
		if unit.isTarget then
			targetOf = UnitName("targettarget") -- Nameplate is a target
		elseif unit.isMouseover then
			targetOf = UnitName("mouseovertarget") -- Nameplate is a mouseover
		else
			targetOf = TrackedUnitTargets[unit.guid]
		end

		-- "Anderer" Tank: man selbst zählt nicht (eigene Aggro zeigt die Bedrohungsfarbe)
		if targetOf and TankNames[targetOf] and targetOf ~= PlayerName then
			return true
		end
	end
	return false
end

-- In 3.3.5a liefert UnitGroupRolesAssigned drei Booleans (isTank, isHealer, isDamage)
-- und keinen Text wie ab Cataclysm. Der alte Vergleich mit "TANK" war daher immer falsch.
local function IsTankUnit(unitid)
	local isTank = UnitGroupRolesAssigned(unitid)
	return isTank == true or isTank == 1
end

-- Tank-Haltungen/-Gestalten: In selbst gebauten Raids gibt es weder Dungeonfinder-Rollen
-- noch zwingend Main-Tank-Zuweisungen. Diese Auren erkennt der Client bei allen
-- Gruppenmitgliedern (Namen werden über GetSpellInfo lokalisiert).
local TankAuraIDs = {
	25780, -- Zorn der Gerechtigkeit (Paladin)
	71,    -- Verteidigungshaltung (Krieger)
	5487,  -- Bärengestalt (Druide)
	9634,  -- Terrorbärengestalt (Druide)
	48263  -- Frostpräsenz (Todesritter)
}
local TankAuraNames
local function HasTankAura(unitid)
	if not TankAuraNames then
		TankAuraNames = {}
		for _, id in ipairs(TankAuraIDs) do
			local name = GetSpellInfo(id)
			if name then
				TankAuraNames[#TankAuraNames + 1] = name
			end
		end
	end
	for i = 1, #TankAuraNames do
		if UnitAura(unitid, TankAuraNames[i]) then
			return true
		end
	end
	return false
end

-- Ergebnis der Aura-Prüfung pro Einheit merken; neu geprüft wird nur eine Einheit,
-- deren Auren sich geändert haben (vorher: alle 25 Mitglieder bei jeder Änderung)
local AuraTankCache, AuraDirtyUnits = {}, {}
local function UnitHasTankAura(unitid)
	local v = AuraTankCache[unitid]
	if v == nil or AuraDirtyUnits[unitid] then
		v = HasTankAura(unitid)
		AuraTankCache[unitid] = v
		AuraDirtyUnits[unitid] = nil
	end
	return v
end

local OldTankNames = {}
local function TankWatcherEvents()
	OldTankNames, TankNames = TankNames, OldTankNames
	wipe(TankNames)

	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for index = 1, numRaid do
			local raidid = "raid" .. index
			local name = UnitName(raidid)
			if name and (GetPartyAssignment("MAINTANK", raidid) or GetPartyAssignment("MAINASSIST", raidid)
				or IsTankUnit(raidid) or UnitHasTankAura(raidid)) then
				TankNames[name] = true
			end
		end
	else
		-- 5er-Gruppe: Rollen aus dem Dungeonfinder
		for index = 1, GetNumPartyMembers() do
			local partyid = "party" .. index
			local name = UnitName(partyid)
			if name and (IsTankUnit(partyid) or UnitHasTankAura(partyid)) then
				TankNames[name] = true
			end
		end
		-- Eigenes Pet gilt außerhalb von Raids als Tank (Jäger/Hexer)
		if HasPetUI("player") and UnitName("pet") then
			TankNames[UnitName("pet")] = true
		end
	end

	-- Plaketten nur aktualisieren, wenn sich die Tank-Liste tatsächlich geändert hat
	local changed = false
	for name in pairs(TankNames) do
		if not OldTankNames[name] then
			changed = true
			break
		end
	end
	if not changed then
		for name in pairs(OldTankNames) do
			if not TankNames[name] then
				changed = true
				break
			end
		end
	end
	if changed and TidyPlates.RequestDelegateUpdate then
		TidyPlates:RequestDelegateUpdate()
	end
end

-- Auren ändern sich im Raid ständig: Tank-Liste höchstens 2x pro Sekunde neu aufbauen,
-- und nur, wenn sich bei einem Gruppenmitglied etwas geändert hat
local TANK_AURA_INTERVAL = 0.5
local auraDirty, nextAuraCheck = false, 0
local function TankWatcherOnUpdate(self)
	if auraDirty and GetTime() >= nextAuraCheck then
		auraDirty = false
		nextAuraCheck = GetTime() + TANK_AURA_INTERVAL
		TankWatcherEvents()
	end
end

local function TankWatcherOnEvent(self, event, unitid)
	if event == "UNIT_AURA" then
		if unitid and (unitid:find("^raid%d") or unitid:find("^party%d")) then
			AuraDirtyUnits[unitid] = true
			auraDirty = true
		end
		return
	end
	-- Gruppe/Rollen geändert: Einheiten-IDs können jetzt andere Spieler sein
	wipe(AuraTankCache)
	TankWatcherEvents()
end

local function EnableTankWatch()
	if not TargetWatcher then
		TargetWatcher = CreateFrame("Frame")
	end
	TargetWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	TargetWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	TargetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	TargetWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
	TargetWatcher:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	TargetWatcher:RegisterEvent("UNIT_TARGET")
	TargetWatcher:SetScript("OnEvent", TargetWatcherEvents)
	RebuildTrackedTargets()

	if not TankWatcher then
		TankWatcher = CreateFrame("Frame")
	end
	TankWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
	TankWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
	TankWatcher:RegisterEvent("PARTY_CONVERTED_TO_RAID")
	TankWatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	TankWatcher:RegisterEvent("UNIT_PET")
	TankWatcher:RegisterEvent("UNIT_AURA")
	TankWatcher:SetScript("OnEvent", TankWatcherOnEvent)
	TankWatcher:SetScript("OnUpdate", TankWatcherOnUpdate)
	TankWatcherEvents()
end

local function DisableTankWatch()
	if TargetWatcher then
		TargetWatcher:SetScript("OnEvent", nil)
		TargetWatcher:SetScript("OnUpdate", nil)
		TargetWatcher:UnregisterAllEvents()
		TargetWatcher = nil
		TargetsDirty = false
	end

	if TankWatcher then
		TankWatcher:SetScript("OnEvent", nil)
		TankWatcher:SetScript("OnUpdate", nil)
		TankWatcher:UnregisterAllEvents()
		TankWatcher = nil
	end
end

TidyPlatesWidgets.EnableTankWatch = EnableTankWatch
TidyPlatesWidgets.DisableTankWatch = DisableTankWatch
TidyPlatesWidgets.IsTankedByAnotherTank = IsTankedByAnotherTank
