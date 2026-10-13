------------------------------
-- Target Tracker
------------------------------
-- Remembers for known enemies (by GUID) whom they currently have targeted.
-- Sources: own target, focus, pet and the targets of all party/raid members.

local TrackedUnitTargets = {} -- [guid] = name of the enemy's target
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
		for i = 1, numRaid do -- all raid members (previously the last one was missing)
			TrackUnit(raidTargets[i])
		end
	else
		for i = 1, GetNumPartyMembers() do -- 5-man groups were previously not evaluated at all
			TrackUnit(partyTargets[i])
		end
	end

	-- Only update nameplates whose enemy has changed target
	-- (previously: full update of all nameplates on every change)
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

-- UNIT_TARGET/UNIT_THREAT_SITUATION_UPDATE fire practically every frame in raids:
-- rebuild at most 4x per second. Own target/focus immediately (next frame).
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

		-- "Other" tank: yourself doesn't count (own aggro is shown by the threat color)
		if targetOf and TankNames[targetOf] and targetOf ~= PlayerName then
			return true
		end
	end
	return false
end

-- In 3.3.5a UnitGroupRolesAssigned returns three booleans (isTank, isHealer, isDamage)
-- and not a string as in Cataclysm+. The old comparison with "TANK" was therefore always false.
local function IsTankUnit(unitid)
	local isTank = UnitGroupRolesAssigned(unitid)
	return isTank == true or isTank == 1
end

-- Tank stances/forms: self-assembled raids have neither Dungeon Finder roles
-- nor necessarily main tank assignments. The client sees these auras on all
-- group members (names are localized via GetSpellInfo).
local TankAuraIDs = {
	25780, -- Righteous Fury (Paladin)
	71,    -- Defensive Stance (Warrior)
	5487,  -- Bear Form (Druid)
	9634,  -- Dire Bear Form (Druid)
	48263  -- Frost Presence (Death Knight)
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

-- Cache the aura check result per unit; only units whose auras have changed
-- are rechecked (previously: all 25 members on every change)
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
		-- 5-man group: roles from the Dungeon Finder
		for index = 1, GetNumPartyMembers() do
			local partyid = "party" .. index
			local name = UnitName(partyid)
			if name and (IsTankUnit(partyid) or UnitHasTankAura(partyid)) then
				TankNames[name] = true
			end
		end
		-- Own pet counts as a tank outside of raids (Hunter/Warlock)
		if HasPetUI("player") and UnitName("pet") then
			TankNames[UnitName("pet")] = true
		end
	end

	-- Only update nameplates if the tank list has actually changed
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

-- Auras change constantly in raids: rebuild the tank list at most 2x per second,
-- and only if something has changed on a group member
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
	-- Group/roles changed: unit IDs may now refer to different players
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
